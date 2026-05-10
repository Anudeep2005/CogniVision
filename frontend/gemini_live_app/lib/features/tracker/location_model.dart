class LocationModel {
  final String userId;
  final double lat;
  final double lng;
  final int timestamp;

  LocationModel({
    required this.userId,
    required this.lat, 
    required this.lng, 
    required this.timestamp
  });

  factory LocationModel.fromMap(Map<dynamic, dynamic> map) {
    return LocationModel(
      userId: map['userId'] ?? 'unknown',
      lat: (map['lat'] as num).toDouble(),
      lng: (map['lng'] as num).toDouble(),
      timestamp: map['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
