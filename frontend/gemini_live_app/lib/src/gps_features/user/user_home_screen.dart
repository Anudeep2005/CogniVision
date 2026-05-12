import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'user_provider.dart';
import '../../gps_core/command_router.dart';
import '../../gps_core/navigation_service.dart';
import '../../gps_core/socket_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../services/global_voice_service.dart';
import '../../ui_components/luxury_background.dart';
import '../../ui_components/ui_components.dart';

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
  final VoiceService _voiceService = VoiceService();

  @override
  void initState() {
    super.initState();
    // Connect to socket for this user
    socketService.initSocket('user_123');
    
    // Debug API Key
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? dotenv.env['MAPS_API_KEY'];
    debugPrint('DEBUG: MAPS_API_KEY is ${apiKey?.substring(0, 5)}...');
    
    _startLocationTracking();
    
    // Listen for voice status changes
    _voiceService.addStatusListener(_onVoiceStatusChanged);
    
    // Listen for commands
    _voiceService.addCommandListener(_handleGlobalCommand);
  }

  void _onVoiceStatusChanged(bool listening) {
    if (mounted) setState(() => _isListening = listening);
  }

  // Updated to use Global Voice Service
  void _handleGlobalCommand(String command) {
    if (mounted && _voiceService.currentIndex == 1) {
       debugPrint("UserHomeScreen: Received command while active: $command");
       ref.read(commandRouterProvider).routeCommand(command);
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _voiceService.removeStatusListener(_onVoiceStatusChanged);
    _voiceService.removeCommandListener(_handleGlobalCommand);
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await _voiceService.speak("Location services are disabled. I am opening your settings now.");
      await Geolocator.openLocationSettings();
      return;
    }

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
          navigationService.updateLiveLocation(position, routeState, (RouteState newState) {
             ref.read(routeProvider.notifier).updateState(newState);
          });
        }
      }
      socketService.sendLocationUpdate('user_123', position.latitude, position.longitude);
      debugPrint('Location sent: ${position.latitude}, ${position.longitude}');
    });
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

    ref.listen<RouteState>(routeProvider, (previous, next) async {
      if (next.bounds != null) {
        final GoogleMapController controller = await _mapController.future;
        controller.animateCamera(CameraUpdate.newLatLngBounds(next.bounds!, 50));
      }
    });

    CameraPosition initialCameraPosition = const CameraPosition(
      target: LatLng(37.7749, -122.4194), 
      zoom: 14,
    );

    if (_currentPosition != null) {
      initialCameraPosition = CameraPosition(
        target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
        zoom: 16,
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          const LuxuryBackground(),
          
          // MAP is visible here
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
          
          // Transparent listener for voice (if user taps map area)
          // but we use HitTestBehavior.translucent so it doesn't block map panning
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (_voiceService.isListening) {
                _voiceService.stopListening();
              } else {
                _voiceService.startListening();
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
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF20563F).withOpacity(0.2)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, 8))
                  ]
                ),
                child: Row(
                  children: [
                    Icon(
                      _getTurnIcon(routeState.steps[routeState.currentStepIndex].instruction), 
                      color: const Color(0xFF20563F), 
                      size: 44
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${routeState.currentDistanceToManeuver} m",
                            style: const TextStyle(color: Color(0xFF20563F), fontSize: 26, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            routeState.steps[routeState.currentStepIndex].instruction,
                            style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w500),
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
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(25), topRight: Radius.circular(25)),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 15, offset: Offset(0, -5))
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
                          style: const TextStyle(color: Color(0xFF20563F), fontSize: 28, fontWeight: FontWeight.w800),
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
    );
  }
}
