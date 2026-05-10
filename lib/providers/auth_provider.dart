import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../services/firebase_service.dart';
import '../services/auth_service.dart';

class AuthProvider with ChangeNotifier {
  final FirebaseService _firebaseService = FirebaseService();
  final AuthService _authService = AuthService();
  final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;
  
  User? _user;
  bool _isLoading = false;
  String? _errorMessage;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // 1. Login
  Future<Map<String, dynamic>> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _authService.login(email, password);

      if (result['success']) {
        _user = result['user'];
        _isLoading = false;
        notifyListeners();
        return {'success': true};
      }
      
      _isLoading = false;
      _errorMessage = result['message'];
      notifyListeners();
      return {
        'success': false, 
        'message': _errorMessage, 
        'locked': result['locked'], 
        'userId': result['userId']
      };
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      debugPrint("Login error: $_errorMessage");
      notifyListeners();
      return {'success': false, 'message': _errorMessage};
    }
  }

  // 2. Sign Up
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _authService.signUp(
      email: email,
      password: password,
      role: role,
    );

    _isLoading = false;
    if (result['success']) {
      _user = result['user'];
      // Still update Firestore for other features (location, etc)
      await _firebaseService.signUp(
        email: email, 
        password: password, 
        name: name, 
        role: role
      );
      notifyListeners();
      return {'success': true};
    } else {
      _errorMessage = result['message'];
      notifyListeners();
      return {'success': false, 'message': _errorMessage};
    }
  }

  // 3. Logout
  Future<void> logout() async {
    await _auth.signOut();
    _user = null;
    notifyListeners();
  }

  // 4. Check Status
  Future<void> checkAuthStatus() async {
    fb.User? fbUser = _auth.currentUser;
    if (fbUser != null) {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(fbUser.uid)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _user = User(
          id: fbUser.uid,
          email: fbUser.email!,
          role: data['role'] ?? 'user',
        );
        notifyListeners();
      }
    }
  }

  // 5. Pairing & Recovery logic
  Future<String> generateToken() async {
    if (_user == null) return "";
    return await _firebaseService.generatePairingToken(_user!.id);
  }

  Future<Map<String, dynamic>> connectToUser(String token) async {
    if (_user == null || _user!.role != 'guardian') {
      return {'success': false, 'message': 'Only guardians can pair'};
    }
    return await _firebaseService.connectGuardian(_user!.id, token);
  }

  // Compatibility methods for existing screens
  Future<Map<String, dynamic>> getRecoveryData(String userId) async {
    final token = await _firebaseService.generatePairingToken(userId);
    return {
      'recoveryToken': "cognivision://pair?token=$token&user=$userId",
      'shortCode': token,
    };
  }

  Future<bool> isUserLocked(String userId) async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return data['isLocked'] ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> verifyRecoveryToken(String token) async {
    return await connectToUser(token);
  }

  Future<Map<String, dynamic>> verifyRecoveryCode(String code) async {
    return await connectToUser(code);
  }
}
