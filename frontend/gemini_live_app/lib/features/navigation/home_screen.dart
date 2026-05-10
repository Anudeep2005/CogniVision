import 'package:flutter/material.dart';
import 'package:vision_aid_app/features/navigation/voice_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
      appBar: AppBar(title: const Text("Home")),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Welcome Home",
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Your voice-controlled dashboard",
                  style: TextStyle(fontSize: 16, color: Colors.white54),
                ),
                const SizedBox(height: 32),
                _buildCard(
                  icon: Icons.mic,
                  title: "Voice Control",
                  subtitle: "Tap anywhere to start speaking",
                  color: const Color(0xFF6366F1),
                ),
                const SizedBox(height: 16),
                _buildCard(
                  icon: Icons.navigation,
                  title: "Smart Navigation",
                  subtitle: "Say 'Settings' or 'Back' to move",
                  color: const Color(0xFF10B981),
                ),
              ],
            ),
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

  Widget _buildCard({required IconData icon, required String title, required String subtitle, required Color color}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(fontSize: 14, color: Colors.white54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
