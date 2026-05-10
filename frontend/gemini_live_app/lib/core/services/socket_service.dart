import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter/foundation.dart';

class SocketService {
  late IO.Socket socket;
  
  // Singleton pattern
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  void initSocket(String userId) {
    const String serverUrl = String.fromEnvironment(
      'API_BASE_URL', 
      defaultValue: 'http://localhost:3000'
    );
    
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.connect();

    socket.onConnect((_) {
      debugPrint('Connected to Socket.IO Server');
      // Join a room using our userId to receive personal alerts
      socket.emit('join', userId);
    });

    socket.onDisconnect((_) => debugPrint('Disconnected from Socket.IO Server'));
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
    }
  }
}

final socketService = SocketService();
