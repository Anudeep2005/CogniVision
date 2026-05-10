import 'package:flutter/material.dart';
import 'package:vision_aid_app/features/navigation/voice_service.dart';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  VoiceScreenState createState() => VoiceScreenState();
}

class VoiceScreenState extends State<VoiceScreen> with SingleTickerProviderStateMixin {
  final VoiceService _voiceService = VoiceService();
  String _displayWords = "say 'Home' or 'Settings'";
  bool _isListening = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _voiceService.onWordsChanged = (words) {
      if (mounted) setState(() => _displayWords = words);
    };
    _voiceService.onListeningChanged = (listening) {
      if (mounted) setState(() => _isListening = listening);
    };
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Voice Control")),
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: _isListening
                          ? [
                              BoxShadow(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.5 * _pulseController.value),
                                blurRadius: 40 * _pulseController.value,
                                spreadRadius: 20 * _pulseController.value,
                              ),
                            ]
                          : [],
                    ),
                    child: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      size: 80,
                      color: _isListening ? const Color(0xFF6366F1) : Colors.white24,
                    ),
                  );
                },
              ),
              const SizedBox(height: 40),
              Text(
                _isListening ? "Listening..." : "Tap anywhere to start",
                style: TextStyle(
                  color: _isListening ? const Color(0xFF6366F1) : Colors.white38,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  _displayWords,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const Spacer(),
              const Text(
                "Commands: 'Home', 'Settings', 'Back'",
                style: TextStyle(color: Colors.white24, fontSize: 14),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
