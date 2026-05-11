import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'voice_engine.dart';
import '../features/user/user_provider.dart';
import 'socket_service.dart';
import 'navigation_service.dart';

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
    else if (lowerCmd.contains('alert guardian') || lowerCmd.contains('help') || lowerCmd.contains('sos')) {
      await _triggerSOS();
    } 
    else {
      // 4. Fallback: If no system command matched, but we are ALREADY in Navigation mode, 
      // assume the user just said the name of the place! (e.g. "Central Park")
      if (ref.read(userModeProvider) == AppMode.navigation) {
         await _executeNavigation(command);
      } else {
        await voiceEngine.speak("I didn't catch that. Please say navigation, vision, profile, or alert guardian.");
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
    // In a real app, this userId comes from the logged-in user's profile
    socketService.socket.emit('SOS_ALERT', {
      'userId': 'user_123',
      'type': 'SOS',
      'status': 'active'
    });
  }
}

final commandRouterProvider = Provider<CommandRouter>((ref) {
  return CommandRouter(ref);
});
