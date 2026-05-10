import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'dart:io';

class AuthService {
  // Use secure tunnel for guaranteed mobile connectivity
  static final String baseUrl = 'https://cognivision-auth.loca.lt/api';
    
  final _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      print("Attempting login to: $baseUrl/auth/login for $email");
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json', 'Bypass-Tunnel-Reminder': 'true'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await _storage.write(key: 'jwt', value: data['token']);
        await _storage.write(key: 'user', value: jsonEncode(data['user']));
        return {'success': true, 'user': User.fromJson(data['user'])};
      } else if ((response.statusCode == 403 || response.statusCode == 401) && data['locked'] == true) {
        return {
          'success': false,
          'locked': true,
          'userId': data['userId'],
          'message': data['message']
        };
      } else {
        return {'success': false, 'message': data['message'] ?? 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/signup'),
        headers: {'Content-Type': 'application/json', 'Bypass-Tunnel-Reminder': 'true'},
        body: jsonEncode({'email': email, 'password': password, 'role': role}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        await _storage.write(key: 'jwt', value: data['token']);
        await _storage.write(key: 'user', value: jsonEncode(data['user']));
        return {'success': true, 'user': User.fromJson(data['user'])};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Signup failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> generateRecoveryData(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/recovery/generate'),
        headers: {'Content-Type': 'application/json', 'Bypass-Tunnel-Reminder': 'true'},
        body: jsonEncode({'userId': userId}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {};
    } catch (e) {
      return {};
    }
  }

  Future<Map<String, dynamic>> verifyShortCode(String code, String guardianId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/recovery/verify-code'),
        headers: {'Content-Type': 'application/json', 'Bypass-Tunnel-Reminder': 'true'},
        body: jsonEncode({'code': code, 'guardianId': guardianId}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Verification failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<Map<String, dynamic>> verifyToken(String token, String guardianId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/recovery/verify'),
        headers: {'Content-Type': 'application/json', 'Bypass-Tunnel-Reminder': 'true'},
        body: jsonEncode({'token': token, 'guardianId': guardianId}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'message': data['message']};
      } else {
        return {'success': false, 'message': data['message'] ?? 'Verification failed'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Connection error: $e'};
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
  }

  Future<String?> getToken() async {
    return await _storage.read(key: 'jwt');
  }

  Future<User?> getUser() async {
    final userStr = await _storage.read(key: 'user');
    if (userStr != null) {
      return User.fromJson(jsonDecode(userStr));
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/users/all'),
        headers: {'Bypass-Tunnel-Reminder': 'true'},
      );
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAuditLogs() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/logs'),
        headers: {'Bypass-Tunnel-Reminder': 'true'},
      );
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
