import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../ui_components/ui_components.dart';

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
    setState(() => _isLoading = true);
    try {
      if (_isRegistering) {
        final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        
        await _apiService.register(
          firebaseUid: userCredential.user!.uid,
          role: _selectedRole,
          displayName: _displayNameController.text.trim(),
          email: _emailController.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

// LuxuryBackground and _Blob removed to use shared components from ui_components

