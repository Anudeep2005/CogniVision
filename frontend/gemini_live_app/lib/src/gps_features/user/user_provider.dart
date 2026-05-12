import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

enum AppMode { idle, navigation }

class UserModeNotifier extends Notifier<AppMode> {
  @override
  AppMode build() {
    return AppMode.idle;
  }

  void setMode(AppMode mode) {
    state = mode;
  }
}

final userModeProvider = NotifierProvider<UserModeNotifier, AppMode>(() {
  return UserModeNotifier();
});

class NavigationStep {
  final LatLng startLocation;
  final LatLng endLocation;
  final String instruction;
  final int distanceMeters;

  NavigationStep({
    required this.startLocation,
    required this.endLocation,
    required this.instruction,
    required this.distanceMeters,
  });
}

class RouteState {
  final Set<Polyline> polylines;
  final Set<Marker> markers;
  final LatLngBounds? bounds;
  final List<NavigationStep> steps;
  final bool isActiveNavigation;
  final int currentStepIndex;
  
  // New UI variables
  final String totalDistance;
  final String totalDuration;
  final int currentDistanceToManeuver;

  RouteState({
    this.polylines = const {},
    this.markers = const {},
    this.bounds,
    this.steps = const [],
    this.isActiveNavigation = false,
    this.currentStepIndex = 0,
    this.totalDistance = "",
    this.totalDuration = "",
    this.currentDistanceToManeuver = 0,
  });

  RouteState copyWith({
    Set<Polyline>? polylines,
    Set<Marker>? markers,
    LatLngBounds? bounds,
    List<NavigationStep>? steps,
    bool? isActiveNavigation,
    int? currentStepIndex,
    String? totalDistance,
    String? totalDuration,
    int? currentDistanceToManeuver,
  }) {
    return RouteState(
      polylines: polylines ?? this.polylines,
      markers: markers ?? this.markers,
      bounds: bounds ?? this.bounds,
      steps: steps ?? this.steps,
      isActiveNavigation: isActiveNavigation ?? this.isActiveNavigation,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      totalDistance: totalDistance ?? this.totalDistance,
      totalDuration: totalDuration ?? this.totalDuration,
      currentDistanceToManeuver: currentDistanceToManeuver ?? this.currentDistanceToManeuver,
    );
  }
}

class RouteNotifier extends Notifier<RouteState> {
  @override
  RouteState build() {
    return RouteState();
  }

  void updateRoute(
    Set<Polyline> polylines, 
    Set<Marker> markers, 
    LatLngBounds bounds, 
    List<NavigationStep> steps,
    String totalDistance,
    String totalDuration,
  ) {
    state = state.copyWith(
      polylines: polylines, 
      markers: markers, 
      bounds: bounds,
      steps: steps,
      isActiveNavigation: false,
      currentStepIndex: 0,
      totalDistance: totalDistance,
      totalDuration: totalDuration,
      currentDistanceToManeuver: steps.isNotEmpty ? steps[0].distanceMeters : 0,
    );
  }

  void startNavigation() {
    state = state.copyWith(isActiveNavigation: true);
  }

  void advanceStep() {
    state = state.copyWith(currentStepIndex: state.currentStepIndex + 1);
  }

  void updateState(RouteState newState) {
    state = newState;
  }

  void clearRoute() {
    state = RouteState();
  }
}

final routeProvider = NotifierProvider<RouteNotifier, RouteState>(() {
  return RouteNotifier();
});
