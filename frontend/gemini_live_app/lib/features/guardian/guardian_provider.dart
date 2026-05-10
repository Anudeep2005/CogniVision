import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:vision_aid_app/core/services/socket_service.dart';
import 'package:vision_aid_app/providers.dart';

// State to hold the visually impaired user's location
class GuardianState {
  final LatLng? trackedLocation;
  final bool hasAlert;

  GuardianState({this.trackedLocation, this.hasAlert = false});

  GuardianState copyWith({LatLng? trackedLocation, bool? hasAlert}) {
    return GuardianState(
      trackedLocation: trackedLocation ?? this.trackedLocation,
      hasAlert: hasAlert ?? this.hasAlert,
    );
  }
}

class GuardianNotifier extends Notifier<GuardianState> {
  @override
  GuardianState build() {
    // Initialize socket connection using real Auth UID
    final authState = ref.read(authStateProvider);
    final userId = authState.value?.uid ?? 'anonymous_guardian';
    socketService.initSocket(userId);

    // Listen for location updates
    socketService.onLocationUpdate((data) {
      final double lat = data['lat'];
      final double lng = data['lng'];
      state = state.copyWith(trackedLocation: LatLng(lat, lng));
    });

    // Listen for SOS alerts
    socketService.onSosAlert((data) {
      state = state.copyWith(hasAlert: true);
    });

    return GuardianState();
  }

  void clearAlert() {
    state = state.copyWith(hasAlert: false);
  }
}

final guardianProvider = NotifierProvider<GuardianNotifier, GuardianState>(() {
  return GuardianNotifier();
});
