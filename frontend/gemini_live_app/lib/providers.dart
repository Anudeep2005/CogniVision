import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;

// Re-export feature providers for convenience
export 'package:vision_aid_app/features/user/user_provider.dart';
export 'package:vision_aid_app/features/guardian/guardian_provider.dart';

// ── Auth State ──
final authStateProvider = StreamProvider<auth.User?>((ref) {
  return auth.FirebaseAuth.instance.authStateChanges();
});

final userRoleProvider = StateProvider<String?>((ref) => null);
