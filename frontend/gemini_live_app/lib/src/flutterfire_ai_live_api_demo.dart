import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    model: 'gemini-live-2.5-flash-native-audio',
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeAudio();
      await _initializeVideo();

      // Auto-start 24/7 streams
      if (_audioIsInitialized) {
        await startAudioStream();
        if (_videoIsInitialized) {
          startVideoStream();
        }
      }
    });
  }

  @override
  void dispose() {
    _sessionWatchdog?.cancel();
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

  void toggleAudioStream() async {
    _audioStreamIsActive ? await stopAudioStream() : await startAudioStream();
  }

  Future<void> startAudioStream() async {
    await _toggleLiveSession();

    final audioInput = ref.read(audioInputProvider);
    final audioOutput = ref.read(audioOutputProvider);

    var audioInputStream = await audioInput.startRecordingStream();
    log('Audio input stream is recording!');

    await audioOutput.playStream();
    log('Audio output stream is playing!');

    setState(() {
      _audioStreamIsActive = true;
    });

    _session.sendMediaStream(
      audioInputStream.map((data) {
        return InlineDataPart('audio/pcm', data);
      }),
    );
  }

  Future<void> stopAudioStream() async {
    if (_cameraIsActive) {
      stopVideoStream();
    }

    await ref.read(audioInputProvider).stopRecording();
    await ref.read(audioOutputProvider).stopStream();

    await _toggleLiveSession();

    setState(() {
      _audioStreamIsActive = false;
    });
  }

  Future<void> toggleMuteInput() async {
    await ref.read(audioInputProvider).togglePauseRecording();
  }

  Future<void> _initializeVideo() async {
    try {
      await ref.read(videoInputProvider).init();

      setState(() {
        _videoIsInitialized = true;
      });
    } catch (e) {
      log("Error during video initialization: $e");
    }
  }

  void startVideoStream() {
    if (!_videoIsInitialized || !_audioStreamIsActive || _cameraIsActive) {
      return;
    }

    Stream<Uint8List> imageStream =
        ref.read(videoInputProvider).startStreamingImages();

    _session.sendMediaStream(
      imageStream.map((data) {
        return InlineDataPart("image/jpeg", data);
      }),
    );

    setState(() {
      _cameraIsActive = true;
    });
  }

  void stopVideoStream() async {
    await ref.read(videoInputProvider).stopStreamingImages();

    setState(() {
      _cameraIsActive = false;
    });
  }

  void toggleVideoStream() async {
    _cameraIsActive ? stopVideoStream() : startVideoStream();
  }

  void toggleYoloMode(bool val) async {
    setState(() {
      _isYoloMode = val;
      _detections = [];
    });

    if (_isYoloMode) {
      // Pause Vertex AI audio/video if active
      if (_audioStreamIsActive) {
        await stopAudioStream();
      }

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

      // Resume Vertex AI if it was active (or just let the user re-enable)
      // For now, just stop everything and let the user click call if they want
    }
  }

  Future<void> _toggleLiveSession() async {
    setState(() {
      _settingUpLiveSession = true;
    });

    if (!_liveSessionIsOpen) {
      _session = await _liveModel.connect();
      _liveSessionIsOpen = true;

      _lastModelResponse = DateTime.now();

      _sessionWatchdog?.cancel();
      _sessionWatchdog = Timer.periodic(const Duration(seconds: 10), (timer) {
        final diff = DateTime.now().difference(_lastModelResponse).inSeconds;

        if (diff > 25 && _liveSessionIsOpen) {
          log("Gemini session stalled. Restarting session...");

          stopVideoStream();
          stopAudioStream();
          startAudioStream();
        }
      });

      unawaited(processMessagesContinuously());
    } else {
      await _session.close();
      _liveSessionIsOpen = false;
      _sessionWatchdog?.cancel();
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
    log('Text message from Gemini: ${part.text}');
  }

  Future<void> _handleTurnComplete() async {
    log('Model is done generating. Turn complete!');
  }

  Future<void> _handleLiveServerToolCall(LiveServerToolCall response) async {
    if (response.functionCalls?.isNotEmpty ?? false) {
      log("Gemini made a function call!");
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioInput = ref.watch(audioInputProvider);
    final videoInput = ref.watch(videoInputProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leadingWidth: 100,
        leading: const LeafAppIcon(),
        title: const AppTitle(title: 'CogniVision'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background Design
          const _LuxuryBackground(),

          SafeArea(
            child: _cameraIsActive
                ? Center(
                    child: FullCameraPreview(
                      controller: videoInput.cameraController,
                    ),
                  )
                : CenterCircle(
                    isListening: _audioStreamIsActive && !audioInput.isPaused,
                    isSpeaking:
                        false, // Could be updated based on model response activity
                    child: Padding(
                      padding: const EdgeInsets.all(60),
                      child: _settingUpLiveSession
                          ? CircularProgressIndicator(
                              color: Theme.of(context).colorScheme.primary,
                            )
                          : Icon(
                              size: 48,
                              Icons.auto_awesome_rounded,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.8),
                            )
                              .animate(onPlay: (c) => c.repeat(reverse: true))
                              .scale(
                                  begin: const Offset(0.9, 0.9),
                                  end: const Offset(1.1, 1.1),
                                  duration: 2.seconds),
                    ),
                  ),
          ),

          Positioned(
            right: 20,
            bottom: 120, // Adjusted to be above the bottom nav bar
            child: Column(
              children: [
                _FloatingGlassToggle(
                  icon: _cameraIsActive
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  isActive: _cameraIsActive,
                  onPressed: toggleVideoStream,
                ),
                const SizedBox(height: 15),
                _FloatingGlassToggle(
                  icon: audioInput.isPaused
                      ? Icons.mic_off_rounded
                      : Icons.mic_rounded,
                  isActive: !audioInput.isPaused,
                  onPressed: _audioStreamIsActive ? toggleMuteInput : null,
                ),
              ],
            ),
          ),

          // YOLO Detections Overlay
          if (_isYoloMode && _detections.isNotEmpty)
            Positioned(
              top: 100,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _detections
                      .map((d) => Text(
                            '${d.label} (${(d.confidence * 100).toStringAsFixed(0)}%)',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16),
                          ))
                      .toList(),
                ),
              ).animate().fadeIn(),
            ),

          Positioned(
            left: 20,
            top: MediaQuery.of(context).size.height / 3.5,
            child: VerticalSwitch(
              initialValue: _isYoloMode,
              onChanged: toggleYoloMode,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingGlassToggle extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback? onPressed;

  const _FloatingGlassToggle({
    required this.icon,
    required this.isActive,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isActive
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)
                  : Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Icon(
              icon,
              color: isActive
                  ? Colors.white
                  : Theme.of(context).colorScheme.primary,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

class _LuxuryBackground extends StatelessWidget {
  const _LuxuryBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7F2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF5F7F2),
            Color(0xFFEAF5EE),
            Color(0xFFDDEFE5),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Blurred Blobs
          Positioned(
            top: -100,
            right: -50,
            child: _Blob(
              color: const Color(0xFFCFE7DA).withOpacity(0.5),
              size: 300,
            ),
          ),
          Positioned(
            bottom: 100,
            left: -50,
            child: _Blob(
              color: const Color(0xFFD4B06A).withOpacity(0.1),
              size: 400,
            ),
          ),
          // Faint Gold Particles (Mockup with subtle dots)
          const IgnorePointer(
            child: Opacity(
              opacity: 0.05,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(
                        'https://www.transparenttextures.com/patterns/stardust.png'),
                    repeat: ImageRepeat.repeat,
                  ),
                ),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;

  const _Blob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).move(
        begin: const Offset(-20, -20),
        end: const Offset(20, 20),
        duration: 10.seconds,
        curve: Curves.easeInOut);
  }
}
