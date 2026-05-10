import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vision_aid_app/core/services/api_service.dart';

class TrackingService {
  final ApiService _apiService = ApiService();
  String get baseUrl => _apiService.baseUrl;

  Future<void> updateLocation({
    required String userId,
    required double latitude,
    required double longitude,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/location'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'userId': userId,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': DateTime.now().toIso8601String(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to update location in MongoDB');
    }
  }

  // Socket logic would go here if using socket_io_client package
}
