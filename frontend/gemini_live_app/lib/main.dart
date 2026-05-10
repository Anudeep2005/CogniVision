import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:vision_aid_app/core/theme/theme.dart';
import 'firebase_options.dart';

// Core
import 'package:vision_aid_app/core/services/voice_engine.dart';

// Auth
import 'package:vision_aid_app/features/auth/login_screen.dart';
import 'package:vision_aid_app/features/auth/guardian_screen.dart';

// Navigation
import 'package:vision_aid_app/core/widgets/main_navigation_wrapper.dart';
import 'package:vision_aid_app/routes/app_router.dart';

// State
import 'package:vision_aid_app/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await dotenv.load(fileName: "lib/.env");
  await voiceEngine.init();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return MaterialApp(
      title: 'CogniVision',
      theme: themeData,
      debugShowCheckedModeBanner: false,
      onGenerateRoute: AppRouter.generateRoute,
      home: authState.when(
        data: (user) {
          if (user == null) return const LoginScreen();
          final role = ref.watch(userRoleProvider);
          if (role == 'guardian') return const GuardianScreen();
          return const MainNavigationWrapper();
        },
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          body: Center(child: Text('Error: $e')),
        ),
      ),
    );
  }
}
