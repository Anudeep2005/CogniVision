import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';
import '../providers/auth_provider.dart';

class GuardianVerifyScreen extends StatefulWidget {
  const GuardianVerifyScreen({super.key});

  @override
  State<GuardianVerifyScreen> createState() => _GuardianVerifyScreenState();
}

class _GuardianVerifyScreenState extends State<GuardianVerifyScreen> {
  final MobileScannerController _controller = MobileScannerController();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final _tokenController = TextEditingController();
  bool _isProcessing = false;

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    
    final String? code = barcodes.first.rawValue;
    if (code != null) {
      _startVerification(code);
    }
  }

  Future<void> _startVerification(String token) async {
    setState(() => _isProcessing = true);
    
    // 1. Biometric Verification for Guardian
    final bool didAuthenticate = await _authenticateGuardian();
    
    if (!didAuthenticate) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric authentication required to proceed')),
        );
      }
      return;
    }

    // 2. Token Verification with Backend
    await _verifyToken(token);
  }

  Future<bool> _authenticateGuardian() async {
    try {
      final bool canAuthenticateWithBiometrics = await _localAuth.canCheckBiometrics;
      final bool canAuthenticate = canAuthenticateWithBiometrics || await _localAuth.isDeviceSupported();

      if (!canAuthenticate) return true; // Fallback if no biometrics

      return await _localAuth.authenticate(
        localizedReason: 'Please authenticate to approve user recovery',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } catch (e) {
      return false;
    }
  }

  Future<void> _verifyToken(String token) async {
    final auth = context.read<AuthProvider>();
    final result = await auth.verifyRecoveryToken(token);

    if (mounted) {
      if (result['success']) {
        _showResultDialog(
          title: 'Account Reactivated',
          message: 'The user account has been successfully verified and unlocked via secure JWT flow.',
          isSuccess: true,
        );
      } else {
        _showResultDialog(
          title: 'Verification Failed',
          message: result['message'] ?? 'The token is invalid, expired, or already used.',
          isSuccess: false,
        );
      }
    }
  }

  void _showResultDialog({required String title, required String message, required bool isSuccess}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(
              isSuccess ? Icons.verified_user_rounded : Icons.gpp_bad_rounded,
              color: isSuccess ? const Color(0xFF10B981) : Colors.redAccent,
              size: 32,
            ),
            const SizedBox(width: 12),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(message, style: const TextStyle(color: Colors.white70, fontSize: 16)),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              if (isSuccess) {
                Navigator.pop(context); // Go back to dashboard
              } else {
                setState(() => _isProcessing = false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isSuccess ? const Color(0xFF10B981) : const Color(0xFF6366F1),
              minimumSize: const Size(100, 45),
            ),
            child: const Text('DONE'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('Guardian Verification'),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard_rounded),
            onPressed: () => _showManualEntryDialog(),
          )
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Scanner Overlay
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF6366F1), width: 3),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: const Center(
                    child: Icon(Icons.qr_code_scanner_rounded, color: Colors.white24, size: 64),
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  'Scan the user\'s recovery QR code',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Biometric authentication will be required',
                  style: TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF6366F1)),
                    SizedBox(height: 24),
                    Text(
                      'SECURE VERIFICATION IN PROGRESS',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                    SizedBox(height: 8),
                    Text('Validating JWT & Guardian Identity', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showManualEntryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Enter Recovery Code', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the 6-digit code provided by the user.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _tokenController,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
              decoration: const InputDecoration(
                hintText: '000000',
                hintStyle: TextStyle(color: Colors.white10),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final code = _tokenController.text.trim();
              if (code.length == 6) {
                Navigator.pop(context);
                _verifyCode(code);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid 6-digit code')),
                );
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyCode(String code) async {
    setState(() => _isProcessing = true);
    
    // Guardian Biometrics first for security
    final bool didAuthenticate = await _authenticateGuardian();
    if (!didAuthenticate) {
      setState(() => _isProcessing = false);
      return;
    }

    final auth = context.read<AuthProvider>();
    final result = await auth.verifyRecoveryCode(code);

    if (mounted) {
      if (result['success']) {
        _showResultDialog(
          title: 'Account Unlocked',
          message: 'The user account has been successfully reactivated via short-code verification.',
          isSuccess: true,
        );
      } else {
        _showResultDialog(
          title: 'Invalid Code',
          message: result['message'] ?? 'The code entered is incorrect or has expired.',
          isSuccess: false,
        );
      }
    }
  }
}
