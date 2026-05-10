import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vision_aid_app/core/widgets/ui_components.dart';
import 'package:vision_aid_app/routes/route_constants.dart';

class GuardianScreen extends StatelessWidget {
  const GuardianScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const LuxuryBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const LeafAppIcon(size: 50),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, color: Color(0xFF1F5C45)),
                        onPressed: () => FirebaseAuth.instance.signOut(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 60),
                  const AppTitle(title: 'Guardian Dashboard'),
                  const SizedBox(height: 100),
                  
                  // Navigate to User Button
                  GestureDetector(
                    onTap: () {
                      Navigator.pushNamed(context, RouteConstants.guardianMap);
                    },
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFC8A96B), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFC8A96B).withValues(alpha: 0.2),
                            blurRadius: 30,
                            spreadRadius: 5,
                          )
                        ],
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.map_rounded, size: 80, color: Color(0xFFC8A96B)),
                          SizedBox(height: 15),
                          Text(
                            'Navigate to User',
                            style: TextStyle(
                              color: Color(0xFF1F5C45),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const Spacer(),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 40),
                    child: Text(
                      'Monitoring User Location...',
                      style: TextStyle(color: Color(0xFF355847), fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
