import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SocketService {
  late IO.Socket socket;

  // Singleton pattern
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  /// Server URL loaded from .env (BACKEND_URL).
  /// Falls back to localhost for development.
  String get _serverUrl {
    final raw = dotenv.env['BACKEND_URL'] ?? 'http://localhost:3000/api';
    // Strip /api suffix if present — Socket.IO connects to root
    return raw.replaceAll(RegExp(r'/api$'), '');
  }

  void initSocket(String userId) {
    socket = IO.io(_serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.connect();

    socket.onConnect((_) {
      debugPrint('[SocketService] Connected to server: $_serverUrl');
      socket.emit('join', userId);
    });

    socket.onDisconnect((_) => debugPrint('[SocketService] Disconnected from server'));

    socket.onConnectError((err) => debugPrint('[SocketService] Connection error: $err'));
  }

  void onLocationUpdate(Function(Map<String, dynamic>) callback) {
    socket.on('LOCATION_UPDATE', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  void onSosAlert(Function(Map<String, dynamic>) callback) {
    socket.on('SOS_ALERT', (data) {
      callback(Map<String, dynamic>.from(data));
    });
  }

  void sendLocationUpdate(String userId, double lat, double lng) {
    if (socket.connected) {
      socket.emit('LOCATION_UPDATE', {
        'userId': userId,
        'lat': lat,
        'lng': lng,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } else {
      debugPrint('[SocketService] Cannot send location — socket not connected');
    }
  }

  void sendSosAlert(String userId) {
    if (socket.connected) {
      socket.emit('SOS_ALERT', {
        'userId': userId,
        'type': 'SOS',
        'status': 'active',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      debugPrint('[SocketService] SOS alert sent for user $userId');
    } else {
      debugPrint('[SocketService] Cannot send SOS — socket not connected');
    }
  }

  void disconnect() {
    socket.disconnect();
  }
}

final socketService = SocketService();
