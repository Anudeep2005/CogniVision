import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';
import 'package:vision_aid_app/src/ui_components/ui_components.dart';
import 'package:vision_aid_app/src/screens/main_navigation_wrapper.dart';
import 'package:vision_aid_app/src/face_features/registered_face.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  await Hive.initFlutter();
  Hive.registerAdapter(RegisteredFaceAdapter());
  await Hive.openBox<RegisteredFace>('faces');
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
      home: const MainNavigationWrapper(),
    );
  }
}
