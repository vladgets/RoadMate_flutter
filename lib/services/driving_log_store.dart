import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A single driving event (trip start or park).
class DrivingEvent {
  final String id;
  final String type; // 'start' | 'park'
  final String timestamp; // ISO8601 UTC
  final double? lat;
  final double? lon;
  final String? address;

  DrivingEvent({
    required this.id,
    required this.type,
    required this.timestamp,
    this.lat,
    this.lon,
    this.address,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'timestamp': timestamp,
        if (lat != null) 'lat': lat,
        if (lon != null) 'lon': lon,
        if (address != null) 'address': address,
      };

  static DrivingEvent fromJson(Map<String, dynamic> json) => DrivingEvent(
        id: json['id'] as String,
        type: (json['type'] ?? 'start').toString(),
        timestamp: (json['timestamp'] ?? '').toString(),
        lat: (json['lat'] as num?)?.toDouble(),
        lon: (json['lon'] as num?)?.toDouble(),
        address: json['address'] as String?,
      );
}

/// Singleton store for driving events.
/// Persists to SharedPreferences as JSON (newest-first, max 500 events).
class DrivingLogStore {
  DrivingLogStore._();
  static final DrivingLogStore instance = DrivingLogStore._();

  static const String _storageKey = 'driving_events_v1';
  static const int _maxEvents = 500;
  static const _uuid = Uuid();

  List<DrivingEvent> _events = [];
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _load();
    _initialized = true;
    debugPrint('[DrivingLogStore] Initialized with ${_events.length} events');
  }

  List<DrivingEvent> get allEvents => List.unmodifiable(_events);

  /// Log a driving event. [type] is 'start' or 'park'.
  /// [location] is the map returned by getBestEffortBackgroundLocation.
  Future<DrivingEvent> logEvent(String type, Map<String, dynamic> location) async {
    await init();

    double? lat;
    double? lon;
    String? address;

    if (location['ok'] == true) {
      lat = (location['lat'] as num?)?.toDouble();
      lon = (location['lon'] as num?)?.toDouble();
      final addr = location['address'];
      if (addr is Map) {
        final parts = <String>[];
        final street = addr['street'];
        final city = addr['city'];
        final state = addr['state'];
        if (street != null && (street as String).isNotEmpty) parts.add(street);
        if (city != null && (city as String).isNotEmpty) parts.add(city);
        if (state != null && (state as String).isNotEmpty) parts.add(state);
        if (parts.isNotEmpty) address = parts.join(', ');
      }
    }

    final event = DrivingEvent(
      id: _uuid.v4(),
      type: type,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      lat: lat,
      lon: lon,
      address: address,
    );

    _events.insert(0, event);

    // Auto-prune oldest events when over limit
    if (_events.length > _maxEvents) {
      _events = _events.sublist(0, _maxEvents);
    }

    await _save();
    debugPrint('[DrivingLogStore] Logged $type event: ${event.id}${address != null ? ' at $address' : ''}');
    return event;
  }

  List<DrivingEvent> getRecentEvents(int limit) {
    if (_events.isEmpty) return [];
    final count = limit.clamp(1, _events.length);
    return List.unmodifiable(_events.sublist(0, count));
  }

  /// Tool handler for get_driving_log.
  Future<Map<String, dynamic>> toolGetDrivingLog(dynamic args) async {
    await init();

    int limit = 10;
    if (args is Map) {
      final raw = args['limit'];
      if (raw is int) limit = raw.clamp(1, 50);
      if (raw is num) limit = raw.toInt().clamp(1, 50);
    }

    final events = getRecentEvents(limit);

    return {
      'ok': true,
      'events': events.map((e) => e.toJson()).toList(),
      'count': events.length,
    };
  }

  // ---- Internal ----

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.trim().isEmpty) {
        _events = [];
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _events = [];
        return;
      }

      _events = decoded
          .whereType<Map>()
          .map((e) => DrivingEvent.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      debugPrint('[DrivingLogStore] Failed to load: $e');
      _events = [];
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_events.map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (e) {
      debugPrint('[DrivingLogStore] Failed to save: $e');
    }
  }
}
