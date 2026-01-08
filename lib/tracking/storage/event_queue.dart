import '../models/tracking_event.dart';
import 'tracking_database.dart';

/// Очередь событий для синхронизации с сервером
class EventQueue {
  final TrackingDatabase _database;
  
  EventQueue(this._database);
  
  /// Добавить событие в очередь
  Future<void> enqueue(TrackingEvent event) async {
    await _database.insertEvent(event);
  }
  
  /// Получить несинхронизированные события
  Future<List<TrackingEvent>> getUnsyncedEvents({int limit = 100}) async {
    return await _database.getUnsyncedEvents(limit: limit);
  }
  
  /// Отметить событие как синхронизированное
  Future<void> markSynced(String clientEventId) async {
    await _database.markEventSynced(clientEventId);
  }
  
  /// Увеличить счетчик повторов для события
  Future<void> incrementRetry(String clientEventId) async {
    await _database.incrementEventRetry(clientEventId);
  }
  
  /// Получить количество несинхронизированных событий
  Future<int> getUnsyncedCount() async {
    final events = await getUnsyncedEvents(limit: 10000);
    return events.length;
  }
  
  /// Очистить старые синхронизированные события (опционально)
  Future<void> clearOldSyncedEvents({Duration? olderThan}) async {
    // TODO: реализовать очистку старых событий при необходимости
    // Можно добавить метод в TrackingDatabase для удаления старых записей
  }
}

