import 'package:flutter/material.dart';

// Auth
import 'package:vision_aid_app/features/auth/login_screen.dart';
import 'package:vision_aid_app/features/auth/guardian_screen.dart';
import 'package:vision_aid_app/features/auth/role_selection_screen.dart';

// Core
import 'package:vision_aid_app/core/widgets/main_navigation_wrapper.dart';

// Features - AI
import 'package:vision_aid_app/features/ai_assistant/vision_screen.dart' as vision_screen;

// Features - Tracker
import 'package:vision_aid_app/features/tracker/live_tracking_page.dart';

// Features - Navigation (cvnav)
import 'package:vision_aid_app/features/navigation/voice_screen.dart';
import 'package:vision_aid_app/features/navigation/home_screen.dart';
import 'package:vision_aid_app/features/navigation/settings_screen.dart';

// Features - Guardian (workspace)
import 'package:vision_aid_app/features/guardian/guardian_map_screen.dart';

// Features - User (workspace)
import 'package:vision_aid_app/features/user/user_home_screen.dart';

import 'route_constants.dart';

class AppRouter {
  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      // ── Auth ──
      case RouteConstants.login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case RouteConstants.roleSelection:
        return MaterialPageRoute(builder: (_) => const RoleSelectionScreen());

      // ── Main App ──
      case RouteConstants.mainNav:
        return MaterialPageRoute(builder: (_) => const MainNavigationWrapper());

      // ── AI Assistant ──
      case RouteConstants.aiAssistant:
      case RouteConstants.visionScreen:
        return MaterialPageRoute(builder: (_) => const vision_screen.VisionScreen());

      // ── GPS Tracker ──
      case RouteConstants.tracker:
        return MaterialPageRoute(builder: (_) => const LiveTrackingPage());

      // ── Voice Navigation ──
      case RouteConstants.voiceNav:
        return MaterialPageRoute(builder: (_) => const VoiceScreen());
      case RouteConstants.voiceDashboard:
        return MaterialPageRoute(builder: (_) => const HomeScreen());
      case RouteConstants.settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());

      // ── Guardian (workspace) ──
      case RouteConstants.guardian:
        return MaterialPageRoute(builder: (_) => const GuardianScreen());
      case RouteConstants.guardianMap:
        return MaterialPageRoute(builder: (_) => const GuardianMapScreen());

      // ── User Home (workspace) ──
      case RouteConstants.userHome:
        return MaterialPageRoute(builder: (_) => const UserHomeScreen());

      // ── Fallback ──
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${settings.name}'),
            ),
          ),
        );
    }
  }
}
