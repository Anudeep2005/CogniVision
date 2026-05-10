import 'package:flutter/material.dart';
import 'package:vision_aid_app/features/guardian/guardian_map_screen.dart';
import 'package:vision_aid_app/features/user/user_home_screen.dart';
import 'package:vision_aid_app/core/constants/app_colors.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cognivision Setup', style: TextStyle(color: AppColors.offWhite, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryGreen,
        centerTitle: true,
        elevation: 0,
      ),
      backgroundColor: AppColors.offWhite,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Select Your Role',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 32, 
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryGreen,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Choose how you will be using the application.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 50),
              ElevatedButton.icon(
                icon: const Icon(Icons.visibility, size: 32, color: AppColors.primaryGreen),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text(
                    'I am a Visually Impaired User', 
                    style: TextStyle(fontSize: 18, color: AppColors.primaryGreen, fontWeight: FontWeight.bold)
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentGold,
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const UserHomeScreen()),
                  );
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.admin_panel_settings, size: 32, color: AppColors.primaryGreen),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text(
                    'I am a Guardian/Caregiver', 
                    style: TextStyle(fontSize: 18, color: AppColors.primaryGreen, fontWeight: FontWeight.bold)
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentGreen,
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const GuardianMapScreen()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
