import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vision_aid_app/core/services/gemini_service.dart';

class VoiceService {
  // Singleton pattern
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  
  bool isListening = false;
  String lastWords = "";
  String lastCommand = "";
  
  // Callbacks for UI updates
  Function(String)? onWordsChanged;
  Function(bool)? onListeningChanged;
  
  GlobalKey<NavigatorState>? navigatorKey;
  String currentRoute = "/"; // Track current route to avoid duplicates

  Future<void> init() async {
    try {
      await _speech.initialize(
        onError: (errorNotification) {
          debugPrint("Speech Error: ${errorNotification.errorMsg}");
          isListening = false;
          onListeningChanged?.call(false);
        },
        onStatus: (status) {
          debugPrint("Speech Status: $status");
          if (status == 'done' || status == 'notListening') {
            isListening = false;
            onListeningChanged?.call(false);
          }
        },
      );
      await _tts.setLanguage("en-US");
    } catch (e) {
      debugPrint("Voice Init Error: $e");
    }
  }

  void startListening() async {
    try {
      bool available = await _speech.initialize();

      if (available) {
        speak("Listening");
        lastWords = "";
        isListening = true;
        onListeningChanged?.call(true);
        
        _speech.listen(
          onResult: (result) {
            lastWords = result.recognizedWords;
            onWordsChanged?.call(lastWords);
            
            // Only process the command when the user has finished speaking
            // or if it's a very clear final result.
            if (result.finalResult) {
              _handleGlobalCommand(lastWords.toLowerCase());
            }
          },
          listenMode: stt.ListenMode.dictation, // Use dictation for better continuous recognition
          partialResults: true,
          cancelOnError: true,
        );
      } else {
        debugPrint("Speech not available");
        speak("Voice control not available on this device.");
      }
    } catch (e) {
      debugPrint("Start Listening Error: $e");
      isListening = false;
      onListeningChanged?.call(false);
    }
  }

  void stopListening() {
    _speech.stop();
    speak("Stopped listening");
    isListening = false;
    lastCommand = "";
    onListeningChanged?.call(false);
  }

  void _handleGlobalCommand(String command) async {
    // Avoid double processing same command within a cooldown window
    if (command.trim() == lastCommand) return;
    
    // Improved matching with more synonyms and RegEx
    final homeRegex = RegExp(r"(home|main|start|dashboard|go home)", caseSensitive: false);
    final settingsRegex = RegExp(r"(settings|setting|options|config|configuration|set|open settings)", caseSensitive: false);
    final backRegex = RegExp(r"(back|go back|previous|return|return back)", caseSensitive: false);

    if (homeRegex.hasMatch(command)) {
      _executeCommand("home", '/home');
    } else if (settingsRegex.hasMatch(command)) {
      _executeCommand("settings", '/settings');
    } else if (backRegex.hasMatch(command)) {
      _executeCommand("back", null);
    } else {
      // GEMINI FALLBACK
      speak("Thinking...");
      final response = await geminiService.askGemini(command);
      speak(response);
    }
  }

  void _executeCommand(String commandKey, String? routeName) {
    lastCommand = commandKey;
    
    if (routeName != null) {
      _navigate(routeName);
    } else {
      _goBack();
    }

    // Cooldown to allow the same command again after 1 second
    Future.delayed(const Duration(seconds: 1), () {
      lastCommand = "";
    });
  }

  void _navigate(String routeName) {
    if (navigatorKey == null) return;
    
    // Avoid pushing the same route if we are already there
    if (currentRoute == routeName) {
      speak("You are already on the ${routeName.replaceAll('/', '')} screen");
      stopListening();
      return;
    }

    speak("Opening ${routeName.replaceAll('/', '')}");
    
    if (routeName == '/home') {
      // Clear stack when going home for a cleaner experience
      navigatorKey!.currentState?.pushNamedAndRemoveUntil(routeName, (route) => route.isFirst);
    } else {
      navigatorKey!.currentState?.pushNamed(routeName);
    }
    
    currentRoute = routeName;
    stopListening();
  }

  void _goBack() {
    if (navigatorKey == null) return;
    
    if (navigatorKey!.currentState?.canPop() ?? false) {
      speak("Going back");
      navigatorKey!.currentState?.pop();
    } else {
      speak("Nowhere to go back to");
    }
    stopListening();
  }

  void updateCurrentRoute(String? routeName) {
    if (routeName != null) {
      currentRoute = routeName;
    }
  }

  Future<void> speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint("TTS Error: $e");
    }
  }
}
