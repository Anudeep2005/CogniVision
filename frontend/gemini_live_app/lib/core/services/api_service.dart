import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  static const String _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL', 
    defaultValue: 'http://localhost:3000'
  );
  
  String get baseUrl => '$_apiBaseUrl/api';

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
      } else {
        throw Exception('Failed to register user: ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error during registration: $e');
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
      throw Exception('Network error while fetching profile: $e');
    }
  }

  Future<void> triggerSos({
    required String firebaseUid,
    required double lat,
    required double lng,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/sos/trigger'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'firebaseUid': firebaseUid,
          'location': {'lat': lat, 'lng': lng},
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to trigger SOS: ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error during SOS trigger: $e');
    }
  }

  Future<void> updateLocation({
    required String firebaseUid,
    required double lat,
    required double lng,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/location/update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'firebaseUid': firebaseUid,
          'lat': lat,
          'lng': lng,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to update location: ${response.body}');
      }
    } catch (e) {
      throw Exception('Network error during location update: $e');
    }
  }
}

