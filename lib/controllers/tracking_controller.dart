import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import '../models/location_model.dart';

class TrackingController {
  final DatabaseReference _dbRef = 
      FirebaseDatabase.instance.ref("tracking/currentUser");

  Stream<LocationModel?> getLocationUpdates() {
    return _dbRef.onValue.map((event) {
      final data = event.snapshot.value;
      if (data != null && data is Map) {
        return LocationModel.fromMap(Map<String, dynamic>.from(data));
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