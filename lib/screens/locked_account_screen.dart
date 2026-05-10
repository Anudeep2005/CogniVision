import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/auth_provider.dart';

class LockedAccountScreen extends StatefulWidget {
  final String email;
  final String userId;
  const LockedAccountScreen({super.key, required this.email, required this.userId});

  @override
  State<LockedAccountScreen> createState() => _LockedAccountScreenState();
}

class _LockedAccountScreenState extends State<LockedAccountScreen> {
  String? _recoveryToken;
  String? _shortCode;
  bool _isLoading = false;
  final FlutterTts _tts = FlutterTts();
  Timer? _statusPollingTimer;

  @override
  void initState() {
    super.initState();
    _generateToken();
    _initTts();
    _startPolling();
  }

  void _startPolling() {
    // Poll every 3 seconds to see if the account was unlocked by a guardian
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final auth = context.read<AuthProvider>();
      final isStillLocked = await auth.isUserLocked(widget.userId);
      
      if (!isStillLocked && mounted) {
        timer.cancel();
        _speak("Success! Your account has been unlocked. Returning to login.");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account Unlocked!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    });
  }

  void _initTts() async {
    await _tts.setLanguage("en-US");
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(0.5);
  }

  Future<void> _generateToken() async {
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final data = await auth.getRecoveryData(widget.userId);
    if (mounted) {
      setState(() {
        _recoveryToken = data['recoveryToken'];
        _shortCode = data['shortCode'];
        _isLoading = false;
      });
      if (_shortCode != null) {
        String spokenCode = _shortCode!.split('').join(' ');
        _speak("Your account is locked. Your six digit recovery code is $spokenCode. Tell this code to your guardian.");
      }
    }
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  void _copyToken() {
    if (_shortCode != null) {
      Clipboard.setData(ClipboardData(text: _shortCode!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Recovery code copied')),
      );
      _speak("Code copied.");
    }
  }

  void _shareToken() {
    if (_shortCode != null) {
      Share.share("My recovery code is: $_shortCode");
      _speak("Sharing recovery code.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Semantics(
          label: "Account Locked Screen",
          child: const Text('Account Locked'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Semantics(
                label: "Warning Icon",
                child: const Icon(Icons.lock_person_rounded, size: 100, color: Colors.orangeAccent),
              ),
              const SizedBox(height: 32),
              Semantics(
                header: true,
                child: Text(
                  'SECURITY ALERT',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                label: "Instructions: Your account is disabled. Share the following code with your guardian to unlock.",
                child: Text(
                  'Your account is disabled.\nTell this code to your guardian.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 18),
                ),
              ),
              const SizedBox(height: 40),
              if (_isLoading)
                const CircularProgressIndicator(color: Colors.orangeAccent)
              else if (_shortCode != null) ...[
                // High Contrast Code Container
                Semantics(
                  label: "Recovery Code: $_shortCode",
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.orangeAccent, width: 3),
                    ),
                    child: Text(
                      _shortCode!,
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'OR SCAN QR CODE',
                  style: TextStyle(color: Colors.white24, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (_recoveryToken != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: _recoveryToken!,
                      version: QrVersions.auto,
                      size: 120.0,
                    ),
                  ),
                const SizedBox(height: 32),
                
                // Accessibility Actions
                _buildLargeButton(
                  icon: Icons.copy_rounded,
                  label: "COPY RECOVERY CODE",
                  color: const Color(0xFF6366F1),
                  onPressed: _copyToken,
                ),
                const SizedBox(height: 16),
                _buildLargeButton(
                  icon: Icons.volume_up_rounded,
                  label: "READ CODE ALOUD",
                  color: Colors.orangeAccent,
                  onPressed: () => _speak("Your code is ${_shortCode!.split('').join(' ')}"),
                ),
                const SizedBox(height: 16),
                _buildLargeButton(
                  icon: Icons.share_rounded,
                  label: "SHARE CODE",
                  color: const Color(0xFF10B981),
                  onPressed: _shareToken,
                ),
              ] else ...[
                const Text('Failed to generate recovery token', style: TextStyle(color: Colors.redAccent)),
                const SizedBox(height: 16),
                _buildLargeButton(
                  icon: Icons.refresh,
                  label: "RETRY GENERATION",
                  color: Colors.white24,
                  onPressed: _generateToken,
                ),
              ],
              const SizedBox(height: 40),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to Login', style: TextStyle(color: Colors.white54, fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLargeButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 28),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 70), // Extra large for accessibility
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _statusPollingTimer?.cancel();
    _tts.stop();
    super.dispose();
  }
}
