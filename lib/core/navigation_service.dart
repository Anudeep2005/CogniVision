import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:html/parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../features/user/user_provider.dart';
import 'voice_engine.dart';

class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  Future<RouteState?> navigateTo(String destination) async {
    final String apiKey = dotenv.env['MAPS_API_KEY'] ?? '';

    try {
      voiceEngine.speak("Calculating walking route to $destination.");

      // 1. Get Current Location
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await voiceEngine.speak("Location services are disabled. Please enable them.");
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          await voiceEngine.speak("Location permissions are denied.");
          return null;
        }
      }

      Position? position = await Geolocator.getLastKnownPosition();
      if (position == null) {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
      }
      
      // 2. Fetch Directions
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?origin=${position.latitude},${position.longitude}&destination=$destination&mode=walking&key=$apiKey'
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['status'] == 'OK') {
          final leg = data['routes'][0]['legs'][0];
          final totalDistance = leg['distance']['text'];
          final totalDuration = leg['duration']['text'];
          final steps = leg['steps'];
          List<NavigationStep> navSteps = [];
          for (var step in steps) {
            navSteps.add(NavigationStep(
              startLocation: LatLng(step['start_location']['lat'], step['start_location']['lng']),
              endLocation: LatLng(step['end_location']['lat'], step['end_location']['lng']),
              instruction: _parseHtmlString(step['html_instructions']),
              distanceMeters: step['distance']['value'],
            ));
          }

          // 3. Read Instructions
          await voiceEngine.speak("Route found. Say start to begin navigation.");
          
          // 4. Parse Polyline
          String polylineStr = data['routes'][0]['overview_polyline']['points'];
          List<PointLatLng> decodedPoints = PolylinePoints.decodePolyline(polylineStr);
          List<LatLng> routeCoords = decodedPoints.map((p) => LatLng(p.latitude, p.longitude)).toList();
          
          final boundsData = data['routes'][0]['bounds'];
          LatLngBounds routeBounds = LatLngBounds(
            southwest: LatLng(boundsData['southwest']['lat'], boundsData['southwest']['lng']),
            northeast: LatLng(boundsData['northeast']['lat'], boundsData['northeast']['lng']),
          );

          Polyline routePolyline = Polyline(
            polylineId: const PolylineId('route'),
            color: const Color(0xFF20563F), // primaryGreen
            width: 6,
            points: routeCoords,
          );

          Marker destinationMarker = Marker(
            markerId: const MarkerId('destination'),
            position: routeCoords.last,
            infoWindow: InfoWindow(title: destination),
          );

          return RouteState(
            polylines: {routePolyline},
            markers: {destinationMarker},
            bounds: routeBounds,
            steps: navSteps,
            totalDistance: totalDistance,
            totalDuration: totalDuration,
            currentDistanceToManeuver: navSteps.isNotEmpty ? navSteps[0].distanceMeters : 0,
          );
        } else {
          debugPrint('Directions API Error: ${data['status']}');
          await voiceEngine.speak("I could not find a walking route to $destination.");
        }
      } else {
        await voiceEngine.speak("Network error while fetching directions.");
      }
    } catch (e) {
      debugPrint("Navigation Error: $e");
      await voiceEngine.speak("An error occurred while setting up navigation.");
      return null;
    }
    return null;
  }

  Future<void> updateLiveLocation(Position currentPosition, RouteState routeState, Function(RouteState) updateState) async {
    if (!routeState.isActiveNavigation || routeState.steps.isEmpty) return;
    if (routeState.currentStepIndex >= routeState.steps.length) return;

    final currentStep = routeState.steps[routeState.currentStepIndex];
    
    // Calculate distance to end_location of current step
    double distance = Geolocator.distanceBetween(
      currentPosition.latitude, currentPosition.longitude,
      currentStep.endLocation.latitude, currentStep.endLocation.longitude,
    );

    // If within 15 meters of the turn coordinate, read the next step
    if (distance <= 15.0) { 
      if (routeState.currentStepIndex == routeState.steps.length - 1) {
        await voiceEngine.speak("You have arrived at your destination.");
        // Reset navigation
        updateState(routeState.copyWith(isActiveNavigation: false));
      } else {
        final nextStep = routeState.steps[routeState.currentStepIndex + 1];
        await voiceEngine.speak(nextStep.instruction);
        
        // Advance step
        final newState = routeState.copyWith(
          currentStepIndex: routeState.currentStepIndex + 1,
          currentDistanceToManeuver: nextStep.distanceMeters,
        );
        updateState(newState);
      }
    } else {
      // Just update distance
      updateState(routeState.copyWith(currentDistanceToManeuver: distance.toInt()));
    }
  }

  // Helper method to strip HTML tags from Google's response (e.g. <b>Turn left</b> -> Turn left)
  String _parseHtmlString(String htmlString) {
    final document = parse(htmlString);
    final String parsedString = parse(document.body!.text).documentElement!.text;
    
    // Sometimes Google adds "Destination will be on the left." concatenated. 
    // We clean up double spaces just in case.
    return parsedString.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

final navigationService = NavigationService();
