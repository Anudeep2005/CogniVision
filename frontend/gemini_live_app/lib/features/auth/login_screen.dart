import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vision_aid_app/core/services/api_service.dart';
import 'package:vision_aid_app/core/widgets/ui_components.dart';
import 'package:vision_aid_app/core/widgets/branding.dart';
import 'package:vision_aid_app/providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  bool _isRegistering = false;
  String _selectedRole = 'user';
  bool _isLoading = false;

  final _apiService = ApiService();

  Future<void> _handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final displayName = _displayNameController.text.trim();

    // 1. Robust Input Validation
    if (email.isEmpty || !RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
      _showError('Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      _showError('Password must be at least 6 characters long.');
      return;
    }
    if (_isRegistering && displayName.isEmpty) {
      _showError('Please enter your display name.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isRegistering) {
        final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        
        await _apiService.register(
          firebaseUid: userCredential.user!.uid,
          role: _selectedRole,
          displayName: displayName,
          email: email,
        );
        ref.read(userRoleProvider.notifier).state = _selectedRole;
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        
        // Fetch role from backend (if applicable)
        ref.read(userRoleProvider.notifier).state = 'user'; 
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Authentication failed.');
    } catch (e) {
      _showError('An unexpected error occurred: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Reuse the luxury background from the main screen
          const LuxuryBackground(),
          
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LeafAppIcon(size: 80),
                        const SizedBox(height: 10),
                        Text(
                          'CogniVision',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: const Color(0xFF1F5C45),
                            fontSize: 32,
                          ),
                        ),
                        const SizedBox(height: 30),
                        
                        if (_isRegistering) ...[
                          _buildTextField(_displayNameController, 'Display Name', Icons.person_outline),
                          const SizedBox(height: 15),
                        ],
                        
                        _buildTextField(_emailController, 'Email', Icons.email_outlined),
                        const SizedBox(height: 15),
                        _buildTextField(_passwordController, 'Password', Icons.lock_outline, isPassword: true),
                        
                        if (_isRegistering) ...[
                          const SizedBox(height: 25),
                          const Text('I am a...', style: TextStyle(color: Color(0xFF1F5C45), fontWeight: FontWeight.w600)),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: _buildRoleButton('user', 'User')),
                              const SizedBox(width: 15),
                              Expanded(child: _buildRoleButton('guardian', 'Guardian')),
                            ],
                          ),
                        ],
                        
                        const SizedBox(height: 40),
                        
                        _isLoading 
                          ? const CircularProgressIndicator(color: Color(0xFFC8A96B))
                          : SizedBox(
                              width: double.infinity,
                              height: 55,
                              child: ElevatedButton(
                                onPressed: _handleAuth,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1F5C45),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                                  elevation: 5,
                                ),
                                child: Text(_isRegistering ? 'Create Account' : 'Sign In', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              ),
                            ),
                        
                        const SizedBox(height: 20),
                        
                        TextButton(
                          onPressed: () => setState(() => _isRegistering = !_isRegistering),
                          child: Text(
                            _isRegistering ? 'Already have an account? Sign In' : 'New here? Create Account',
                            style: const TextStyle(color: Color(0xFF1F5C45)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, IconData icon, {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xFF1F5C45).withValues(alpha: 0.6)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildRoleButton(String role, String label) {
    bool isSelected = _selectedRole == role;
    return GestureDetector(
      onTap: () => setState(() => _selectedRole = role),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFC8A96B) : Colors.white.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isSelected ? const Color(0xFFC8A96B) : Colors.transparent),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF1F5C45),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
