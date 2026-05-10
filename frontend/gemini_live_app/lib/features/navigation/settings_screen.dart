import 'package:flutter/material.dart';
import 'package:vision_aid_app/features/navigation/voice_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final VoiceService _voiceService = VoiceService();
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    _voiceService.onListeningChanged = (listening) {
      if (mounted) setState(() => _isListening = listening);
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: GestureDetector(
        onTap: () {
          if (_isListening) {
            _voiceService.stopListening();
          } else {
            _voiceService.startListening();
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            children: [
              _buildSettingTile(Icons.person, "Profile", "Manage your account"),
              _buildSettingTile(
                Icons.notifications,
                "Notifications",
                "Alerts and sounds",
              ),
              _buildSettingTile(
                Icons.security,
                "Security",
                "Privacy and safety",
              ),
              _buildSettingTile(
                Icons.language,
                "Language",
                "Voice recognition settings",
              ),
              _buildSettingTile(
                Icons.help,
                "Help & Support",
                "FAQs and contact",
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_isListening) {
            _voiceService.stopListening();
          } else {
            _voiceService.startListening();
          }
        },
        backgroundColor: _isListening ? Colors.red : const Color(0xFF6366F1),
        child: Icon(_isListening ? Icons.stop : Icons.mic, color: Colors.white),
      ),
    );
  }

  Widget _buildSettingTile(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF6366F1)),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
        trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      ),
    );
  }
}
