import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:vision_aid_app/core/services/api_service.dart';

class TrackingService {
  final ApiService _apiService = ApiService();
  final FirebaseDatabase _database = FirebaseDatabase.instance;
  
  String get baseUrl => _apiService.baseUrl;

  Future<void> updateLocation({
    required String userId,
    required double latitude,
    required double longitude,
  }) async {
    // 1. Sync to MongoDB (via Backend API)
    try {
      await http.post(
        Uri.parse('$baseUrl/location/update'), // Updated to match latest API route
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'firebaseUid': userId, // Updated to match backend field
          'lat': latitude,
          'lng': longitude,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      print('MongoDB Sync Error: $e');
    }

    // 2. Sync to Firebase Realtime Database (for IoT layer compliance)
    try {
      await _database.ref('locations/$userId').set({
        'lat': latitude,
        'lng': longitude,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      print('Firebase RTDB Sync Error: $e');
    }
  }
}
