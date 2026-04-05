import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui_components/ui_components.dart';
import 'providers.dart';

class FlutterFireAILiveAPIDemo extends ConsumerStatefulWidget {
  const FlutterFireAILiveAPIDemo({super.key});

  @override
  ConsumerState<FlutterFireAILiveAPIDemo> createState() =>
      _MyHomePageState();
}

class _MyHomePageState extends ConsumerState<FlutterFireAILiveAPIDemo> {
  bool _audioIsInitialized = false;
  bool _videoIsInitialized = false;



      final LiveGenerativeModel _liveModel =
          FirebaseAI.vertexAI().liveGenerativeModel(
       
        model: 'gemini-live-2.5-flash-native-audio', 
        
        systemInstruction: Content.text(
      'You are a helpful visual assistant for visually impaired users. '
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAudio();
      _initializeVideo();
    });
  }

  @override
  void dispose() {
    _sessionWatchdog?.cancel();
    ref.read(audioInputProvider).dispose();
    ref.read(audioOutputProvider).dispose();
    ref.read(videoInputProvider).dispose();

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
        final diff =
            DateTime.now().difference(_lastModelResponse).inSeconds;

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

  Future<void> _handleLiveServerContent(
      LiveServerContent response) async {
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

  Future<void> _handleLiveServerToolCall(
      LiveServerToolCall response) async {
    if (response.functionCalls?.isNotEmpty ?? false) {
      log("Gemini made a function call!");
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioInput = ref.watch(audioInputProvider);
    final videoInput = ref.watch(videoInputProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leadingWidth: 100,
        leading: const LeafAppIcon(),
        title: const AppTitle(title: 'Vision Aid'),
      ),
      body: _cameraIsActive
          ? Center(
              child: FullCameraPreview(
                controller: videoInput.cameraController,
              ),
            )
          : CenterCircle(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: _settingUpLiveSession
                    ? const CircularProgressIndicator()
                    : const Icon(size: 54, Icons.waves),
              ),
            ),
      bottomNavigationBar: BottomBar(
        child: Row(
          children: [
            const ChatButton(),
            VideoButton(
              isActive: _cameraIsActive,
              onPressed: toggleVideoStream,
            ),
            const Spacer(),
            MuteButton(
              isMuted: audioInput.isPaused,
              onPressed: _audioStreamIsActive ? toggleMuteInput : null,
            ),
            CallButton(
              isActive: _audioStreamIsActive,
              onPressed: _audioIsInitialized ? toggleAudioStream : null,
            ),
          ],
        ),
      ),
    );
  }
}