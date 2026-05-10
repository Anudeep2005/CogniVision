import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'firebase_service.dart';

class LocationService {
  final FirebaseService _firebaseService = FirebaseService();
  StreamSubscription<Position>? _positionStreamSubscription;

  // 1. Request Permission
  Future<bool> handlePermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    
    if (permission == LocationPermission.deniedForever) return false;
    return true;
  }

  // 2. Start Live Tracking
  void startTracking(String uid) async {
    final hasPermission = await handlePermission();
    if (!hasPermission) return;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      _firebaseService.updateLiveLocation(
        uid,
        position.latitude,
        position.longitude,
      );
    });
  }

  // 3. Stop Tracking
  void stopTracking() {
    _positionStreamSubscription?.cancel();
  }
}
