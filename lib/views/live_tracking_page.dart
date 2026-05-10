import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/tracking_controller.dart';

class LiveTrackingPage extends StatefulWidget {
  const LiveTrackingPage({super.key});

  @override
  State<LiveTrackingPage> createState() => _LiveTrackingPageState();
}

class _LiveTrackingPageState extends State<LiveTrackingPage> {
  final TrackingController _controller = TrackingController();
  final MapController _mapController = MapController();
  final Color primaryGreen = const Color(0xFF20563F);
  final Color accentGold = const Color(0xFFE8C685);
  final Color accentgreen = const Color(0xFFBFEFD9);
  final Color offWhite = const Color(0xFFF8F9F3);
  final Color mutedGold = const Color(0xFFBBA771);

  LatLng? _myLocation;
  LatLng? _firebaseUserLocation;
  bool _isLoading = true;
  String _distance = "Calculating...";

  @override
  void initState() {
    super.initState();
    _initTracking();
  }

  void _updateDistance() {
    if (_myLocation != null && _firebaseUserLocation != null) {
      double distanceInMeters = Geolocator.distanceBetween(
        _myLocation!.latitude,
        _myLocation!.longitude,
        _firebaseUserLocation!.latitude,
        _firebaseUserLocation!.longitude,
      );

      setState(() {
        if (distanceInMeters < 1000) {
          _distance = "${distanceInMeters.toStringAsFixed(0)} m";
        } else {
          _distance = "${(distanceInMeters / 1000).toStringAsFixed(2)} km";
        }
      });
    }
  }

  void _fitBounds() {
    if (_myLocation != null && _firebaseUserLocation != null) {
      final bounds = LatLngBounds.fromPoints([
        _myLocation!,
        _firebaseUserLocation!,
      ]);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50.0)),
      );
    }
  }

  Future<void> _initTracking() async {
    final hasPermission = await _controller.handleLocationPermission();
    if (hasPermission) {
      _controller.getLocationUpdates().listen((loc) {
        if (loc != null && loc.lat.isFinite && loc.lng.isFinite) {
          setState(() {
            _firebaseUserLocation = LatLng(loc.lat, loc.lng);
          });
          _updateDistance();
          _fitBounds();
        }
      });

      _controller.getMyPositionStream().listen((pos) {
        if (pos.latitude.isFinite && pos.longitude.isFinite) {
          final newPos = LatLng(pos.latitude, pos.longitude);
          setState(() {
            _myLocation = newPos;
            _isLoading = false;
          });
          _updateDistance();
          if (_firebaseUserLocation == null) {
            _mapController.move(newPos, 17.0);
          }
        }
      });
    }
  }

  Future<void> _launchNavigation() async {
    if (_myLocation != null && _firebaseUserLocation != null) {
      final destLat = _firebaseUserLocation!.latitude;
      final destLng = _firebaseUserLocation!.longitude;
      final startLat = _myLocation!.latitude;
      final startLng = _myLocation!.longitude;

      final String googleMapsUrl =
          "https://www.google.com/maps/dir/?api=1&origin=$startLat,$startLng&destination=$destLat,$destLng&travelmode=driving";

      final Uri uri = Uri.parse(googleMapsUrl);

      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          final String fallbackUrl = "google.navigation:q=$destLat,$destLng";
          await launchUrl(Uri.parse(fallbackUrl));
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error: Could not open navigation app")),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Waiting for GPS location...")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _myLocation == null) {
      return Scaffold(
        backgroundColor: accentGold,
        body: Center(child: CircularProgressIndicator(color: primaryGreen)),
      );
    }

    return Scaffold(
      backgroundColor: offWhite,
      appBar: AppBar(
        title: Text(
          "Live Tracking",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: primaryGreen,
          ),
        ),
        centerTitle: true,
        backgroundColor: accentgreen,
        toolbarHeight: 70,
        shape: RoundedRectangleBorder(
          side: BorderSide(width: 4, color: primaryGreen),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
        ),
        elevation: 5,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _myLocation!,
                initialZoom: 15.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.live_tracker_app',
                ),
                MarkerLayer(
                  markers: [
                    if (_firebaseUserLocation != null)
                      Marker(
                        point: _firebaseUserLocation!,
                        width: 50,
                        height: 50,
                        child: Icon(
                          Icons.location_on,
                          color: Colors.redAccent,
                          size: 40,
                        ),
                      ),
                    Marker(
                      point: _myLocation!,
                      width: 50,
                      height: 50,
                      child: Icon(
                        Icons.person_pin_circle,
                        color: Colors.blue,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            flex: 1,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: accentgreen,
                border: Border.all(
                  width: 4,
                  style: BorderStyle.solid,
                  color: primaryGreen,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Tracking User",
                            style: TextStyle(
                              color: primaryGreen.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            "Sai Mani",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: primaryGreen,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: primaryGreen,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text(
                          _distance,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: accentGold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton.icon(
                      onPressed: _launchNavigation,
                      icon: Icon(Icons.navigation, color: accentGold),
                      label: Text(
                        "Start Navigation",
                        style: TextStyle(
                          color: accentGold,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 160),
        child: FloatingActionButton(
          backgroundColor: primaryGreen,
          foregroundColor: accentGold,
          onPressed: _fitBounds,
          mini: true,
          child: const Icon(Icons.zoom_out_map),
        ),
      ),
    );
  }
}
