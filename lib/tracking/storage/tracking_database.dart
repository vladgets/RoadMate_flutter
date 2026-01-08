import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import '../models/segment.dart';
import '../models/location_fix.dart';
import '../models/tracking_event.dart';
import '../models/activity_state.dart';

/// База данных для хранения данных трекинга
class TrackingDatabase {
  static final TrackingDatabase _instance = TrackingDatabase._internal();
  static Database? _database;
  
  factory TrackingDatabase() => _instance;
  TrackingDatabase._internal();
  
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }
  
  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, 'tracking.db');
    
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }
  
  Future<void> _onCreate(Database db, int version) async {
    // Таблица segments
    await db.execute('''
      CREATE TABLE segments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        state TEXT NOT NULL,
        t_start INTEGER NOT NULL,
        t_end INTEGER,
        t_confirm INTEGER,
        anchor_lat REAL,
        anchor_lon REAL,
        anchor_accuracy REAL,
        polyline TEXT,
        stats TEXT,
        confidence REAL,
        synced INTEGER NOT NULL DEFAULT 0
      )
    ''');
    
    // Таблица location_points
    await db.execute('''
      CREATE TABLE location_points (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        segment_id INTEGER,
        lat REAL NOT NULL,
        lon REAL NOT NULL,
        accuracy REAL,
        speed REAL,
        heading REAL,
        provider TEXT,
        timestamp INTEGER NOT NULL,
        accepted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (segment_id) REFERENCES segments(id)
      )
    ''');
    
    // Таблица events
    await db.execute('''
      CREATE TABLE events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_event_id TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        synced_at INTEGER,
        retry_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
    
    // Таблица current_state (singleton)
    await db.execute('''
      CREATE TABLE current_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        state TEXT NOT NULL,
        last_location_lat REAL,
        last_location_lon REAL,
        last_update INTEGER NOT NULL,
        confidence REAL
      )
    ''');
    
    // Индексы
    await db.execute('CREATE INDEX idx_segments_t_start ON segments(t_start)');
    await db.execute('CREATE INDEX idx_segments_synced ON segments(synced)');
    await db.execute('CREATE INDEX idx_location_points_segment_id ON location_points(segment_id)');
    await db.execute('CREATE INDEX idx_location_points_timestamp ON location_points(timestamp)');
    await db.execute('CREATE INDEX idx_events_synced ON events(synced_at)');
    await db.execute('CREATE INDEX idx_events_created_at ON events(created_at)');
  }
  
  // ========== SEGMENTS ==========
  
  Future<int> insertSegment(Segment segment) async {
    final db = await database;
    return await db.insert('segments', _segmentToMap(segment));
  }
  
  Future<void> updateSegment(Segment segment) async {
    if (segment.id == null) return;
    final db = await database;
    await db.update(
      'segments',
      _segmentToMap(segment),
      where: 'id = ?',
      whereArgs: [segment.id],
    );
  }
  
  Future<List<Segment>> getSegments({
    int? limit,
    int? offset,
    bool? synced,
  }) async {
    final db = await database;
    String query = 'SELECT * FROM segments WHERE 1=1';
    List<dynamic> args = [];
    
    if (synced != null) {
      query += ' AND synced = ?';
      args.add(synced ? 1 : 0);
    }
    
    query += ' ORDER BY t_start DESC';
    
    if (limit != null) {
      query += ' LIMIT ?';
      args.add(limit);
      if (offset != null) {
        query += ' OFFSET ?';
        args.add(offset);
      }
    }
    
    final List<Map<String, dynamic>> maps = await db.rawQuery(query, args);
    return maps.map((map) => _segmentFromMap(map)).toList();
  }
  
  Future<Segment?> getActiveSegment() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'segments',
      where: 't_end IS NULL',
      orderBy: 't_start DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return _segmentFromMap(maps.first);
  }
  
  Future<void> markSegmentsSynced(List<int> segmentIds) async {
    if (segmentIds.isEmpty) return;
    final db = await database;
    final placeholders = segmentIds.map((_) => '?').join(',');
    await db.rawUpdate(
      'UPDATE segments SET synced = 1 WHERE id IN ($placeholders)',
      segmentIds,
    );
  }
  
  // ========== LOCATION POINTS ==========
  
  Future<int> insertLocationPoint({
    required LocationFix location,
    int? segmentId,
    bool accepted = false,
  }) async {
    final db = await database;
    return await db.insert('location_points', {
      'segment_id': segmentId,
      'lat': location.latitude,
      'lon': location.longitude,
      'accuracy': location.accuracy,
      'speed': location.speed,
      'heading': location.heading,
      'provider': location.provider,
      'timestamp': location.timestamp.millisecondsSinceEpoch,
      'accepted': accepted ? 1 : 0,
    });
  }
  
  Future<List<LocationFix>> getLocationPointsForSegment(int segmentId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'location_points',
      where: 'segment_id = ? AND accepted = 1',
      whereArgs: [segmentId],
      orderBy: 'timestamp ASC',
    );
    return maps.map((map) => _locationFixFromMap(map)).toList();
  }
  
  Future<void> deleteLocationPointsForSegment(int segmentId) async {
    final db = await database;
    await db.delete(
      'location_points',
      where: 'segment_id = ?',
      whereArgs: [segmentId],
    );
  }
  
  // ========== EVENTS ==========
  
  Future<int> insertEvent(TrackingEvent event) async {
    final db = await database;
    try {
      return await db.insert('events', _eventToMap(event));
    } catch (e) {
      // Если дубликат client_event_id, игнорируем
      return -1;
    }
  }
  
  Future<List<TrackingEvent>> getUnsyncedEvents({int limit = 100}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'events',
      where: 'synced_at IS NULL',
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return maps.map((map) => _eventFromMap(map)).toList();
  }
  
  Future<void> markEventSynced(String clientEventId) async {
    final db = await database;
    await db.update(
      'events',
      {'synced_at': DateTime.now().millisecondsSinceEpoch},
      where: 'client_event_id = ?',
      whereArgs: [clientEventId],
    );
  }
  
  Future<void> incrementEventRetry(String clientEventId) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE events SET retry_count = retry_count + 1 WHERE client_event_id = ?',
      [clientEventId],
    );
  }
  
  // ========== CURRENT STATE ==========
  
  Future<void> updateCurrentState({
    required ActivityState state,
    double? lastLocationLat,
    double? lastLocationLon,
    double? confidence,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Проверяем, существует ли запись
    final existing = await db.query('current_state', limit: 1);
    
    if (existing.isEmpty) {
      await db.insert('current_state', {
        'id': 1,
        'state': state.name,
        'last_location_lat': lastLocationLat,
        'last_location_lon': lastLocationLon,
        'last_update': now,
        'confidence': confidence,
      });
    } else {
      await db.update(
        'current_state',
        {
          'state': state.name,
          'last_location_lat': lastLocationLat,
          'last_location_lon': lastLocationLon,
          'last_update': now,
          'confidence': confidence,
        },
        where: 'id = 1',
      );
    }
  }
  
  Future<Map<String, dynamic>?> getCurrentState() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('current_state', limit: 1);
    if (maps.isEmpty) return null;
    return maps.first;
  }
  
  // ========== HELPERS ==========
  
  Map<String, dynamic> _segmentToMap(Segment segment) {
    return {
      'id': segment.id,
      'type': segment.type.name,
      'state': segment.state.name,
      't_start': segment.tStart.millisecondsSinceEpoch,
      't_end': segment.tEnd?.millisecondsSinceEpoch,
      't_confirm': segment.tConfirm?.millisecondsSinceEpoch,
      'anchor_lat': segment.anchorLat,
      'anchor_lon': segment.anchorLon,
      'anchor_accuracy': segment.anchorAccuracy,
      'polyline': segment.polyline != null 
          ? jsonEncode(segment.polyline!.map((p) => p.toJson()).toList())
          : null,
      'stats': segment.stats != null ? jsonEncode(segment.stats) : null,
      'confidence': segment.confidence,
      'synced': segment.synced ? 1 : 0,
    };
  }
  
  Segment _segmentFromMap(Map<String, dynamic> map) {
    List<LocationFix>? polyline;
    if (map['polyline'] != null) {
      final List<dynamic> polylineJson = jsonDecode(map['polyline'] as String);
      polyline = polylineJson
          .map((p) => LocationFix.fromJson(p as Map<String, dynamic>))
          .toList();
    }
    
    Map<String, dynamic>? stats;
    if (map['stats'] != null) {
      stats = jsonDecode(map['stats'] as String) as Map<String, dynamic>;
    }
    
    return Segment(
      id: map['id'] as int?,
      type: SegmentType.values.firstWhere(
        (e) => e.name == map['type'] as String,
        orElse: () => SegmentType.movement,
      ),
      state: ActivityStateExtension.fromString(map['state'] as String) ?? ActivityState.still,
      tStart: DateTime.fromMillisecondsSinceEpoch(map['t_start'] as int),
      tEnd: map['t_end'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['t_end'] as int)
          : null,
      tConfirm: map['t_confirm'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['t_confirm'] as int)
          : null,
      anchorLat: map['anchor_lat'] as double?,
      anchorLon: map['anchor_lon'] as double?,
      anchorAccuracy: map['anchor_accuracy'] as double?,
      polyline: polyline,
      stats: stats,
      confidence: map['confidence'] as double?,
      synced: (map['synced'] as int? ?? 0) == 1,
    );
  }
  
  LocationFix _locationFixFromMap(Map<String, dynamic> map) {
    return LocationFix(
      latitude: map['lat'] as double,
      longitude: map['lon'] as double,
      accuracy: map['accuracy'] as double?,
      speed: map['speed'] as double?,
      heading: map['heading'] as double?,
      provider: map['provider'] as String?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }
  
  Map<String, dynamic> _eventToMap(TrackingEvent event) {
    return {
      'id': event.id,
      'client_event_id': event.clientEventId,
      'type': event.type.name,
      'payload': jsonEncode(event.payload),
      'created_at': event.createdAt.millisecondsSinceEpoch,
      'synced_at': event.syncedAt?.millisecondsSinceEpoch,
      'retry_count': event.retryCount,
    };
  }
  
  TrackingEvent _eventFromMap(Map<String, dynamic> map) {
    return TrackingEvent(
      id: map['id'] as int?,
      clientEventId: map['client_event_id'] as String,
      type: TrackingEventType.values.firstWhere(
        (e) => e.name == map['type'] as String,
        orElse: () => TrackingEventType.locationFix,
      ),
      payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      syncedAt: map['synced_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['synced_at'] as int)
          : null,
      retryCount: map['retry_count'] as int? ?? 0,
    );
  }
  
  Future<void> close() async {
    final db = await database;
    await db.close();
  }
  
  Future<void> deleteAllData() async {
    final db = await database;
    await db.delete('events');
    await db.delete('location_points');
    await db.delete('segments');
    await db.delete('current_state');
  }
}

