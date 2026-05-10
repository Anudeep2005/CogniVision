import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:math';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  // 1. Auth: Sign Up with Role
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      User? user = result.user;
      if (user != null) {
        // Store user role in Firestore
        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': name,
          'email': email,
          'role': role,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return {'success': true, 'user': user};
      }
      return {'success': false, 'message': 'User creation failed'};
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'message': "[${e.code}] ${e.message}"};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // 2. Pairing: Generate Token for VI User
  Future<String> generatePairingToken(String uid) async {
    String token = "COGN-${Random().nextInt(900) + 100}-${Random().nextInt(90) + 10}X";
    
    await _firestore.collection('pairing_tokens').doc(uid).set({
      'token': token,
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': DateTime.now().add(const Duration(hours: 24)),
    });
    
    return token;
  }

  // 3. Pairing: Connect Guardian to User
  Future<Map<String, dynamic>> connectGuardian(String guardianUid, String token) async {
    try {
      // Find the user with this token
      QuerySnapshot query = await _firestore
          .collection('pairing_tokens')
          .where('token', isEqualTo: token)
          .get();

      if (query.docs.isEmpty) {
        return {'success': false, 'message': 'Invalid or expired token'};
      }

      String userUid = query.docs.first['uid'];

      // Create a connection request
      await _firestore.collection('connections').add({
        'userUid': userUid,
        'guardianUid': guardianUid,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      return {'success': true, 'message': 'Connection request sent'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // 4. Monitoring: Update Location (Realtime Database)
  void updateLiveLocation(String uid, double lat, double lng) {
    _rtdb.ref('locations/$uid').set({
      'lat': lat,
      'lng': lng,
      'lastUpdated': ServerValue.timestamp,
    });
  }

  // 5. Monitoring: Trigger SOS
  Future<void> triggerSOS(String uid) async {
    await _firestore.collection('alerts').add({
      'userUid': uid,
      'type': 'SOS',
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'active',
    });
  }
}
