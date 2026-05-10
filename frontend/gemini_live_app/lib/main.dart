import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'firebase_options.dart';
import 'package:vision_aid_app/src/flutterfire_ai_live_api_demo.dart';
import 'package:vision_aid_app/src/ui_components/ui_components.dart';
import 'package:vision_aid_app/src/screens/login_screen.dart';
import 'package:vision_aid_app/src/screens/guardian_screen.dart';
import 'package:vision_aid_app/src/services/api_service.dart';
import 'package:vision_aid_app/src/providers.dart';
import 'package:vision_aid_app/src/screens/main_navigation_wrapper.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Vision Aid - CogniVision',
      theme: themeData,
      debugShowCheckedModeBanner: false,
      home: MainNavigationWrapper(),
    );
  }
}
