import 'package:flutter_tts/flutter_tts.dart';
import 'package:vision_aid_app/features/ai_assistant/yolo_detector.dart';

class TtsService {
  final FlutterTts _flutterTts = FlutterTts();

  Future<void> init() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> speak(String text) async {
    await _flutterTts.stop();
    await _flutterTts.speak(text);
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }

  Future<void> announceDetections(List<DetectionResult> detections) async {
    if (detections.isEmpty) return;

    // Take top 3
    final top3 = detections.take(3).toList();
    List<String> phrases = [];

    for (var det in top3) {
      double centerX = det.boundingBox[0];
      String direction;
      if (centerX < 0.33) {
        direction = "on the left";
      } else if (centerX > 0.66) {
        direction = "on the right";
      } else {
        direction = "ahead";
      }
      phrases.add("${det.label} $direction");
    }

    String announcement = phrases.join(", ");
    await speak(announcement);
  }

  void dispose() {
    _flutterTts.stop();
  }
}
