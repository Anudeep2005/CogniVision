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

  /// Specialized for conversational voice interaction
  Future<String> chat(String message) async {
    try {
      // Add system context for assistant persona
      final prompt = "You are CogniVision, a helpful AI assistant for the visually impaired. "
          "Keep your responses concise, descriptive, and easy to understand via speech. "
          "User says: $message";
      return await askGemini(prompt);
    } catch (e) {
      return "I'm sorry, I encountered an error during our conversation.";
    }
  }

  /// Multimodal analysis for real-time scene understanding
  Future<String> describeScene(Uint8List imageBytes) async {
    const prompt = "Describe the scene in front of me clearly and concisely for a visually impaired person. "
        "Mention any hazards, obstacles, or important objects like doors, stairs, or people.";
    return await analyzeImage(imageBytes, prompt);
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
