/// Model for photo attachments in chat messages
class PhotoAttachment {
  final String path;       // Local file path
  final String? location;  // Human-readable location
  final DateTime? timestamp;
  final double? latitude;
  final double? longitude;

  PhotoAttachment({
    required this.path,
    this.location,
    this.timestamp,
    this.latitude,
    this.longitude,
  });

  /// Serialize to JSON
  Map<String, dynamic> toJson() {
    return {
      'path': path,
      'location': location,
      'timestamp': timestamp?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  /// Deserialize from JSON
  factory PhotoAttachment.fromJson(Map<String, dynamic> json) {
    return PhotoAttachment(
      path: json['path'] as String,
      location: json['location'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
      latitude: json['latitude'] as double?,
      longitude: json['longitude'] as double?,
    );
  }

  @override
  String toString() {
    return 'PhotoAttachment(path: $path, location: $location, timestamp: $timestamp)';
  }
}
