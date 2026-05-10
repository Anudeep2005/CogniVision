import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

class GeminiService {
  final GenerativeModel _model = FirebaseAI.vertexAI().generativeModel(
    model: 'gemini-1.5-flash',
  );

  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  Future<String> askGemini(String prompt) async {
    try {
      final content = [Content.text(prompt)];
      final response = await _model.generateContent(content);
      return response.text ?? "I'm sorry, I couldn't understand that.";
    } catch (e) {
      debugPrint("Gemini Error: $e");
      return "I'm having trouble connecting to my AI brain right now.";
    }
  }

  Future<String> analyzeImage(Uint8List imageBytes, String prompt) async {
    try {
      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ])
      ];
      final response = await _model.generateContent(content);
      return response.text ?? "I couldn't describe this image.";
    } catch (e) {
      debugPrint("Gemini Vision Error: $e");
      return "I'm having trouble analyzing the image right now.";
    }
  }
}


final geminiService = GeminiService();
