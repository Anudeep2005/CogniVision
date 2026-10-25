import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'ui_components/ui_components.dart';
import 'providers.dart';
import 'utilities/yolo_detector.dart';
import 'utilities/video_input.dart' show RawFrame, VideoInput;
import 'services/tts_service.dart';

class FlutterFireAILiveAPIDemo extends ConsumerStatefulWidget {
  const FlutterFireAILiveAPIDemo({super.key});

  @override
  ConsumerState<FlutterFireAILiveAPIDemo> createState() => _MyHomePageState();
}

class _MyHomePageState extends ConsumerState<FlutterFireAILiveAPIDemo> {
  final LiveGenerativeModel _liveModel =
      FirebaseAI.vertexAI().liveGenerativeModel(
    model: 'gemini-2.0-flash-exp',
    systemInstruction: Content.text(
      'You are cogni, a helpful visual assistant for visually impaired users. '
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

  bool _liveSessionIsOpen = false;
  bool _audioStreamIsActive = false;
  bool _cameraIsActive = false;

  DateTime _lastModelResponse = DateTime.now();
  Timer? _sessionWatchdog;

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

      // If vertex tab is active on mount, bootstrap the initial mode
      if (ref.read(vertexActiveProvider)) {
        await _handleModeSwitch(ref.read(aiModeProvider));
      }
    });
  }

  @override
  void dispose() {
    _sessionWatchdog?.cancel();
    _combinedMediaController?.close();
    _micSubscription?.cancel();
    _cameraSubscription?.cancel();
    _yoloSubscription?.cancel();

    ref.read(audioInputProvider).dispose();
    ref.read(audioOutputProvider).dispose();
    ref.read(videoInputProvider).dispose();
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

  /// Authoritative coordinator for switching AI modes with strict mutual exclusion.
  Future<void> _handleModeSwitch(AiMode targetMode) async {
    final currentMode = ref.read(aiModeProvider);
    final transitionState = ref.read(modeTransitionProvider);

    // Prevent re-entrant transitions and redundant switches
    if (transitionState == ModeTransitionState.transitioning) return;
    if (currentMode == targetMode && transitionState == ModeTransitionState.active) return;

    ref.read(modeTransitionProvider.notifier).state = ModeTransitionState.transitioning;
    if (mounted) setState(() {});

    try {
      // 1. Teardown active mode
      if (currentMode == AiMode.localYolo) {
        await _teardownYolo();
      } else {
        await _teardownGemini();
      }

      // 2. Setup incoming mode
      if (targetMode == AiMode.localYolo) {
        await _setupYolo();
      } else {
        await _setupGemini();
      }

      ref.read(aiModeProvider.notifier).state = targetMode;
      ref.read(modeTransitionProvider.notifier).state = ModeTransitionState.active;
    } catch (e, st) {
      log("Mode switch error: $e\n$st");
      ref.read(modeTransitionProvider.notifier).state = ModeTransitionState.error;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              targetMode == AiMode.cloudGemini
                  ? "Cloud Gemini unavailable: ${e.toString().split('\n').first}. Fallback to Local YOLO."
                  : "YOLO setup failed: ${e.toString().split('\n').first}",
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }

      // Safe recovery: fall back to Local YOLO if cloud failed
      if (targetMode == AiMode.cloudGemini) {
        try {
          await _setupYolo();
          ref.read(aiModeProvider.notifier).state = AiMode.localYolo;
          ref.read(modeTransitionProvider.notifier).state = ModeTransitionState.active;
        } catch (fallbackError) {
          log("Fallback to YOLO failed: $fallbackError");
        }
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _setupYolo() async {
    // Audio Mutual Exclusion: Ensure mic recording and SoLoud stream are stopped
    _micSubscription?.cancel();
    _micSubscription = null;
    await ref.read(audioInputProvider).stopRecording();
    await ref.read(audioOutputProvider).stopStream();
    _audioStreamIsActive = false;

    // Subsystem initialization
    await _yoloDetector.init();
    await _ttsService.init();
    _ttsService.reset();

    final videoInput = ref.read(videoInputProvider);
    if (!videoInput.isInitialized) {
      await videoInput.init();
    }

    // Ensure clean image stream
    await videoInput.stopStreamingImages();

    _yoloSubscription?.cancel();
    _yoloSubscription = videoInput
        .startStreamingRawFrames(minIntervalMs: 250)
        .listen((frame) async {
      if (ref.read(aiModeProvider) != AiMode.localYolo || !mounted) return;
      final results = await _yoloDetector.detectRaw(frame);
      if (mounted && ref.read(aiModeProvider) == AiMode.localYolo) {
        setState(() {
          _detections = results;
        });
        await _ttsService.announceDetections(results);
      }
    });

    if (mounted) {
      setState(() {
        _cameraIsActive = true;
      });
    }
  }

  Future<void> _teardownYolo() async {
    _yoloSubscription?.cancel();
    _yoloSubscription = null;
    await _ttsService.stop();
    _ttsService.reset();
    await ref.read(videoInputProvider).stopStreamingImages();

    if (mounted) {
      setState(() {
        _detections = [];
        _cameraIsActive = false;
      });
    }
  }

  Future<void> _setupGemini() async {
    // YOLO Mutual Exclusion: Stop TTS and cancel YOLO subscription
    _yoloSubscription?.cancel();
    _yoloSubscription = null;
    await _ttsService.stop();
    _ttsService.reset();

    if (mounted) {
      setState(() {
        _detections = [];
      });
    }

    final videoInput = ref.read(videoInputProvider);
    if (!videoInput.isInitialized) {
      await videoInput.init();
    }

    // Connect Gemini Live session
    await _connectLiveSession();

    // Start Gemini Audio (Mic + SoLoud)
    await startAudioStream();

    // Start Gemini Video (1000ms interval)
    await startVideoStream();
  }

  Future<void> _teardownGemini() async {
    _sessionWatchdog?.cancel();
    _sessionWatchdog = null;

    _cameraSubscription?.cancel();
    _cameraSubscription = null;
    await ref.read(videoInputProvider).stopStreamingImages();

    _micSubscription?.cancel();
    _micSubscription = null;
    await ref.read(audioInputProvider).stopRecording();
    await ref.read(audioOutputProvider).stopStream();

    await _combinedMediaController?.close();
    _combinedMediaController = null;

    if (_liveSessionIsOpen) {
      try {
        await _session.close();
      } catch (e) {
        log("Error closing Gemini session: $e");
      }
      _liveSessionIsOpen = false;
    }

    if (mounted) {
      setState(() {
        _audioStreamIsActive = false;
        _cameraIsActive = false;
      });
    }
  }

  Future<void> _connectLiveSession() async {
    if (_liveSessionIsOpen) return;

    try {
      _session = await _liveModel.connect();
      _liveSessionIsOpen = true;
      log("Gemini Live Session Connected Successfully!");
    } catch (e) {
      log("Failed to connect to Gemini: $e");
      rethrow;
    }

    _lastModelResponse = DateTime.now();

    _sessionWatchdog?.cancel();
    _sessionWatchdog = Timer.periodic(const Duration(seconds: 10), (timer) {
      final diff = DateTime.now().difference(_lastModelResponse).inSeconds;

      if (diff > 25 && _liveSessionIsOpen && ref.read(aiModeProvider) == AiMode.cloudGemini) {
        log("Gemini session stalled. Restarting audio/video streams...");

        Future.microtask(() async {
          await stopVideoStream();
          await stopAudioStream();
          await startAudioStream();
        });
      }
    });

    unawaited(processMessagesContinuously());
  }

  void toggleAudioStream() async {
    if (ref.read(modeTransitionProvider) == ModeTransitionState.transitioning) return;

    final currentMode = ref.read(aiModeProvider);
    if (currentMode == AiMode.localYolo) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Microphone is used for Gemini Live mode."),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    if (_audioStreamIsActive) {
      await stopAudioStream();
    } else {
      await startAudioStream();
    }
  }

  Future<void> startAudioStream() async {
    if (!_liveSessionIsOpen) {
      await _connectLiveSession();
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

    if (mounted) {
      setState(() {
        _audioStreamIsActive = true;
      });
    }
  }

  Future<void> stopAudioStream() async {
    _micSubscription?.cancel();
    _micSubscription = null;

    await ref.read(audioInputProvider).stopRecording();
    await ref.read(audioOutputProvider).stopStream();

    if (mounted) {
      setState(() {
        _audioStreamIsActive = false;
      });
    }
  }

  void toggleVideoStream() async {
    if (ref.read(modeTransitionProvider) == ModeTransitionState.transitioning) return;

    final currentMode = ref.read(aiModeProvider);
    if (currentMode == AiMode.localYolo) {
      if (_cameraIsActive) {
        _yoloSubscription?.cancel();
        _yoloSubscription = null;
        await ref.read(videoInputProvider).stopStreamingImages();
        if (mounted) {
          setState(() {
            _cameraIsActive = false;
            _detections = [];
          });
        }
      } else {
        final videoInput = ref.read(videoInputProvider);
        if (!videoInput.isInitialized) await videoInput.init();
        if (!_yoloDetector.isInitialized) await _yoloDetector.init();

        _yoloSubscription?.cancel();
        _yoloSubscription = videoInput
            .startStreamingRawFrames(minIntervalMs: 250)
            .listen((frame) async {
          if (ref.read(aiModeProvider) != AiMode.localYolo || !mounted) return;
          final results = await _yoloDetector.detectRaw(frame);
          if (mounted && ref.read(aiModeProvider) == AiMode.localYolo) {
            setState(() {
              _detections = results;
            });
            await _ttsService.announceDetections(results);
          }
        });

        if (mounted) {
          setState(() {
            _cameraIsActive = true;
          });
        }
      }
    } else {
      if (_cameraIsActive) {
        await stopVideoStream();
      } else {
        await startVideoStream();
      }
    }
  }

  Future<void> startVideoStream() async {
    if (!_liveSessionIsOpen) {
      await _connectLiveSession();
    }

    final videoInput = ref.read(videoInputProvider);
    if (!videoInput.isInitialized) {
      log("Camera not initialized yet. Initializing...");
      await videoInput.init();
    }

    // Ensure pipe exists
    if (_combinedMediaController == null || _combinedMediaController!.isClosed) {
      _combinedMediaController = StreamController<InlineDataPart>();
      _session.sendMediaStream(_combinedMediaController!.stream);
    }

    _cameraSubscription?.cancel();
    _cameraSubscription = videoInput.startStreamingImages(minIntervalMs: 1000).listen((image) {
      // Feed into Gemini Unified Pipe
      if (_combinedMediaController != null && !_combinedMediaController!.isClosed && _cameraIsActive) {
        _combinedMediaController!.add(InlineDataPart('image/jpeg', image));
      }

      if (mounted) setState(() {});
    });

    if (mounted) {
      setState(() {
        _cameraIsActive = true;
      });
    }
  }

  Future<void> stopVideoStream() async {
    _cameraSubscription?.cancel();
    _cameraSubscription = null;
    await ref.read(videoInputProvider).stopStreamingImages();

    if (mounted) {
      setState(() {
        _cameraIsActive = false;
      });
    }
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
    // Listen for activation state changes (Tab switching)
    ref.listen<bool>(vertexActiveProvider, (previous, next) async {
      if (next) {
        // Tab became active: activate current mode
        await _handleModeSwitch(ref.read(aiModeProvider));
      } else {
        // Tab became inactive: teardown active pipelines to release hardware
        final currentMode = ref.read(aiModeProvider);
        if (currentMode == AiMode.localYolo) {
          await _teardownYolo();
        } else {
          await _teardownGemini();
        }
        ref.read(modeTransitionProvider.notifier).state = ModeTransitionState.idle;
      }
    });

    final aiMode = ref.watch(aiModeProvider);
    final transitionState = ref.watch(modeTransitionProvider);
    final bool isYolo = aiMode == AiMode.localYolo;
    final bool isTransitioning = transitionState == ModeTransitionState.transitioning;

    final videoInput = ref.read(videoInputProvider);

    // Determine status badge colors and text
    Color statusColor;
    String statusText;

    if (transitionState == ModeTransitionState.transitioning) {
      statusColor = Colors.amberAccent;
      statusText = "SWITCHING...";
    } else if (transitionState == ModeTransitionState.error) {
      statusColor = Colors.redAccent;
      statusText = "MODE ERROR";
    } else if (isYolo) {
      statusColor = const Color(0xFF00FF88);
      statusText = _cameraIsActive ? "LOCAL YOLO" : "YOLO PAUSED";
    } else {
      statusColor = _liveSessionIsOpen ? const Color(0xFF00E5FF) : Colors.orangeAccent;
      statusText = _liveSessionIsOpen ? "GEMINI LIVE" : "CONNECTING...";
    }

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
              color: const Color(0xFF20563F).withValues(alpha: 0.1),
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
                color: Colors.white.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: const Color(0xFF20563F).withValues(alpha: 0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
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
                      Builder(builder: (context) {
                        try {
                          return SizedBox.expand(
                            child: CameraPreview(videoInput.cameraController),
                          );
                        } catch (_) {
                          return const Center(
                            child: Icon(Icons.videocam_off_rounded, size: 80, color: Colors.black12),
                          );
                        }
                      })
                    else
                      const Center(
                        child: Icon(Icons.videocam_off_rounded, size: 80, color: Colors.black12),
                      ),

                    // YOLO Overlay
                    if (isYolo && _cameraIsActive && _detections.isNotEmpty)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: YoloPainter(
                            _detections,
                            previewSize: () {
                              try {
                                return videoInput.isInitialized
                                    ? videoInput.cameraController.value.previewSize
                                    : null;
                              } catch (_) {
                                return null;
                              }
                            }(),
                          ),
                        ),
                      ),

                    // Status Indicator
                    Positioned(
                      top: 20,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ).animate(onPlay: (controller) => controller.repeat())
                             .fadeIn(duration: 500.ms)
                             .fadeOut(delay: 500.ms, duration: 500.ms),
                            const SizedBox(width: 8),
                            Text(
                              statusText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
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

          // Control Action Buttons (Camera & Mic)
          Positioned(
            bottom: 120,
            right: 30,
            child: Column(
              children: [
                // Camera Toggle
                _buildActionButton(
                  icon: _cameraIsActive ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                  isActive: _cameraIsActive,
                  isEnabled: !isTransitioning,
                  tooltip: _cameraIsActive ? "Turn off camera" : "Turn on camera",
                  onTap: toggleVideoStream,
                ),
                const SizedBox(height: 20),
                // Mic Toggle (Active in Cloud Gemini mode; disabled in YOLO mode)
                _buildActionButton(
                  icon: _audioStreamIsActive ? Icons.mic_rounded : Icons.mic_off_rounded,
                  isActive: _audioStreamIsActive,
                  isEnabled: !isTransitioning && !isYolo,
                  tooltip: isYolo
                      ? "Microphone is only used in Cloud Gemini mode"
                      : (_audioStreamIsActive ? "Mute microphone" : "Unmute microphone"),
                  onTap: toggleAudioStream,
                ),
              ],
            ),
          ),

          // AI Mode Selector (Authoritative Switch)
          Positioned(
            bottom: 40,
            left: 30,
            child: _buildModeSelector(aiMode, transitionState),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    bool isEnabled = true,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: Opacity(
        opacity: isEnabled ? 1.0 : 0.4,
        child: GestureDetector(
          onTap: isEnabled ? onTap : null,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF20563F) : Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                )
              ],
              border: Border.all(
                color: const Color(0xFF20563F).withValues(alpha: isActive ? 0 : 0.2),
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? Colors.white : const Color(0xFF20563F),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModeSelector(AiMode currentMode, ModeTransitionState transitionState) {
    final bool isTransitioning = transitionState == ModeTransitionState.transitioning;
    final bool isYolo = currentMode == AiMode.localYolo;

    return Semantics(
      label: "AI Mode: ${isYolo ? 'Local YOLO on-device' : 'Cloud Gemini live assistant'}",
      hint: isTransitioning ? "Switching modes, please wait" : "Double tap to switch AI mode",
      button: true,
      enabled: !isTransitioning,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFF20563F).withValues(alpha: 0.25),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isYolo ? Icons.visibility_rounded : Icons.cloud_done_rounded,
              size: 20,
              color: isTransitioning
                  ? Colors.grey
                  : (isYolo ? const Color(0xFF20563F) : const Color(0xFF007A87)),
            ),
            const SizedBox(width: 8),
            Text(
              isYolo ? "LOCAL YOLO" : "CLOUD GEMINI",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: isTransitioning ? Colors.grey : const Color(0xFF20563F),
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: !isYolo,
              onChanged: isTransitioning
                  ? null
                  : (isGemini) {
                      _handleModeSwitch(isGemini ? AiMode.cloudGemini : AiMode.localYolo);
                    },
              activeTrackColor: const Color(0xFF007A87),
              activeThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xFF20563F),
              inactiveThumbColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

class YoloPainter extends CustomPainter {
  final List<DetectionResult> detections;
  final Size? previewSize;

  YoloPainter(this.detections, {this.previewSize});

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    double scaleX = size.width;
    double scaleY = size.height;
    double offsetX = 0.0;
    double offsetY = 0.0;

    // Handle camera sensor aspect ratio scaling (portrait sensor width/height swapped in BoxFit.cover)
    if (previewSize != null && previewSize!.width > 0 && previewSize!.height > 0) {
      final bool isPortrait = size.height > size.width;
      final double imageWidth = isPortrait ? previewSize!.height : previewSize!.width;
      final double imageHeight = isPortrait ? previewSize!.width : previewSize!.height;

      final double scale = (size.width / imageWidth > size.height / imageHeight)
          ? size.width / imageWidth
          : size.height / imageHeight;

      final double renderedWidth = imageWidth * scale;
      final double renderedHeight = imageHeight * scale;

      offsetX = (size.width - renderedWidth) / 2.0;
      offsetY = (size.height - renderedHeight) / 2.0;
      scaleX = renderedWidth;
      scaleY = renderedHeight;
    }

    final boxPaint = Paint()
      ..color = const Color(0xFF00FF88) // High-contrast neon green for accessibility
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final fillPaint = Paint()
      ..color = const Color(0x3300FF88) // Subtle translucent overlay
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    for (final detection in detections) {
      final rect = Rect.fromLTWH(
        offsetX + detection.rect.left * scaleX,
        offsetY + detection.rect.top * scaleY,
        detection.rect.width * scaleX,
        detection.rect.height * scaleY,
      );

      // Draw bounding box with rounded corners
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      canvas.drawRRect(rrect, fillPaint);
      canvas.drawRRect(rrect, boxPaint);

      // Draw high-visibility label pill
      final labelText = '${detection.label} ${(detection.confidence * 100).toStringAsFixed(0)}%';
      textPainter.text = TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();

      final labelTop = (rect.top - 22).clamp(0.0, size.height - 22);
      final labelBgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          rect.left.clamp(0.0, size.width - textPainter.width - 12),
          labelTop,
          textPainter.width + 10,
          20,
        ),
        const Radius.circular(4),
      );

      canvas.drawRRect(labelBgRect, Paint()..color = const Color(0xFF00FF88));
      textPainter.paint(
        canvas,
        Offset(labelBgRect.left + 5, labelBgRect.top + 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant YoloPainter oldDelegate) {
    return oldDelegate.detections != detections || oldDelegate.previewSize != previewSize;
  }
}
