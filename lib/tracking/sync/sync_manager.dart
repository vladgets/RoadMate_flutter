import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../storage/event_queue.dart';
import '../storage/tracking_database.dart';
import '../models/tracking_event.dart';
import '../models/segment.dart';

/// Менеджер синхронизации данных с сервером
class SyncManager {
  final EventQueue _eventQueue;
  final TrackingDatabase _database;
  final String? _serverUrl;
  final String? _apiKey;
  
  Timer? _syncTimer;
  bool _isSyncing = false;
  
  SyncManager({
    required EventQueue eventQueue,
    required TrackingDatabase database,
    String? serverUrl,
    String? apiKey,
  })  : _eventQueue = eventQueue,
        _database = database,
        _serverUrl = serverUrl,
        _apiKey = apiKey;
  
  /// Начать периодическую синхронизацию
  void startPeriodicSync({Duration interval = const Duration(minutes: 5)}) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (_) {
      sync();
    });
  }
  
  /// Остановить периодическую синхронизацию
  void stopPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }
  
  /// Синхронизировать данные с сервером
  Future<void> sync() async {
    if (_isSyncing || _serverUrl == null) return;
    
    _isSyncing = true;
    
    try {
      // Синхронизируем события
      await _syncEvents();
      
      // Синхронизируем сегменты
      await _syncSegments();
      
      // Синхронизируем текущее состояние
      await _syncCurrentState();
    } catch (e) {
      // ignore: avoid_print
      print('Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }
  
  Future<void> _syncEvents() async {
    final unsyncedEvents = await _eventQueue.getUnsyncedEvents(limit: 100);
    if (unsyncedEvents.isEmpty) return;
    
    // Группируем события в батчи
    final batches = _batchEvents(unsyncedEvents, batchSize: 50);
    
    for (final batch in batches) {
      try {
        final payload = _buildEventBatchPayload(batch);
        final success = await _sendToServer('/api/events/batch', payload);
        
        if (success) {
          // Отмечаем события как синхронизированные
          for (final event in batch) {
            await _eventQueue.markSynced(event.clientEventId);
          }
        } else {
          // Увеличиваем счетчик повторов
          for (final event in batch) {
            await _eventQueue.incrementRetry(event.clientEventId);
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('Failed to sync event batch: $e');
        // Увеличиваем счетчик повторов для всех событий в батче
        for (final event in batch) {
          await _eventQueue.incrementRetry(event.clientEventId);
        }
      }
    }
  }
  
  Future<void> _syncSegments() async {
    final unsyncedSegments = await _database.getSegments(
      limit: 50,
      synced: false,
    );
    if (unsyncedSegments.isEmpty) return;
    
    try {
      final payload = _buildSegmentsPayload(unsyncedSegments);
      final success = await _sendToServer('/api/segments/batch', payload);
      
      if (success) {
        final segmentIds = unsyncedSegments
            .where((s) => s.id != null)
            .map((s) => s.id!)
            .toList();
        await _database.markSegmentsSynced(segmentIds);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to sync segments: $e');
    }
  }
  
  Future<void> _syncCurrentState() async {
    final currentState = await _database.getCurrentState();
    if (currentState == null) return;
    
    try {
      final payload = {
        'state': currentState['state'],
        'last_location': currentState['last_location_lat'] != null
            ? {
                'lat': currentState['last_location_lat'],
                'lon': currentState['last_location_lon'],
              }
            : null,
        'last_update': currentState['last_update'],
        'confidence': currentState['confidence'],
      };
      
      await _sendToServer('/api/current-state', payload);
    } catch (e) {
      // ignore: avoid_print
      print('Failed to sync current state: $e');
    }
  }
  
  List<List<TrackingEvent>> _batchEvents(
    List<TrackingEvent> events, {
    int batchSize = 50,
  }) {
    final batches = <List<TrackingEvent>>[];
    for (int i = 0; i < events.length; i += batchSize) {
      batches.add(events.sublist(
        i,
        i + batchSize > events.length ? events.length : i + batchSize,
      ));
    }
    return batches;
  }
  
  Map<String, dynamic> _buildEventBatchPayload(List<TrackingEvent> events) {
    return {
      'events': events.map((e) => {
        'client_event_id': e.clientEventId,
        'type': e.type.name,
        'payload': e.payload,
        'created_at': e.createdAt.toIso8601String(),
      }).toList(),
    };
  }
  
  Map<String, dynamic> _buildSegmentsPayload(List<Segment> segments) {
    return {
      'segments': segments.map((s) => s.toJson()).toList(),
    };
  }
  
  Future<bool> _sendToServer(String endpoint, Map<String, dynamic> payload) async {
    if (_serverUrl == null) return false;
    
    try {
      final uri = Uri.parse('$_serverUrl$endpoint');
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      
      if (_apiKey != null) {
        headers['Authorization'] = 'Bearer $_apiKey';
      }
      
      final response = await http.post(
        uri,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 30));
      
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      // ignore: avoid_print
      print('HTTP request failed: $e');
      return false;
    }
  }
  
  void dispose() {
    stopPeriodicSync();
  }
}

