import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vision_aid_app/core/services/voice_engine.dart';
import 'package:vision_aid_app/features/user/user_provider.dart';
import 'package:vision_aid_app/core/services/socket_service.dart';
import 'package:vision_aid_app/core/services/navigation_service.dart';
import 'package:vision_aid_app/core/services/api_service.dart';
import 'package:vision_aid_app/core/services/gemini_service.dart';
import 'package:geolocator/geolocator.dart';

class CommandRouter {
  final Ref ref;

  CommandRouter(this.ref);

  Future<void> routeCommand(String command) async {
    final lowerCmd = command.toLowerCase();

    // 1. Check for explicit navigation triggers
    final navTriggers = ['navigate to', 'take me to', 'route to', 'directions to', 'go to', 'find '];
    String? destination;

    for (var trigger in navTriggers) {
      if (lowerCmd.contains(trigger)) {
        destination = lowerCmd.split(trigger).last.trim();
        break;
      }
    }

    // 2. If a trigger was found, execute navigation immediately
    if (destination != null && destination.isNotEmpty) {
      ref.read(userModeProvider.notifier).setMode(AppMode.navigation);
      await _executeNavigation(destination);
      return;
    }

    // 3. Check for 'start navigation' command
    if (lowerCmd == 'start' || lowerCmd == 'start navigation' || lowerCmd == 'begin' || lowerCmd == "let's go") {
      final routeState = ref.read(routeProvider);
      if (routeState.steps.isNotEmpty && !routeState.isActiveNavigation) {
        ref.read(routeProvider.notifier).startNavigation();
        await voiceEngine.speak("Starting navigation. " + routeState.steps[0].instruction);
        return;
      } else if (routeState.isActiveNavigation) {
        await voiceEngine.speak("Navigation is already active.");
        return;
      } else {
        await voiceEngine.speak("Please set a destination first before starting navigation.");
        return;
      }
    }

    // 4. Otherwise, check for standard mode switching commands
    if (lowerCmd.contains('navigation') || lowerCmd.contains('navigate')) {
      ref.read(userModeProvider.notifier).setMode(AppMode.navigation);
      await voiceEngine.speak('Switched to Navigation mode. Tell me your destination.');
    } 
    else if (lowerCmd.contains('vision') || lowerCmd.contains('describe')) {
      ref.read(userModeProvider.notifier).setMode(AppMode.vision);
      await voiceEngine.speak('Switched to Vision mode. Scanning surroundings.');
      // Phase 7: Trigger Gemini/Gemma Vision here
    } 
    else if (lowerCmd.contains('profile')) {
      ref.read(userModeProvider.notifier).setMode(AppMode.profile);
      await voiceEngine.speak('Profile mode. Your pair code is A B C D 1 2 3 4.');
    } 
    else if (lowerCmd.contains('alert guardian') || lowerCmd.contains('help') || lowerCmd.contains('sos')) {
      await _triggerSOS();
    } 
    else {
      // 4. Fallback: If no system command matched, but we are ALREADY in Navigation mode, 
      // assume the user just said the name of the place! (e.g. "Central Park")
      if (ref.read(userModeProvider) == AppMode.navigation) {
         await _executeNavigation(command);
      } else {
        // Use Gemini for general queries
        await voiceEngine.speak("Thinking...");
        final response = await geminiService.askGemini(command);
        await voiceEngine.speak(response);
      }
    }
  }

  Future<void> _executeNavigation(String destination) async {
    final routeState = await navigationService.navigateTo(destination);
    if (routeState != null) {
      ref.read(routeProvider.notifier).updateRoute(
        routeState.polylines, 
        routeState.markers, 
        routeState.bounds!,
        routeState.steps,
        routeState.totalDistance,
        routeState.totalDuration,
      );
    }
  }

  Future<void> _triggerSOS() async {
    await voiceEngine.speak('Alerting your guardian immediately.');
    
    // 1. Send via Socket for real-time update
    socketService.socket.emit('SOS_ALERT', {
      'userId': 'user_123',
      'type': 'SOS',
      'status': 'active'
    });

    // 2. Send via REST for persistence and push notifications
    try {
      final position = await Geolocator.getCurrentPosition();
      final apiService = ApiService();
      await apiService.triggerSos(
        firebaseUid: 'user_123_firebase', // Mocked UID
        lat: position.latitude,
        lng: position.longitude,
      );
    } catch (e) {
      debugPrint('Failed to send SOS to backend: $e');
    }
  }
}

final commandRouterProvider = Provider<CommandRouter>((ref) {
  return CommandRouter(ref);
});
