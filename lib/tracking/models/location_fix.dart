import 'dart:math' as math;

/// Модель точки локации с метаданными
class LocationFix {
  final double latitude;
  final double longitude;
  final double? accuracy; // в метрах
  final double? speed; // в м/с
  final double? heading; // в градусах (0-360)
  final String? provider; // GPS, network, etc.
  final DateTime timestamp;
  
  LocationFix({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.speed,
    this.heading,
    this.provider,
    required this.timestamp,
  });
  
  /// Вычисляет расстояние до другой точки в метрах (Haversine)
  double distanceTo(LocationFix other) {
    const double earthRadius = 6371000; // в метрах
    final double dLat = _toRadians(other.latitude - latitude);
    final double dLon = _toRadians(other.longitude - longitude);
    
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(latitude)) *
        math.cos(_toRadians(other.latitude)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.asin(math.sqrt(a));
    
    return earthRadius * c;
  }
  
  double _toRadians(double degrees) => degrees * (math.pi / 180.0);
  
  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lon': longitude,
    'accuracy': accuracy,
    'speed': speed,
    'heading': heading,
    'provider': provider,
    'timestamp': timestamp.toIso8601String(),
  };
  
  factory LocationFix.fromJson(Map<String, dynamic> json) => LocationFix(
    latitude: json['lat'] as double,
    longitude: json['lon'] as double,
    accuracy: json['accuracy'] as double?,
    speed: json['speed'] as double?,
    heading: json['heading'] as double?,
    provider: json['provider'] as String?,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

