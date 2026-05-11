import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'user_provider.dart';
import '../../core/voice_engine.dart';
import '../../core/command_router.dart';
import '../../core/navigation_service.dart';
import '../../core/socket_service.dart';
import '../../core/app_colors.dart';

class UserHomeScreen extends ConsumerStatefulWidget {
  const UserHomeScreen({super.key});

  @override
  ConsumerState<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends ConsumerState<UserHomeScreen> {
  bool _isListening = false;
  StreamSubscription<Position>? _positionStreamSubscription;
  final Completer<GoogleMapController> _mapController = Completer<GoogleMapController>();
  Position? _currentPosition;
  bool _hasCenteredOnInitialLocation = false;

  @override
  void initState() {
    super.initState();
    // Connect to socket for this user
    socketService.initSocket('user_123');
    _initVoiceSystem();
    _startLocationTracking();
  }

  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    // Instantly grab last known position to prevent lag
    Position? lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null && mounted) {
      setState(() {
        _currentPosition = lastKnown;
      });
      
      if (!_hasCenteredOnInitialLocation) {
        _hasCenteredOnInitialLocation = true;
        _mapController.future.then((controller) {
          controller.animateCamera(CameraUpdate.newLatLngZoom(
            LatLng(lastKnown.latitude, lastKnown.longitude), 
            16.0
          ));
        });
      }
    }

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Only update if they move 5 meters
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });

        if (!_hasCenteredOnInitialLocation) {
          _hasCenteredOnInitialLocation = true;
          _mapController.future.then((controller) {
            controller.animateCamera(CameraUpdate.newLatLngZoom(
              LatLng(position.latitude, position.longitude), 
              16.0
            ));
          });
        }

        // Live Turn-by-Turn Tracking
        final routeState = ref.read(routeProvider);
        if (routeState.isActiveNavigation) {
          navigationService.updateLiveLocation(position, routeState, (newState) {
             ref.read(routeProvider.notifier).updateState(newState);
          });
        }
      }
      socketService.sendLocationUpdate('user_123', position.latitude, position.longitude);
      debugPrint('Location sent: ${position.latitude}, ${position.longitude}');
    });
  }

  Future<void> _initVoiceSystem() async {
    await voiceEngine.init();
    await voiceEngine.speak("Cognivision active. Tap anywhere on the screen to give a command.");
  }

  Future<void> _triggerAssistant() async {
    if (_isListening) {
      await voiceEngine.stopListening();
      setState(() => _isListening = false);
      return;
    }

    setState(() {
      _isListening = true;
    });

    // Vibrate to let the user know we caught the button press
    HapticFeedback.vibrate();

    await voiceEngine.listen((commandText) async {
      debugPrint("Recognized command: $commandText");
      
      // Pass the recognized text to our Command Router
      await ref.read(commandRouterProvider).routeCommand(commandText);
      
      setState(() {
        _isListening = false;
      });
    });

    // Failsafe reset if speech recognition times out or errors
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isListening) {
        setState(() {
          _isListening = false;
        });
      }
    });
  }

  @override
  void dispose() {
    // Clean up
    _positionStreamSubscription?.cancel();
    voiceEngine.stopSpeaking();
    super.dispose();
  }

  IconData _getTurnIcon(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('left')) return Icons.turn_left;
    if (lower.contains('right')) return Icons.turn_right;
    if (lower.contains('u-turn') || lower.contains('u turn')) return Icons.u_turn_left;
    return Icons.straight;
  }

  @override
  Widget build(BuildContext context) {
    final routeState = ref.watch(routeProvider);

    // If we receive a new route with bounds, animate the camera to fit the route
    ref.listen<RouteState>(routeProvider, (previous, next) async {
      if (next.bounds != null) {
        final GoogleMapController controller = await _mapController.future;
        controller.animateCamera(CameraUpdate.newLatLngBounds(next.bounds!, 50));
      }
    });

    CameraPosition initialCameraPosition = const CameraPosition(
      target: LatLng(37.7749, -122.4194), // Default to SF before location loads
      zoom: 14,
    );

    if (_currentPosition != null) {
      initialCameraPosition = CameraPosition(
        target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        zoom: 16,
      );
    }

    return Scaffold(
      body: GestureDetector(
        onTap: _triggerAssistant,
        behavior: HitTestBehavior.opaque,
        child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: initialCameraPosition,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            polylines: routeState.polylines,
            markers: routeState.markers,
            onMapCreated: (GoogleMapController controller) {
              if (!_mapController.isCompleted) {
                _mapController.complete(controller);
              }
            },
          ),
          
          // Top Banner (Turn Instruction)
          if (routeState.isActiveNavigation && routeState.steps.isNotEmpty)
            Positioned(
              top: 50,
              left: 15,
              right: 15,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F5132), // Dark Green
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))
                  ]
                ),
                child: Row(
                  children: [
                    Icon(
                      _getTurnIcon(routeState.steps[routeState.currentStepIndex].instruction), 
                      color: Colors.white, 
                      size: 40
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${routeState.currentDistanceToManeuver} m",
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            routeState.steps[routeState.currentStepIndex].instruction,
                            style: const TextStyle(color: Colors.white, fontSize: 20),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom Banner (ETA and Distance Summary)
          if (routeState.isActiveNavigation)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))
                  ]
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, size: 30, color: Colors.black54),
                      onPressed: () {
                        ref.read(routeProvider.notifier).clearRoute();
                        ref.read(userModeProvider.notifier).setMode(AppMode.idle);
                      },
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          routeState.totalDuration,
                          style: const TextStyle(color: Colors.green, fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          routeState.totalDistance,
                          style: const TextStyle(color: Colors.black54, fontSize: 16),
                        ),
                      ],
                    ),
                    const IconButton(
                      icon: Icon(Icons.alt_route, size: 30, color: Colors.black54),
                      onPressed: null,
                    ),
                  ],
                ),
              ),
            ),

          // Microphone Button
          Positioned(
            bottom: routeState.isActiveNavigation ? 130 : 40,
            left: 0,
            right: 0,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: routeState.isActiveNavigation ? 20 : 0),
              child: Align(
                alignment: routeState.isActiveNavigation ? Alignment.centerRight : Alignment.center,
                child: routeState.isActiveNavigation
                  ? FloatingActionButton(
                      onPressed: _triggerAssistant,
                      backgroundColor: _isListening ? Colors.redAccent : AppColors.primaryGreen,
                      child: Icon(_isListening ? Icons.mic : Icons.mic_none, color: AppColors.offWhite),
                    )
                  : FloatingActionButton.large(
                      onPressed: _triggerAssistant,
                      backgroundColor: _isListening ? Colors.redAccent : AppColors.primaryGreen,
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: AppColors.offWhite,
                        size: 40,
                      ),
                    ),
              ),
            ),
          ),

          // Listening Status Text
          if (_isListening)
            Positioned(
              bottom: 130,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    "Listening...",
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}
