import 'package:flutter/material.dart';
import '../ui_components/ui_components.dart';
import 'login_screen.dart'; // For LuxuryBackground

class GpsNavScreen extends StatelessWidget {
  const GpsNavScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Stack(
        children: [
          LuxuryBackground(),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.map_rounded, size: 80, color: Color(0xFF1F5C45)),
                SizedBox(height: 20),
                AppTitle(title: 'GPS Navigation'),
                SizedBox(height: 10),
                Text('Coming Soon...', style: TextStyle(color: Color(0xFF355847))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FaceRecognitionScreen extends StatelessWidget {
  const FaceRecognitionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Stack(
        children: [
          LuxuryBackground(),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.face_unlock_rounded, size: 80, color: Color(0xFF1F5C45)),
                SizedBox(height: 20),
                AppTitle(title: 'Face Recognition'),
                SizedBox(height: 10),
                Text('Coming Soon...', style: TextStyle(color: Color(0xFF355847))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
