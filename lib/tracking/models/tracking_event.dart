import 'activity_state.dart';
import 'location_fix.dart';

/// Типы событий системы трекинга
enum TrackingEventType {
  trackingStarted,
  stateChanged,
  stopStarted,
  stopConfirmed,
  stopEnded,
  locationFix,
}

/// Модель события системы трекинга
class TrackingEvent {
  final int? id; // для БД
  final String clientEventId; // уникальный ID клиента
  final TrackingEventType type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final int retryCount;
  
  TrackingEvent({
    this.id,
    required this.clientEventId,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.syncedAt,
    this.retryCount = 0,
  });
  
  /// Создает событие TRACKING_STARTED
  factory TrackingEvent.trackingStarted({
    required LocationFix location,
    required DateTime timestamp,
  }) {
    return TrackingEvent(
      clientEventId: _generateEventId(),
      type: TrackingEventType.trackingStarted,
      payload: {
        'location': location.toJson(),
        'timestamp': timestamp.toIso8601String(),
        'latitude': location.latitude,
        'longitude': location.longitude,
      },
      createdAt: DateTime.now(),
    );
  }
  
  /// Создает событие STATE_CHANGED
  factory TrackingEvent.stateChanged({
    required ActivityState oldState,
    required ActivityState newState,
    required double confidence,
    required DateTime timestamp,
    double? latitude,
    double? longitude,
  }) {
    return TrackingEvent(
      clientEventId: _generateEventId(),
      type: TrackingEventType.stateChanged,
      payload: {
        'old_state': oldState.name,
        'new_state': newState.name,
        'confidence': confidence,
        'timestamp': timestamp.toIso8601String(),
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
      createdAt: DateTime.now(),
    );
  }
  
  /// Создает событие STOP_STARTED
  factory TrackingEvent.stopStarted({
    required LocationFix anchorCandidate,
    required DateTime timestamp,
  }) {
    return TrackingEvent(
      clientEventId: _generateEventId(),
      type: TrackingEventType.stopStarted,
      payload: {
        'anchor_candidate': anchorCandidate.toJson(),
        'timestamp': timestamp.toIso8601String(),
      },
      createdAt: DateTime.now(),
    );
  }
  
  /// Создает событие STOP_CONFIRMED
  factory TrackingEvent.stopConfirmed({
    required String stopId,
    required LocationFix anchor,
    required DateTime tStart,
    required double confidence,
  }) {
    return TrackingEvent(
      clientEventId: _generateEventId(),
      type: TrackingEventType.stopConfirmed,
      payload: {
        'stop_id': stopId,
        'anchor': anchor.toJson(),
        't_start': tStart.toIso8601String(),
        'confidence': confidence,
      },
      createdAt: DateTime.now(),
    );
  }
  
  /// Создает событие STOP_ENDED
  factory TrackingEvent.stopEnded({
    required String stopId,
    required DateTime tEnd,
  }) {
    return TrackingEvent(
      clientEventId: _generateEventId(),
      type: TrackingEventType.stopEnded,
      payload: {
        'stop_id': stopId,
        't_end': tEnd.toIso8601String(),
      },
      createdAt: DateTime.now(),
    );
  }
  
  /// Создает событие LOCATION_FIX
  factory TrackingEvent.locationFix({
    required LocationFix location,
  }) {
    return TrackingEvent(
      clientEventId: _generateEventId(),
      type: TrackingEventType.locationFix,
      payload: {
        'location': location.toJson(),
      },
      createdAt: DateTime.now(),
    );
  }
  
  static String _generateEventId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch}';
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'client_event_id': clientEventId,
    'type': type.name,
    'payload': payload,
    'created_at': createdAt.toIso8601String(),
    'synced_at': syncedAt?.toIso8601String(),
    'retry_count': retryCount,
  };
  
  factory TrackingEvent.fromJson(Map<String, dynamic> json) {
    return TrackingEvent(
      id: json['id'] as int?,
      clientEventId: json['client_event_id'] as String,
      type: TrackingEventType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TrackingEventType.locationFix,
      ),
      payload: json['payload'] as Map<String, dynamic>,
      createdAt: DateTime.parse(json['created_at'] as String),
      syncedAt: json['synced_at'] != null 
          ? DateTime.parse(json['synced_at'] as String) 
          : null,
      retryCount: json['retry_count'] as int? ?? 0,
    );
  }
  
  TrackingEvent copyWith({
    int? id,
    String? clientEventId,
    TrackingEventType? type,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    DateTime? syncedAt,
    int? retryCount,
  }) {
    return TrackingEvent(
      id: id ?? this.id,
      clientEventId: clientEventId ?? this.clientEventId,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}

