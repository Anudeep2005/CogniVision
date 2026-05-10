import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:vision_aid_app/core/services/api_service.dart';

class TrackingService {
  final ApiService _apiService = ApiService();
  final DatabaseReference _rtdbRef = FirebaseDatabase.instance.ref();
  
  String get baseUrl => _apiService.baseUrl;

  Future<void> updateLocation({
    required String userId,
    required double latitude,
    required double longitude,
  }) async {
    // 1. Sync to Firebase RTDB (for IoT layer compliance)
    try {
      await _rtdbRef.child('users').child(userId).child('location').set({
        'lat': latitude,
        'lng': longitude,
        'timestamp': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Firebase RTDB Sync Error: $e');
    }

    // 2. Sync to MongoDB (via Backend API)
    try {
      await http.post(
        Uri.parse('$baseUrl/location/update'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'firebaseUid': userId,
          'lat': latitude,
          'lng': longitude,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      print('MongoDB Sync Error: $e');
    }
  }
}
