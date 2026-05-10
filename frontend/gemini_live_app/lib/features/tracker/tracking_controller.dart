import 'dart:async';
import 'package:vision_aid_app/core/services/tracking_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:vision_aid_app/core/services/socket_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vision_aid_app/features/tracker/location_model.dart';

class TrackingController {
  final TrackingService _trackingService = TrackingService();

  Future<void> sendLocationUpdate(String userId, double lat, double lng) async {
    await _trackingService.updateLocation(
      userId: userId,
      latitude: lat,
      longitude: lng,
    );
  }

  Stream<LocationModel?> getLocationUpdates() {
    final controller = StreamController<LocationModel?>();
    
    // 1. Listen to Socket.io (Mobile-to-Mobile sync)
    socketService.onLocationUpdate((data) {
      if (data['lat'] != null && data['lng'] != null) {
        controller.add(LocationModel(
          userId: data['userId'] ?? 'unknown',
          lat: (data['lat'] as num).toDouble(),
          lng: (data['lng'] as num).toDouble(),
          timestamp: data['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        ));
      }
    });

    return controller.stream;
  }

  Stream<LocationModel?> getIoTLocationUpdates(String userId) {
    final database = FirebaseDatabase.instance;
    return database.ref('locations/$userId').onValue.map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data != null && data['lat'] != null && data['lng'] != null) {
        return LocationModel(
          userId: userId,
          lat: (data['lat'] as num).toDouble(),
          lng: (data['lng'] as num).toDouble(),
          timestamp: data['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
        );
      }
      return null;
    });
  }

  Stream<Position> getMyPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    );
  }

  Future<bool> handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    return permission != LocationPermission.deniedForever;
  }
}
