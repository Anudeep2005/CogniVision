import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/global_voice_service.dart';
import '../gps_features/user/user_provider.dart';
import 'socket_service.dart';
import 'navigation_service.dart';

class CommandRouter {
  final Ref ref;
  final _voiceService = VoiceService();

  CommandRouter(this.ref);

  Future<void> routeCommand(String command) async {
    final lowerCmd = command.toLowerCase();

    // 1. Check for explicit navigation triggers
    final navTriggers = [
      'navigate to', 'take me to', 'route to', 'directions to', 'go to', 'find '
    ];
    String? destination;

    for (var trigger in navTriggers) {
      if (lowerCmd.contains(trigger)) {
        destination = lowerCmd.split(trigger).last.trim();
        break;
      }
    }

    // 2. If a navigation trigger was found, execute immediately
    if (destination != null && destination.isNotEmpty) {
      ref.read(userModeProvider.notifier).setMode(AppMode.navigation);
      await _executeNavigation(destination);
      return;
    }

    // 3. Start navigation command
    if (lowerCmd == 'start' ||
        lowerCmd == 'start navigation' ||
        lowerCmd == 'begin' ||
        lowerCmd == "let's go") {
      final routeState = ref.read(routeProvider);
      if (routeState.steps.isNotEmpty && !routeState.isActiveNavigation) {
        ref.read(routeProvider.notifier).startNavigation();
        await _voiceService.speak(
            'Starting navigation. ${routeState.steps[0].instruction}');
        return;
      } else if (routeState.isActiveNavigation) {
        await _voiceService.speak('Navigation is already active.');
        return;
      } else {
        await _voiceService.speak(
            'Please set a destination first before starting navigation.');
        return;
      }
    }

    // 4. SOS command — use current authenticated user's UID
    if (lowerCmd.contains('alert guardian') ||
        lowerCmd.contains('help') ||
        lowerCmd.contains('sos')) {
      await _triggerSOS();
      return;
    }

    // 5. Mode switching
    if (lowerCmd.contains('navigation') || lowerCmd.contains('navigate')) {
      ref.read(userModeProvider.notifier).setMode(AppMode.navigation);
      await _voiceService.speak('Switched to Navigation mode. Tell me your destination.');
      return;
    }

    // 6. Fallback: treat as a destination search
    debugPrint('[CommandRouter] No trigger matched. Fallback search for: $command');
    await _executeNavigation(command);
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
    await _voiceService.speak('Alerting your guardian immediately.');
    // Use the authenticated user's UID — never a hardcoded placeholder
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      debugPrint('[CommandRouter] SOS triggered but no authenticated user found');
      await _voiceService.speak('Could not send SOS — you are not logged in.');
      return;
    }
    socketService.sendSosAlert(userId);
  }
}

final commandRouterProvider = Provider<CommandRouter>((ref) {
  return CommandRouter(ref);
});
