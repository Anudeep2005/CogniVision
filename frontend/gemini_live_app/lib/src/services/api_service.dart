import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  /// Backend base URL loaded from .env (BACKEND_URL).
  /// Falls back to localhost for development.
  static String get baseUrl {
    final url = dotenv.env['BACKEND_URL'] ?? 'http://localhost:3000/api';
    return url;
  }

  Future<Map<String, dynamic>> register({
    required String firebaseUid,
    required String role,
    required String displayName,
    required String email,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'firebaseUid': firebaseUid,
          'role': role,
          'displayName': displayName,
          'email': email,
        }),
      );

      if (response.statusCode == 201) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 409) {
        throw Exception('User already registered. Please log in.');
      } else {
        throw Exception('Failed to register user: ${response.body}');
      }
    } catch (e) {
      debugPrint('[ApiService] register error: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getMe(String idToken) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: {
          'Authorization': 'Bearer $idToken',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Failed to fetch user profile: ${response.body}');
      }
    } catch (e) {
      debugPrint('[ApiService] getMe error: $e');
      rethrow;
    }
  }
}
