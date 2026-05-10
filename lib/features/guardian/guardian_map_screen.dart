import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'guardian_provider.dart';
import '../../core/app_colors.dart';

class GuardianMapScreen extends ConsumerWidget {
  const GuardianMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardianState = ref.watch(guardianProvider);

    // Default position (e.g., city center) if no location tracked yet
    const LatLng defaultLocation = LatLng(17.3850, 78.4867); // Hyderabad

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guardian Tracking', style: TextStyle(color: AppColors.offWhite)),
        backgroundColor: guardianState.hasAlert ? Colors.red : AppColors.primaryGreen,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: guardianState.trackedLocation ?? defaultLocation,
              zoom: 15,
            ),
            markers: guardianState.trackedLocation != null
                ? {
                    Marker(
                      markerId: const MarkerId('tracked_user'),
                      position: guardianState.trackedLocation!,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                      infoWindow: const InfoWindow(title: 'User Location'),
                    )
                  }
                : {},
          ),
          if (guardianState.hasAlert)
            Positioned(
              top: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.white),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'SOS ALERT TRIGGERED!',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => ref.read(guardianProvider.notifier).clearAlert(),
                    )
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
