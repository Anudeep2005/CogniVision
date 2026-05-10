import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter/foundation.dart';

class VoiceEngine {
  final FlutterTts _flutterTts = FlutterTts();
  final SpeechToText _speechToText = SpeechToText();
  bool _isInitialized = false;

  // Singleton
  static final VoiceEngine _instance = VoiceEngine._internal();
  factory VoiceEngine() => _instance;
  VoiceEngine._internal();

  Future<void> init() async {
    if (_isInitialized) return;
    
    // Init TTS
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    // Init STT
    try {
      bool available = await _speechToText.initialize(
        onStatus: (status) => debugPrint('STT Status: $status'),
        onError: (errorNotification) => debugPrint('STT Error: $errorNotification'),
      );
      if (available) {
        _isInitialized = true;
      } else {
        debugPrint("The user has denied the use of speech recognition.");
      }
    } catch (e) {
      debugPrint('Failed to initialize STT: $e');
    }
  }

  Future<void> speak(String text) async {
    // Stop any ongoing speech
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  Future<void> stopSpeaking() async {
    await _flutterTts.stop();
  }

  Future<void> listen(Function(String) onResult) async {
    if (!_isInitialized) {
      await speak("Speech recognition is not available. Please check permissions.");
      return;
    }

    if (_speechToText.isListening) {
      await _speechToText.stop();
      return;
    }

    // We removed the 'speak("Listening")' and the 800ms delay to make it INSTANT.
    // The UI already updates and the phone vibrates, so the user knows.

    await _speechToText.listen(
      onResult: (result) {
        if (result.finalResult) {
          onResult(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(milliseconds: 1500),
      partialResults: false,
      cancelOnError: true,
      listenMode: ListenMode.confirmation,
    );
  }

  bool get isListening => _speechToText.isListening;

  void dispose() {
    _flutterTts.stop();
    _speechToText.stop();
  }
}

final voiceEngine = VoiceEngine();
