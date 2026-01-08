import 'activity_state.dart';
import 'location_fix.dart';

/// Тип сегмента
enum SegmentType {
  movement,
  stop,
}

/// Модель сегмента движения или остановки
class Segment {
  final int? id; // null для новых сегментов
  final SegmentType type;
  final ActivityState state;
  final DateTime tStart;
  final DateTime? tEnd;
  final DateTime? tConfirm; // для stop - момент подтверждения
  final double? anchorLat; // для stop
  final double? anchorLon; // для stop
  final double? anchorAccuracy; // для stop
  final List<LocationFix>? polyline; // для movement
  final Map<String, dynamic>? stats; // статистика (JSON)
  final double? confidence;
  final bool synced;
  
  Segment({
    this.id,
    required this.type,
    required this.state,
    required this.tStart,
    this.tEnd,
    this.tConfirm,
    this.anchorLat,
    this.anchorLon,
    this.anchorAccuracy,
    this.polyline,
    this.stats,
    this.confidence,
    this.synced = false,
  });
  
  /// Длительность сегмента в секундах
  double? get durationSeconds {
    if (tEnd == null) return null;
    return tEnd!.difference(tStart).inSeconds.toDouble();
  }
  
  /// Является ли сегмент активным (не завершен)
  bool get isActive => tEnd == null;
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'state': state.name,
    't_start': tStart.toIso8601String(),
    't_end': tEnd?.toIso8601String(),
    't_confirm': tConfirm?.toIso8601String(),
    'anchor_lat': anchorLat,
    'anchor_lon': anchorLon,
    'anchor_accuracy': anchorAccuracy,
    'polyline': polyline?.map((p) => p.toJson()).toList(),
    'stats': stats,
    'confidence': confidence,
    'synced': synced,
  };
  
  factory Segment.fromJson(Map<String, dynamic> json) {
    final polylineJson = json['polyline'] as List<dynamic>?;
    return Segment(
      id: json['id'] as int?,
      type: SegmentType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => SegmentType.movement,
      ),
      state: ActivityStateExtension.fromString(json['state'] as String) ?? ActivityState.still,
      tStart: DateTime.parse(json['t_start'] as String),
      tEnd: json['t_end'] != null ? DateTime.parse(json['t_end'] as String) : null,
      tConfirm: json['t_confirm'] != null ? DateTime.parse(json['t_confirm'] as String) : null,
      anchorLat: json['anchor_lat'] as double?,
      anchorLon: json['anchor_lon'] as double?,
      anchorAccuracy: json['anchor_accuracy'] as double?,
      polyline: polylineJson?.map((p) => LocationFix.fromJson(p as Map<String, dynamic>)).toList(),
      stats: json['stats'] as Map<String, dynamic>?,
      confidence: json['confidence'] as double?,
      synced: json['synced'] as bool? ?? false,
    );
  }
  
  Segment copyWith({
    int? id,
    SegmentType? type,
    ActivityState? state,
    DateTime? tStart,
    DateTime? tEnd,
    DateTime? tConfirm,
    double? anchorLat,
    double? anchorLon,
    double? anchorAccuracy,
    List<LocationFix>? polyline,
    Map<String, dynamic>? stats,
    double? confidence,
    bool? synced,
  }) {
    return Segment(
      id: id ?? this.id,
      type: type ?? this.type,
      state: state ?? this.state,
      tStart: tStart ?? this.tStart,
      tEnd: tEnd ?? this.tEnd,
      tConfirm: tConfirm ?? this.tConfirm,
      anchorLat: anchorLat ?? this.anchorLat,
      anchorLon: anchorLon ?? this.anchorLon,
      anchorAccuracy: anchorAccuracy ?? this.anchorAccuracy,
      polyline: polyline ?? this.polyline,
      stats: stats ?? this.stats,
      confidence: confidence ?? this.confidence,
      synced: synced ?? this.synced,
    );
  }
}

