import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'ui_components/ui_components.dart';
import 'providers.dart';
import 'utilities/yolo_detector.dart';
import 'services/tts_service.dart';

class FlutterFireAILiveAPIDemo extends ConsumerStatefulWidget {
  const FlutterFireAILiveAPIDemo({super.key});

  @override
  ConsumerState<FlutterFireAILiveAPIDemo> createState() => _MyHomePageState();
}

class _MyHomePageState extends ConsumerState<FlutterFireAILiveAPIDemo> {
  bool _audioIsInitialized = false;
  bool _videoIsInitialized = false;

  final LiveGenerativeModel _liveModel =
      FirebaseAI.vertexAI().liveGenerativeModel(
    model: 'gemini-2.0-flash-exp',
    systemInstruction: Content.text(
      'You are cogni, a  helpful visual assistant for visually impaired users. '
      'Your job is to help the user understand their surroundings. '
      'When the user asks what you see, describe objects, people, text, '
      'hazards, or anything relevant in their environment clearly and concisely. '
      'Greet the user and let them know you are ready to help them navigate '
      'and understand their surroundings. Ask them to turn on their camera '
      'so you can see what is around them.',
    ),
    liveGenerationConfig: LiveGenerationConfig(
      speechConfig: SpeechConfig(voiceName: 'Puck'),
      responseModalities: [ResponseModalities.audio],
    ),
  );

  late LiveSession _session;

  bool _settingUpLiveSession = false;
  bool _liveSessionIsOpen = false;
  bool _audioStreamIsActive = false;
  bool _cameraIsActive = false;

  DateTime _lastModelResponse = DateTime.now();
  Timer? _sessionWatchdog;

  bool _isYoloMode = false;
  final YoloDetector _yoloDetector = YoloDetector();
  final TtsService _ttsService = TtsService();
  StreamSubscription? _yoloSubscription;
  List<DetectionResult> _detections = [];

  // Unified Media Pipe for Gemini (Audio + Video)
  StreamController<InlineDataPart>? _combinedMediaController;
  StreamSubscription<Uint8List>? _micSubscription;
  StreamSubscription<Uint8List>? _cameraSubscription;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeAudio();
      await _initializeVideo();

      // Set initial state for provider if this is the active tab
      // but let the MainNavigationWrapper handle the logic
    });
  }

  @override
  void dispose() {
    _sessionWatchdog?.cancel();
    _combinedMediaController?.close();
    _micSubscription?.cancel();
    _cameraSubscription?.cancel();
    
    ref.read(audioInputProvider).dispose();
    ref.read(audioOutputProvider).dispose();
    ref.read(videoInputProvider).dispose();
    _yoloSubscription?.cancel();
    _yoloDetector.dispose();
    _ttsService.dispose();

    if (_liveSessionIsOpen) {
      unawaited(_session.close());
    }

    super.dispose();
  }

  Future<void> _initializeAudio() async {
    try {
      await ref.read(audioInputProvider).init();
      await ref.read(audioOutputProvider).init();

      setState(() {
        _audioIsInitialized = true;
      });
    } catch (e) {
      log("Error during audio initialization: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Oops! Something went wrong with audio setup.'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: _initializeAudio,
          ),
        ),
      );
    }
  }

  Future<void> _initializeVideo() async {
    try {
      await ref.read(videoInputProvider).init();

      setState(() {
        _videoIsInitialized = true;
      });
    } catch (e) {
      log("Error during video initialization: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Oops! Something went wrong with video setup.'),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: _initializeVideo,
          ),
        ),
      );
    }
  }

  void toggleAudioStream() async {
    if (_audioStreamIsActive) {
      await stopAudioStream();
    } else {
      await startAudioStream();
    }
  }

  Future<void> startAudioStream() async {
    if (!_liveSessionIsOpen) {
      await _toggleLiveSession();
    }

    final audioInput = ref.read(audioInputProvider);
    final audioOutput = ref.read(audioOutputProvider);

    // Initialize the UNIFIED pipe if it doesn't exist
    if (_combinedMediaController == null || _combinedMediaController!.isClosed) {
      _combinedMediaController = StreamController<InlineDataPart>();
      _session.sendMediaStream(_combinedMediaController!.stream);
    }

    // Start Microphone and feed into Unified Pipe
    var micStream = await audioInput.startRecordingStream();
    _micSubscription?.cancel();
    _micSubscription = micStream.listen((data) {
      if (_combinedMediaController != null && !_combinedMediaController!.isClosed) {
        _combinedMediaController!.add(InlineDataPart('audio/pcm;rate=16000', data));
      }
    });

    log('Voice is now flowing into Unified Pipe.');
    await audioOutput.playStream();

    setState(() {
      _audioStreamIsActive = true;
    });
  }

  Future<void> stopAudioStream() async {
    _micSubscription?.cancel();
    _micSubscription = null;
    
    await ref.read(audioInputProvider).stopRecording();

    setState(() {
      _audioStreamIsActive = false;
    });
  }

  void toggleVideoStream() async {
    if (_cameraIsActive) {
      await stopVideoStream();
    } else {
      await startVideoStream();
    }
  }

  Future<void> startVideoStream() async {
    if (!_liveSessionIsOpen) {
      await _toggleLiveSession();
    }

    final videoInput = ref.read(videoInputProvider);
    if (!videoInput.isInitialized) {
      log("Camera not initialized yet. Please wait.");
      return;
    }

    // Ensure pipe exists
    if (_combinedMediaController == null || _combinedMediaController!.isClosed) {
      _combinedMediaController = StreamController<InlineDataPart>();
      _session.sendMediaStream(_combinedMediaController!.stream);
    }

    _cameraSubscription?.cancel();
    _cameraSubscription = videoInput.startStreamingImages().listen((image) {
      // 1. Feed into Gemini Unified Pipe
      if (_combinedMediaController != null && !_combinedMediaController!.isClosed && _cameraIsActive) {
        _combinedMediaController!.add(InlineDataPart('image/jpeg', image));
      }

      // 2. Feed into local YOLO detector
      if (_isYoloMode) {
        _yoloDetector.detect(image);
      }

      if (mounted) setState(() {});
    });

    setState(() {
      _cameraIsActive = true;
    });
  }

  Future<void> stopVideoStream() async {
    _cameraSubscription?.cancel();
    _cameraSubscription = null;
    await ref.read(videoInputProvider).stopStreamingImages();

    setState(() {
      _cameraIsActive = false;
    });
  }

  void toggleYoloMode(bool val) async {
    setState(() {
      _isYoloMode = val;
      _detections = [];
    });

    if (_isYoloMode) {
      // Stop Gemini streams to focus on YOLO
      if (_audioStreamIsActive) await stopAudioStream();
      if (_cameraIsActive) await stopVideoStream();

      await _yoloDetector.init();
      await _ttsService.init();

      _yoloSubscription = ref
          .read(videoInputProvider)
          .startStreamingImages()
          .listen((jpeg) async {
        final results = await _yoloDetector.detect(jpeg);
        setState(() {
          _detections = results;
        });
        await _ttsService.announceDetections(results);
      });
    } else {
      _yoloSubscription?.cancel();
      _yoloSubscription = null;
      await _ttsService.stop();
    }
  }

  Future<void> _toggleLiveSession() async {
    setState(() {
      _settingUpLiveSession = true;
    });

    if (!_liveSessionIsOpen) {
      try {
        _session = await _liveModel.connect();
        _liveSessionIsOpen = true;
        log("Gemini Live Session Connected Successfully!");
      } catch (e) {
        log("Failed to connect to Gemini: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Cloud Connection Failed: ${e.toString().split('\n').first}")),
          );
        }
        setState(() => _settingUpLiveSession = false);
        return;
      }

      _lastModelResponse = DateTime.now();

      _sessionWatchdog?.cancel();
      _sessionWatchdog = Timer.periodic(const Duration(seconds: 10), (timer) {
        final diff = DateTime.now().difference(_lastModelResponse).inSeconds;

        if (diff > 25 && _liveSessionIsOpen) {
          log("Gemini session stalled. Restarting session...");

          Future.microtask(() async {
            await stopVideoStream();
            await stopAudioStream();
            await startAudioStream();
          });
        }
      });

      unawaited(processMessagesContinuously());
    } else {
      await _session.close();
      _liveSessionIsOpen = false;
      _sessionWatchdog?.cancel();
      
      await _combinedMediaController?.close();
      _combinedMediaController = null;
    }

    setState(() {
      _settingUpLiveSession = false;
    });
  }

  Future<void> processMessagesContinuously() async {
    try {
      await for (final response in _session.receive()) {
        LiveServerMessage message = response.message;
        await _handleLiveServerMessage(message);
      }

      log('Live session receive stream completed.');
    } catch (e) {
      log('Error receiving live session messages: $e');
    }
  }

  Future<void> _handleLiveServerMessage(LiveServerMessage response) async {
    _lastModelResponse = DateTime.now();

    if (response is LiveServerContent) {
      if (response.modelTurn != null) {
        await _handleLiveServerContent(response);
      }

      if (response.turnComplete != null && response.turnComplete!) {
        await _handleTurnComplete();
      }

      if (response.interrupted != null && response.interrupted!) {
        log('Interrupted: $response');
      }
    }

    if (response is LiveServerToolCall && response.functionCalls != null) {
      await _handleLiveServerToolCall(response);
    }
  }

  Future<void> _handleLiveServerContent(LiveServerContent response) async {
    final partList = response.modelTurn?.parts;

    if (partList != null) {
      for (final part in partList) {
        switch (part) {
          case TextPart textPart:
            await _handleTextPart(textPart);

          case InlineDataPart inlineDataPart:
            await _handleInlineDataPart(inlineDataPart);

          default:
            log('Received part with type ${part.runtimeType}');
        }
      }
    }
  }

  Future<void> _handleInlineDataPart(InlineDataPart part) async {
    if (part.mimeType.startsWith('audio')) {
      ref.read(audioOutputProvider).addDataToAudioStream(part.bytes);
    }
  }

  Future<void> _handleTextPart(TextPart part) async {
    log('Received text part: ${part.text}');
  }

  Future<void> _handleTurnComplete() async {
    log('Turn complete.');
  }

  Future<void> _handleLiveServerToolCall(LiveServerToolCall response) async {
    log('Received tool call: $response');
  }

  @override
  Widget build(BuildContext context) {
    // Listen for activation state changes
    ref.listen<bool>(vertexActiveProvider, (previous, next) async {
      if (next) {
        if (_audioIsInitialized && !_audioStreamIsActive) {
          await startAudioStream();
          if (_videoIsInitialized && !_cameraIsActive) {
            await startVideoStream();
          }
        }
      } else {
        if (_audioStreamIsActive) {
          await stopAudioStream();
        }
        if (_cameraIsActive) {
          await stopVideoStream();
        }
      }
    });

    final audioInput = ref.read(audioInputProvider);
    final videoInput = ref.read(videoInputProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'COGNIVISION',
          style: TextStyle(
            color: Color(0xFF20563F),
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF20563F).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.eco_rounded, color: Color(0xFF20563F), size: 20),
          ),
        ),
      ),
      body: Stack(
        children: [
          const LuxuryBackground(),
          
          // Camera Preview / AI Viewport
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              height: MediaQuery.of(context).size.height * 0.65,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.4),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: const Color(0xFF20563F).withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  )
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: Stack(
                  children: [
                    // Camera Feed (Native Smooth Preview)
                    if (_cameraIsActive && videoInput.isInitialized)
                      SizedBox.expand(
                        child: CameraPreview(videoInput.cameraController),
                      )
                    else
                      const Center(
                        child: Icon(Icons.videocam_off_rounded, size: 80, color: Colors.black12),
                      ),
                    
                    // YOLO Overlay
                    if (_isYoloMode)
                      CustomPaint(
                        painter: YoloPainter(_detections),
                        size: Size.infinite,
                      ),

                    // Status Indicator
                    Positioned(
                      top: 20,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                            ).animate(onPlay: (controller) => controller.repeat())
                             .fadeIn(duration: 500.ms)
                             .fadeOut(delay: 500.ms, duration: 500.ms),
                            const SizedBox(width: 8),
                            Text(
                              _isYoloMode ? "VISION ACTIVE" : (_liveSessionIsOpen ? "LIVE SESSION" : "IDLE"),
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Control Buttons
          Positioned(
            bottom: 120,
            right: 30,
            child: Column(
              children: [
                // Camera Toggle
                _buildActionButton(
                  icon: _cameraIsActive ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                  isActive: _cameraIsActive,
                  onTap: toggleVideoStream,
                ),
                const SizedBox(height: 20),
                // Mic Toggle
                _buildActionButton(
                  icon: _audioStreamIsActive ? Icons.mic_rounded : Icons.mic_off_rounded,
                  isActive: _audioStreamIsActive,
                  onTap: toggleAudioStream,
                ),
              ],
            ),
          ),

          // AI Mode Selector
          Positioned(
            bottom: 40,
            left: 30,
            child: Row(
              children: [
                _buildModeSwitch("YOLO", _isYoloMode, toggleYoloMode),
                const SizedBox(width: 15),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required bool isActive, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF20563F) : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            )
          ],
          border: Border.all(color: const Color(0xFF20563F).withOpacity(isActive ? 0 : 0.2)),
        ),
        child: Icon(icon, color: isActive ? Colors.white : const Color(0xFF20563F)),
      ),
    );
  }

  Widget _buildModeSwitch(String label, bool value, Function(bool) onChanged) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF20563F))),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF20563F),
        ),
      ],
    );
  }
}

class YoloPainter extends CustomPainter {
  final List<DetectionResult> detections;
  YoloPainter(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (var detection in detections) {
      final rect = Rect.fromLTWH(
        detection.rect.left * size.width,
        detection.rect.top * size.height,
        detection.rect.width * size.width,
        detection.rect.height * size.height,
      );
      canvas.drawRect(rect, paint);

      textPainter.text = TextSpan(
        text: '${detection.label} ${(detection.confidence * 100).toStringAsFixed(0)}%',
        style: const TextStyle(color: Colors.redAccent, backgroundColor: Colors.white, fontSize: 12),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(rect.left, rect.top - 15));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
