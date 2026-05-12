import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool isListening = false;
  String lastWords = "";
  String lastCommand = "";

  final List<Function(String)> _onWordsChangedListeners = [];
  final List<Function(String)> _onCommandListeners = [];
  final List<Function(bool)> _onListeningChangedListeners = [];

  void addWordsListener(Function(String) l) => _onWordsChangedListeners.add(l);
  void addCommandListener(Function(String) l) => _onCommandListeners.add(l);
  void addStatusListener(Function(bool) l) => _onListeningChangedListeners.add(l);

  void removeWordsListener(Function(String) l) => _onWordsChangedListeners.remove(l);
  void removeCommandListener(Function(String) l) => _onCommandListeners.remove(l);
  void removeStatusListener(Function(bool) l) => _onListeningChangedListeners.remove(l);

  GlobalKey<NavigatorState>? navigatorKey;
  int currentIndex = 0;
  Function(int)? onTabChange;

  void updateCurrentIndex(int index) {
    currentIndex = index;
  }

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      _isInitialized = await _speech.initialize(
        onError: (errorNotification) {
          debugPrint("Speech Error: ${errorNotification.errorMsg}");
          isListening = false;
          for (var l in _onListeningChangedListeners) l(false);
        },
        onStatus: (status) {
          debugPrint("Speech Status: $status");
          if (status == 'done' || status == 'notListening') {
            isListening = false;
            for (var l in _onListeningChangedListeners) l(false);
          }
        },
      );
    } catch (e) {
      debugPrint("VoiceService Init Error: $e");
    }
  }

  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    await _tts.setLanguage("en-US");
    await _tts.setPitch(1.0);
    await _tts.speak(text);
  }

  Future<void> startListening() async {
    // Safety check: if Vertex AI is active, don't listen
    // (This is a second layer of protection)
    
    try {
      if (!_isInitialized) await init();

      if (_isInitialized) {
        HapticFeedback.mediumImpact();
        
        lastWords = "";
        isListening = true;
        for (var l in _onListeningChangedListeners) l(true);

        _speech.listen(
          onResult: (result) {
            lastWords = result.recognizedWords;
            for (var l in _onWordsChangedListeners) l(lastWords);

            if (result.finalResult) {
              debugPrint("VoiceService: Final Result Recognized: ${lastWords.toLowerCase()}");
              _handleGlobalCommand(lastWords.toLowerCase());
              for (var l in _onCommandListeners) l(lastWords.toLowerCase());
            }
          },
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
          onDevice: true,
        );
      } else {
        debugPrint("Speech not available");
        speak("Voice control not available on this device.");
      }
    } catch (e) {
      debugPrint("Start Listening Error: $e");
      isListening = false;
      for (var l in _onListeningChangedListeners) l(false);
    }
  }


  void stopListening() {
    _speech.stop();
    speak("Stopped listening");
    isListening = false;
    lastCommand = "";
    for (var l in _onListeningChangedListeners) l(false);
  }

  /// Force-releases the microphone for other services (like Vertex AI)
  Future<void> shutdown() async {
    debugPrint("VoiceService: Shutting down to release microphone...");
    await _speech.stop();
    await _speech.cancel();
    isListening = false;
    for (var l in _onListeningChangedListeners) l(false);
  }

  void _handleGlobalCommand(String command) {
    if (command.trim() == lastCommand) return;

    final vertexRegex = RegExp(
      r"(vertex|ai|assistant|home|start vertex)",
      caseSensitive: false,
    );
    final gpsRegex = RegExp(
      r"(gps|navigate|navigation|map|route|directions)",
      caseSensitive: false,
    );
    final faceRegex = RegExp(
      r"(face|recognition|camera|detect|who is)",
      caseSensitive: false,
    );

    bool handled = false;

    if (vertexRegex.hasMatch(command)) {
      _executeCommand("vertex", 0);
      handled = true;
    } else if (gpsRegex.hasMatch(command)) {
      _executeCommand("gps", 1);
      handled = true;
    } else if (faceRegex.hasMatch(command)) {
      _executeCommand("face", 2);
      handled = true;
    }
  }

  void _executeCommand(String commandKey, int targetIndex) {
    lastCommand = commandKey;
    _navigate(targetIndex);

    Future.delayed(const Duration(seconds: 1), () {
      lastCommand = "";
    });
  }

  void _navigate(int targetIndex) {
    if (currentIndex == targetIndex) {
      return;
    }

    String screenName = "Vertex AI";
    if (targetIndex == 1) screenName = "GPS Navigation";
    if (targetIndex == 2) screenName = "Face Recognition";

    speak("Opening $screenName");
    
    if (onTabChange != null) {
      currentIndex = targetIndex;
      onTabChange!(targetIndex);
    }
  }
}
