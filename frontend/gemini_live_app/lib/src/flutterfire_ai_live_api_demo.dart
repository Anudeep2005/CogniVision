import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'ui_components/ui_components.dart';
import 'providers.dart';
import 'utilities/yolo_detector.dart';
import 'utilities/video_input.dart' show VideoInput, YuvFrame;
import 'services/tts_service.dart';

/// Minimum gap between frames handed to YOLO. The worker is the real limiter
/// (frames are dropped while it is busy), this just avoids needless copying.
const int _kYoloFrameIntervalMs = 100;

class FlutterFireAILiveAPIDemo extends ConsumerStatefulWidget {
  const FlutterFireAILiveAPIDemo({super.key});

  @override
  ConsumerState<FlutterFireAILiveAPIDemo> createState() => _MyHomePageState();
}

class _MyHomePageState extends ConsumerState<FlutterFireAILiveAPIDemo>
    with WidgetsBindingObserver {
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
  StreamSubscription<YuvFrame>? _yoloSubscription;

  /// Detections live in a notifier so only the overlay repaints
  /// (previously every detection rebuilt the whole screen).
  final ValueNotifier<List<DetectionResult>> _detectionsNotifier =
      ValueNotifier<List<DetectionResult>>(const <DetectionResult>[]);

  // Unified Media Pipe for Gemini (Audio + Video)
  StreamController<InlineDataPart>? _combinedMediaController;
  StreamSubscription<Uint8List>? _micSubscription;
  StreamSubscription<Uint8List>? _cameraSubscription;

  // App-lifecycle handling (release the camera when backgrounded).
  bool _backgrounded = false;
  bool _suspendedByLifecycle = false;
  Future<void>? _suspendFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // The camera frames are rotated by the sensor orientation assuming a
    // portrait-held phone, and the overlay maths assumes the same. Lock it.
    // (Move this to main() if you prefer a single app-wide place.)
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeAudio();
      await _initializeVideo();

      // If vertex tab is active on mount, bootstrap the initial mode
      if (mounted && ref.read(vertexActiveProvider)) {
        await _handleModeSwitch(ref.read(aiModeProvider));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _sessionWatchdog?.cancel();
    _combinedMediaController?.close();
    _micSubscription?.cancel();
    _cameraSubscription?.cancel();
    _yoloSubscription?.cancel();

    // The notifier-based providers own their own disposal; just free hardware.
    unawaited(ref.read(videoInputProvider).release());
    unawaited(ref.read(audioInputProvider).stopRecording());
    unawaited(ref.read(audioOutputProvider).dispose());
    _yoloDetector.dispose();
    _ttsService.dispose();
    _detectionsNotifier.dispose();

    if (_liveSessionIsOpen) {
      unawaited(_session.close());
    }

    super.dispose();
  }

  // ── App lifecycle ─────────────────────────────────────────────────────────
  //
  // Without this the camera session from the previous run/background stays
  // bound and the next start fails with
  // "No supported surface combination is found for camera device".

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgrounded = true;
      unawaited(_onBackgrounded());
    } else if (state == AppLifecycleState.resumed) {
      _backgrounded = false;
      unawaited(_onForegrounded());
    }
  }

  Future<void> _onBackgrounded() async {
    if (!mounted || !ref.read(vertexActiveProvider)) return;
    _suspendedByLifecycle = true;
    _suspendFuture = _suspendPipelines();
    await _suspendFuture;
  }

  Future<void> _onForegrounded() async {
    await _suspendFuture;
    if (!_suspendedByLifecycle) return;
    _suspendedByLifecycle = false;
    if (!mounted || !ref.read(vertexActiveProvider)) return;
    await _handleModeSwitch(ref.read(aiModeProvider));
  }

  /// Stops the active mode and fully releases the camera.
  Future<void> _suspendPipelines() async {
    if (!mounted) return;
    try {
      if (ref.read(aiModeProvider) == AiMode.localYolo) {
        await _teardownYolo();
      } else {
        await _teardownGemini();
      }
      await _releaseCamera();
    } catch (e) {
      log('Suspend error: $e');
    }
    if (mounted) {
      ref.read(modeTransitionProvider.notifier).state =
          ModeTransitionState.idle;
    }
  }

  Future<void> _releaseCamera() async {
    // Remove the CameraPreview from the tree BEFORE the controller is disposed.
    if (mounted) {
      setState(() => _cameraIsActive = false);
    }
    await ref.read(videoInputProvider).release();
  }

  // ── Initialisation ────────────────────────────────────────────────────────

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

  // ── Mode switching ────────────────────────────────────────────────────────

  /// Authoritative coordinator for switching AI modes with strict mutual exclusion.
  Future<void> _handleModeSwitch(AiMode targetMode) async {
    final currentMode = ref.read(aiModeProvider);
    final transitionState = ref.read(modeTransitionProvider);

    // Prevent re-entrant transitions and redundant switches
    if (transitionState == ModeTransitionState.transitioning) return;
    if (currentMode == targetMode &&
        transitionState == ModeTransitionState.active) return;

    ref.read(modeTransitionProvider.notifier).state =
        ModeTransitionState.transitioning;
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
      ref.read(modeTransitionProvider.notifier).state =
          ModeTransitionState.active;

      // The app was backgrounded / the tab was left while we were switching:
      // don't leave camera, mic or GPU work running.
      if (_backgrounded || !ref.read(vertexActiveProvider)) {
        await _suspendPipelines();
      }
    } catch (e, st) {
      log("Mode switch error: $e\n$st");
      ref.read(modeTransitionProvider.notifier).state =
          ModeTransitionState.error;

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
          ref.read(modeTransitionProvider.notifier).state =
              ModeTransitionState.active;
        } catch (fallbackError) {
          log("Fallback to YOLO failed: $fallbackError");
        }
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  // ── YOLO mode ─────────────────────────────────────────────────────────────

  Future<void> _setupYolo() async {
    // Audio Mutual Exclusion: Ensure mic recording and SoLoud stream are stopped
    _micSubscription?.cancel();
    _micSubscription = null;
    await ref.read(audioInputProvider).stopRecording();
    await ref.read(audioOutputProvider).stopStream();
    _audioStreamIsActive = false;

    // Subsystem initialization (model load + TTS in parallel)
    await Future.wait<void>([_yoloDetector.init(), _ttsService.init()]);
    _ttsService.reset();

    await _startYoloStream();
  }

  /// Subscribes YOLO to the camera. The native image stream is started once
  /// inside VideoInput and is never restarted, so there is no CameraX re-bind.
  Future<void> _startYoloStream() async {
    final videoInput = ref.read(videoInputProvider);
    if (!_yoloDetector.isInitialized) await _yoloDetector.init();
    await videoInput.init(); // idempotent

    await _yoloSubscription?.cancel();
    final frames = await videoInput.startStreamingYuvFrames(
        minIntervalMs: _kYoloFrameIntervalMs);
    _yoloSubscription = frames.listen(_onYuvFrame);

    if (mounted) {
      setState(() {
        _cameraIsActive = true;
      });
    }
  }

  Future<void> _onYuvFrame(YuvFrame frame) async {
    if (!mounted || ref.read(aiModeProvider) != AiMode.localYolo) return;

    final results = await _yoloDetector.detectYuv(frame);
    // null = frame skipped (worker busy) or failed: keep the previous boxes.
    if (results == null) return;

    if (!mounted ||
        ref.read(aiModeProvider) != AiMode.localYolo ||
        !_cameraIsActive) {
      return;
    }

    // Repaints only the overlay – no setState.
    _detectionsNotifier.value = results;
    await _ttsService.announceDetections(results);
  }

  Future<void> _teardownYolo() async {
    await _yoloSubscription?.cancel();
    _yoloSubscription = null;
    await _ttsService.stop();
    _ttsService.reset();
    await ref.read(videoInputProvider).stopStreamingImages();
    _detectionsNotifier.value = const <DetectionResult>[];

    if (mounted) {
      setState(() {
        _cameraIsActive = false;
      });
    }
  }

  // ── Gemini mode ───────────────────────────────────────────────────────────

  Future<void> _setupGemini() async {
    // YOLO Mutual Exclusion: Stop TTS and cancel YOLO subscription
    await _yoloSubscription?.cancel();
    _yoloSubscription = null;
    await _ttsService.stop();
    _ttsService.reset();
    _detectionsNotifier.value = const <DetectionResult>[];

    final videoInput = ref.read(videoInputProvider);
    await videoInput.init(); // idempotent

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

    await _cameraSubscription?.cancel();
    _cameraSubscription = null;
    await ref.read(videoInputProvider).stopStreamingImages();

    await _micSubscription?.cancel();
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

      if (diff > 25 &&
          _liveSessionIsOpen &&
          ref.read(aiModeProvider) == AiMode.cloudGemini) {
        log("Gemini session stalled. Restarting audio/video streams...");

        // Reset right away, otherwise this fires again on every tick.
        _lastModelResponse = DateTime.now();
        final bool cameraWasOn = _cameraIsActive;

        Future.microtask(() async {
          await stopVideoStream();
          await stopAudioStream();
          await startAudioStream();
          if (cameraWasOn) await startVideoStream();
        });
      }
    });

    unawaited(processMessagesContinuously());
  }

  void toggleAudioStream() async {
    if (ref.read(modeTransitionProvider) == ModeTransitionState.transitioning)
      return;

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
    if (_combinedMediaController == null ||
        _combinedMediaController!.isClosed) {
      _combinedMediaController = StreamController<InlineDataPart>();
      _session.sendMediaStream(_combinedMediaController!.stream);
    }

    // Start Microphone and feed into Unified Pipe
    var micStream = await audioInput.startRecordingStream();
    _micSubscription?.cancel();
    _micSubscription = micStream.listen((data) {
      if (_combinedMediaController != null &&
          !_combinedMediaController!.isClosed) {
        _combinedMediaController!
            .add(InlineDataPart('audio/pcm;rate=16000', data));
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
    if (ref.read(modeTransitionProvider) == ModeTransitionState.transitioning)
      return;

    final currentMode = ref.read(aiModeProvider);
    if (currentMode == AiMode.localYolo) {
      if (_cameraIsActive) {
        await _yoloSubscription?.cancel();
        _yoloSubscription = null;
        await ref.read(videoInputProvider).stopStreamingImages();
        _detectionsNotifier.value = const <DetectionResult>[];
        if (mounted) {
          setState(() {
            _cameraIsActive = false;
          });
        }
      } else {
        try {
          await _startYoloStream();
        } catch (e) {
          log('Could not start YOLO camera stream: $e');
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
    await videoInput.init(); // idempotent

    // Ensure pipe exists
    if (_combinedMediaController == null ||
        _combinedMediaController!.isClosed) {
      _combinedMediaController = StreamController<InlineDataPart>();
      _session.sendMediaStream(_combinedMediaController!.stream);
    }

    await _cameraSubscription?.cancel();
    _cameraIsActive = true;
    try {
      final jpegs = await videoInput.startStreamingImages(minIntervalMs: 1000);
      _cameraSubscription = jpegs.listen((image) {
        // Feed into Gemini Unified Pipe (no setState: nothing to rebuild here)
        final pipe = _combinedMediaController;
        if (pipe != null && !pipe.isClosed && _cameraIsActive) {
          pipe.add(InlineDataPart('image/jpeg', image));
        }
      });
    } catch (e) {
      _cameraIsActive = false;
      rethrow;
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> stopVideoStream() async {
    await _cameraSubscription?.cancel();
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

  // ── UI ────────────────────────────────────────────────────────────────────

  /// Current preview size, or null if the camera is not open (the controller
  /// getter throws while released).
  Size? _previewSizeOrNull(VideoInput videoInput) {
    if (!videoInput.isInitialized) return null;
    try {
      return videoInput.cameraController.value.previewSize;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for activation state changes (Tab switching)
    ref.listen<bool>(vertexActiveProvider, (previous, next) async {
      if (next) {
        // Tab became active: re-open the camera and activate the current mode
        await _handleModeSwitch(ref.read(aiModeProvider));
      } else {
        // Tab became inactive: stop the mode AND release the camera so the
        // Face tab / other tabs can use camera hardware without contention.
        await _suspendPipelines();
      }
    });

    final aiMode = ref.watch(aiModeProvider);
    final transitionState = ref.watch(modeTransitionProvider);
    final bool isYolo = aiMode == AiMode.localYolo;
    final bool isTransitioning =
        transitionState == ModeTransitionState.transitioning;

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
      statusColor =
          _liveSessionIsOpen ? const Color(0xFF00E5FF) : Colors.orangeAccent;
      statusText = _liveSessionIsOpen ? "GEMINI LIVE" : "CONNECTING...";
    }

    final Size? previewSize =
        _cameraIsActive ? _previewSizeOrNull(videoInput) : null;

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
            child: const Icon(Icons.eco_rounded,
                color: Color(0xFF20563F), size: 20),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Static background: isolate its repaints from the live camera/overlay.
          const RepaintBoundary(child: LuxuryBackground()),

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
                    // Camera feed. FittedBox(cover) keeps the preview geometry
                    // identical to what YoloPainter assumes, so boxes line up.
                    if (previewSize != null)
                      SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            // Portrait box: short side = width, long side = height,
                            // whichever way the plugin reports previewSize.
                            width:
                                math.min(previewSize.width, previewSize.height),
                            height:
                                math.max(previewSize.width, previewSize.height),
                            child: CameraPreview(videoInput.cameraController),
                          ),
                        ),
                      )
                    else
                      const Center(
                        child: Icon(Icons.videocam_off_rounded,
                            size: 80, color: Colors.black12),
                      ),

                    // YOLO overlay – repaints on its own when detections change.
                    if (isYolo && previewSize != null)
                      Positioned.fill(
                        child: ValueListenableBuilder<List<DetectionResult>>(
                          valueListenable: _detectionsNotifier,
                          builder: (context, detections, _) {
                            return RepaintBoundary(
                              child: CustomPaint(
                                painter: YoloPainter(
                                  detections,
                                  previewSize: previewSize,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    // Status Indicator
                    Positioned(
                      top: 20,
                      right: 20,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
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
                            )
                                .animate(
                                    onPlay: (controller) => controller.repeat())
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
                  icon: _cameraIsActive
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  isActive: _cameraIsActive,
                  isEnabled: !isTransitioning,
                  tooltip:
                      _cameraIsActive ? "Turn off camera" : "Turn on camera",
                  onTap: toggleVideoStream,
                ),
                const SizedBox(height: 20),
                // Mic Toggle (Active in Cloud Gemini mode; disabled in YOLO mode)
                _buildActionButton(
                  icon: _audioStreamIsActive
                      ? Icons.mic_rounded
                      : Icons.mic_off_rounded,
                  isActive: _audioStreamIsActive,
                  isEnabled: !isTransitioning && !isYolo,
                  tooltip: isYolo
                      ? "Microphone is only used in Cloud Gemini mode"
                      : (_audioStreamIsActive
                          ? "Mute microphone"
                          : "Unmute microphone"),
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
                color: const Color(0xFF20563F)
                    .withValues(alpha: isActive ? 0 : 0.2),
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

  Widget _buildModeSelector(
      AiMode currentMode, ModeTransitionState transitionState) {
    final bool isTransitioning =
        transitionState == ModeTransitionState.transitioning;
    final bool isYolo = currentMode == AiMode.localYolo;

    return Semantics(
      label:
          "AI Mode: ${isYolo ? 'Local YOLO on-device' : 'Cloud Gemini live assistant'}",
      hint: isTransitioning
          ? "Switching modes, please wait"
          : "Double tap to switch AI mode",
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
                  : (isYolo
                      ? const Color(0xFF20563F)
                      : const Color(0xFF007A87)),
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
                      _handleModeSwitch(
                          isGemini ? AiMode.cloudGemini : AiMode.localYolo);
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

// ─────────────────────────────────────────────────────────────────────────────
// YOLO bounding-box overlay
// ─────────────────────────────────────────────────────────────────────────────

class YoloPainter extends CustomPainter {
  final List<DetectionResult> detections;
  final Size? previewSize;

  YoloPainter(this.detections, {this.previewSize});

  // Allocated once instead of per frame.
  static final Paint _boxPaint = Paint()
    ..color =
        const Color(0xFF00FF88) // High-contrast neon green for accessibility
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5;
  static final Paint _fillPaint = Paint()
    ..color = const Color(0x3300FF88) // Subtle translucent overlay
    ..style = PaintingStyle.fill;
  static final Paint _labelBgPaint = Paint()..color = const Color(0xFF00FF88);
  static const TextStyle _labelStyle = TextStyle(
    color: Colors.black,
    fontSize: 12,
    fontWeight: FontWeight.bold,
  );
  static final TextPainter _textPainter =
      TextPainter(textDirection: TextDirection.ltr);

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty) return;

    double scaleX = size.width;
    double scaleY = size.height;
    double offsetX = 0.0;
    double offsetY = 0.0;

    // The preview is drawn BoxFit.cover. Detections are normalised to the whole
    // upright frame, so map them onto the same "cover" rectangle. previewSize
    // may be reported landscape or portrait, so orient it to the viewport.
    final ps = previewSize;
    if (ps != null && ps.width > 0 && ps.height > 0) {
      final bool portrait = size.height > size.width;
      final double shortSide = math.min(ps.width, ps.height);
      final double longSide = math.max(ps.width, ps.height);
      final double imageWidth = portrait ? shortSide : longSide;
      final double imageHeight = portrait ? longSide : shortSide;

      final double scale =
          math.max(size.width / imageWidth, size.height / imageHeight);

      final double renderedWidth = imageWidth * scale;
      final double renderedHeight = imageHeight * scale;

      offsetX = (size.width - renderedWidth) / 2.0;
      offsetY = (size.height - renderedHeight) / 2.0;
      scaleX = renderedWidth;
      scaleY = renderedHeight;
    }

    for (final detection in detections) {
      final r = detection.rect;
      final rect = Rect.fromLTWH(
        offsetX + r.left * scaleX,
        offsetY + r.top * scaleY,
        r.width * scaleX,
        r.height * scaleY,
      );

      // Draw bounding box with rounded corners
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      canvas.drawRRect(rrect, _fillPaint);
      canvas.drawRRect(rrect, _boxPaint);

      // Draw high-visibility label pill
      final labelText =
          '${detection.label} ${(detection.confidence * 100).toStringAsFixed(0)}%';
      _textPainter.text = TextSpan(text: labelText, style: _labelStyle);
      _textPainter.layout();

      final double labelTop =
          math.max(0.0, math.min(rect.top - 22, size.height - 22));
      final double labelLeft = math.max(
          0.0, math.min(rect.left, size.width - _textPainter.width - 12));
      final labelBgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(labelLeft, labelTop, _textPainter.width + 10, 20),
        const Radius.circular(4),
      );

      canvas.drawRRect(labelBgRect, _labelBgPaint);
      _textPainter.paint(
        canvas,
        Offset(labelBgRect.left + 5, labelBgRect.top + 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant YoloPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.previewSize != previewSize;
  }
}
