import 'dart:async';
import '../../services/realtime_session_manager.dart';
import '../core/activity_provider.dart';
import '../core/location_provider.dart';
import '../core/state_machine.dart';
import '../core/stop_detector.dart';
import '../core/track_builder.dart';
import '../core/profile_manager.dart';
import '../core/battery_manager.dart';
import '../core/sound_manager.dart';
import '../storage/tracking_database.dart';
import '../storage/event_queue.dart';
import '../models/activity_state.dart';
import '../models/location_fix.dart';
import '../models/segment.dart';
import '../models/tracking_event.dart';

/// Главный сервис трекинга, оркестрирующий все компоненты
class TrackingService {
  // Компоненты
  final ActivityProvider _activityProvider;
  final LocationProvider _locationProvider;
  final StateMachine _stateMachine;
  final StopDetector _stopDetector;
  final TrackBuilder _trackBuilder;
  final ProfileManager _profileManager;
  final BatteryManager _batteryManager;
  final TrackingDatabase _database;
  final EventQueue _eventQueue;
  
  // Подписки
  StreamSubscription<ActivityState>? _activitySubscription;
  StreamSubscription<LocationFix>? _locationSubscription;
  StreamSubscription<StateChangeEvent>? _stateChangeSubscription;
  StreamSubscription<StopConfirmedEvent>? _stopConfirmedSubscription;
  StreamSubscription<StopEndedEvent>? _stopEndedSubscription;
  
  // Текущее состояние
  ActivityState _currentState = ActivityState.still;
  LocationFix? _lastLocation;
  Segment? _currentSegment;
  bool _isRunning = false;
  
  // Таймеры
  Timer? _statusUpdateTimer;
  Timer? _heartbeatTimer;
  
  TrackingService({
    required ActivityProvider activityProvider,
    required LocationProvider locationProvider,
    required StateMachine stateMachine,
    required StopDetector stopDetector,
    required TrackBuilder trackBuilder,
    required ProfileManager profileManager,
    required BatteryManager batteryManager,
    required TrackingDatabase database,
    required EventQueue eventQueue,
  })  : _activityProvider = activityProvider,
        _locationProvider = locationProvider,
        _stateMachine = stateMachine,
        _stopDetector = stopDetector,
        _trackBuilder = trackBuilder,
        _profileManager = profileManager,
        _batteryManager = batteryManager,
        _database = database,
        _eventQueue = eventQueue;
  
  /// Начать трекинг
  Future<void> start() async {
    if (_isRunning) return;
    
    // Устанавливаем флаг сразу, чтобы предотвратить повторный вызов
    _isRunning = true;
    
    try {
      // Запускаем менеджер батареи
      await _batteryManager.startMonitoring();
      
      // Запускаем провайдеры
      await _activityProvider.start();
      await _locationProvider.start();
      
      // Получаем текущую локацию для события старта
      try {
        final startLocation = await _locationProvider.getCurrentLocation();
        _lastLocation = startLocation;
        final startTimestamp = DateTime.now();
        
        // Проверяем, не было ли недавно создано событие trackingStarted
        // (защита от дублирования при быстрых перезапусках)
        final recentEvents = await _database.getHistoryEvents(limit: 1);
        final hasRecentStart = recentEvents.isNotEmpty &&
            recentEvents.first.type == TrackingEventType.trackingStarted &&
            startTimestamp.difference(recentEvents.first.createdAt).inSeconds < 5;
        
        if (!hasRecentStart) {
          // Создаем событие старта трекинга
          final trackingStartedEvent = TrackingEvent.trackingStarted(
            location: startLocation,
            timestamp: startTimestamp,
          );
          _eventQueue.enqueue(trackingStartedEvent);
        }
      } catch (e) {
        // Если не удалось получить локацию, продолжаем без события старта
        // ignore: avoid_print
        print('Failed to get location for tracking start: $e');
      }
      
      // Подписываемся на события
      _activitySubscription = _activityProvider.activityStream.listen(
        _handleActivityUpdate,
      );
      
      _locationSubscription = _locationProvider.locationStream.listen(
        _handleLocationUpdate,
      );
      
      _stateChangeSubscription = _stateMachine.stateChangeStream.listen(
        _handleStateChange,
      );
      
      _stopConfirmedSubscription = _stopDetector.stopConfirmedStream.listen(
        (event) => _handleStopConfirmed(event),
      );
      
      _stopEndedSubscription = _stopDetector.stopEndedStream.listen(
        (event) => _handleStopEnded(event),
      );
      
      // Запускаем таймеры для обновления статуса
      _startStatusUpdateTimer();
      _startHeartbeatTimer();
    } catch (e) {
      // В случае ошибки сбрасываем флаг
      _isRunning = false;
      // ignore: avoid_print
      print('Failed to start tracking service: $e');
      rethrow;
    }
  }
  
  /// Остановить трекинг
  Future<void> stop() async {
    if (!_isRunning) return;
    
    // Завершаем текущий сегмент, если есть
    await _finalizeCurrentSegment();
    
    // Отменяем подписки
    await _activitySubscription?.cancel();
    await _locationSubscription?.cancel();
    await _stateChangeSubscription?.cancel();
    await _stopConfirmedSubscription?.cancel();
    await _stopEndedSubscription?.cancel();
    
    // Останавливаем провайдеры
    await _activityProvider.stop();
    await _locationProvider.stop();
    _batteryManager.stopMonitoring();
    
    // Останавливаем таймеры
    _statusUpdateTimer?.cancel();
    _heartbeatTimer?.cancel();
    
    _isRunning = false;
  }
  
  void _handleActivityUpdate(ActivityState activityState) {
    // Передаем в state machine для обработки
    _stateMachine.processActivityUpdate(activityState, 0.6);
  }
  
  void _handleLocationUpdate(LocationFix location) {
    _lastLocation = location;
    
    // Обновляем activity provider на основе скорости
    if (location.speed != null) {
      _activityProvider.updateFromSpeed(location.speed);
    }
    
    // Передаем в state machine
    _stateMachine.processLocationUpdate(location);
    
    // Если есть активный сегмент движения, добавляем точку
    if (_currentSegment != null && 
        _currentSegment!.type == SegmentType.movement &&
        _currentSegment!.state != ActivityState.still) {
      final accepted = _trackBuilder.addPoint(location, _currentState);
      if (accepted) {
        // Сохраняем точку в БД
        _database.insertLocationPoint(
          location: location,
          segmentId: _currentSegment!.id,
          accepted: true,
        );
      }
    }
    
    // Передаем в stop detector
    _stopDetector.addLocationPoint(location);
    _stopDetector.onLocationUpdate(location);
  }
  
  void _handleStateChange(StateChangeEvent event) {
    _currentState = event.newState;
    
    // Воспроизводим звуковой сигнал при смене состояния
    SoundManager.instance.playStateChangeSound(event.newState);
    
    // Обновляем профиль GPS
    _profileManager.updateForState(_currentState);
    
    // Создаем событие изменения состояния с координатами (если доступны)
    final trackingEvent = TrackingEvent.stateChanged(
      oldState: event.oldState,
      newState: event.newState,
      confidence: event.confidence,
      timestamp: event.timestamp,
      latitude: _lastLocation?.latitude,
      longitude: _lastLocation?.longitude,
    );
    _eventQueue.enqueue(trackingEvent);
    
    // Обрабатываем переход с IN_VEHICLE на STILL или WALKING
    if (event.oldState == ActivityState.inVehicle &&
        (event.newState == ActivityState.still || event.newState == ActivityState.walking)) {
      _handleArrival(event.timestamp);
    }
    
    // Обрабатываем переходы состояний
    if (event.newState == ActivityState.still) {
      _handleStateChangedToStill(event.oldState, event.timestamp);
    } else {
      _handleStateChangedFromStill(event.newState, event.timestamp);
    }
    
    // Обновляем текущее состояние в БД
    _database.updateCurrentState(
      state: _currentState,
      lastLocationLat: _lastLocation?.latitude,
      lastLocationLon: _lastLocation?.longitude,
      confidence: event.confidence,
    );
  }
  
  /// Обработать прибытие (переход с IN_VEHICLE на STILL или WALKING)
  void _handleArrival(DateTime timestamp) {
    if (_lastLocation == null) {
      // ignore: avoid_print
      print('[TrackingService] Cannot send arrival message: location not available');
      return;
    }
    
    // Формируем сообщение с временем (ISO 8601) и координатами
    final currentTime = timestamp.toIso8601String();
    final locationCoords = '${_lastLocation!.latitude}, ${_lastLocation!.longitude}';
    final message = 'The current time is $currentTime, I have arrived at this geolocation $locationCoords.';
    
    // Отправляем сообщение в Realtime сессию (асинхронно, не блокируем трекинг)
    RealtimeSessionManager.instance.sendTextMessage(message).then((success) {
      if (success) {
        // ignore: avoid_print
        print('[TrackingService] Arrival message sent to Realtime session');
      } else {
        // ignore: avoid_print
        print('[TrackingService] Failed to send arrival message to Realtime session');
      }
    }).catchError((error) {
      // ignore: avoid_print
      print('[TrackingService] Error sending arrival message: $error');
    });
  }
  
  void _handleStateChangedToStill(ActivityState previousState, DateTime timestamp) {
    // Завершаем текущий сегмент движения, если есть
    if (_currentSegment != null && _currentSegment!.type == SegmentType.movement) {
      _finalizeCurrentSegment();
    }
    
    // Запускаем детекцию остановки
    _stopDetector.onStateChangedToStill(previousState, timestamp);
    _profileManager.startStopAcquisition();
    
    // Создаем событие начала остановки
    if (_lastLocation != null) {
      final event = TrackingEvent.stopStarted(
        anchorCandidate: _lastLocation!,
        timestamp: timestamp,
      );
      _eventQueue.enqueue(event);
    }
  }
  
  void _handleStateChangedFromStill(ActivityState newState, DateTime timestamp) {
    // Завершаем остановку, если активна
    if (_stopDetector.isStopActive) {
      _stopDetector.onStateChangedFromStill(newState, timestamp);
    }
    
    _profileManager.endStopAcquisition();
    
    // Создаем новый сегмент движения
    _startMovementSegment(newState, timestamp);
  }
  
  Future<void> _handleStopConfirmed(StopConfirmedEvent event) async {
    // Завершаем окно захвата
    _profileManager.endStopAcquisition();
    
    // Создаем сегмент остановки
    var stopSegment = Segment(
      type: SegmentType.stop,
      state: ActivityState.still,
      tStart: event.tStart,
      tConfirm: event.tConfirm,
      anchorLat: event.anchor.latitude,
      anchorLon: event.anchor.longitude,
      anchorAccuracy: event.anchor.accuracy,
      confidence: event.confidence,
    );
    
    final segmentId = await _database.insertSegment(stopSegment);
    stopSegment = stopSegment.copyWith(id: segmentId);
    _currentSegment = stopSegment;
    
    // Создаем событие подтверждения остановки
    final trackingEvent = TrackingEvent.stopConfirmed(
      stopId: event.stopId,
      anchor: event.anchor,
      tStart: event.tStart,
      confidence: event.confidence,
    );
    _eventQueue.enqueue(trackingEvent);
  }
  
  Future<void> _handleStopEnded(StopEndedEvent event) async {
    // Завершаем сегмент остановки
    if (_currentSegment != null && _currentSegment!.type == SegmentType.stop) {
      final updatedSegment = _currentSegment!.copyWith(tEnd: event.tEnd);
      await _database.updateSegment(updatedSegment);
      _currentSegment = null;
    }
    
    // Создаем событие завершения остановки
    final trackingEvent = TrackingEvent.stopEnded(
      stopId: event.stopId,
      tEnd: event.tEnd,
    );
    _eventQueue.enqueue(trackingEvent);
  }
  
  Future<void> _startMovementSegment(ActivityState state, DateTime timestamp) async {
    _trackBuilder.clear();
    
    final movementSegment = Segment(
      type: SegmentType.movement,
      state: state,
      tStart: timestamp,
    );
    
    final segmentId = await _database.insertSegment(movementSegment);
    _currentSegment = movementSegment.copyWith(id: segmentId);
  }
  
  Future<void> _finalizeCurrentSegment() async {
    if (_currentSegment == null) return;
    
    if (_currentSegment!.type == SegmentType.movement) {
      // Получаем упрощенный полилайн
      final polyline = _trackBuilder.finalize();
      
      // Обновляем сегмент с полилинией
      final updatedSegment = _currentSegment!.copyWith(
        tEnd: DateTime.now(),
        polyline: polyline,
      );
      await _database.updateSegment(updatedSegment);
    }
    
    _currentSegment = null;
  }
  
  void _startStatusUpdateTimer() {
    // Обновляем статус каждые 15 секунд при движении
    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isRunning && _lastLocation != null) {
        _sendStatusUpdate();
      }
    });
  }
  
  void _startHeartbeatTimer() {
    // Heartbeat каждые 60 секунд при стоянии
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_isRunning && _currentState == ActivityState.still) {
        _sendHeartbeat();
      }
    });
  }
  
  void _sendStatusUpdate() {
    if (_lastLocation == null) return;
    
    final event = TrackingEvent.locationFix(location: _lastLocation!);
    _eventQueue.enqueue(event);
  }
  
  void _sendHeartbeat() {
    // При стоянии отправляем anchor, если есть
    final anchor = _stopDetector.currentAnchor;
    if (anchor != null) {
      final event = TrackingEvent.locationFix(location: anchor);
      _eventQueue.enqueue(event);
    } else if (_lastLocation != null) {
      final event = TrackingEvent.locationFix(location: _lastLocation!);
      _eventQueue.enqueue(event);
    }
  }
  
  /// Получить текущее состояние
  ActivityState get currentState => _currentState;
  
  /// Получить последнюю локацию
  LocationFix? get lastLocation => _lastLocation;
  
  /// Проверяет, работает ли сервис
  bool get isRunning => _isRunning;
  
  void dispose() {
    stop();
    _activityProvider.dispose();
    _locationProvider.dispose();
    _stateMachine.dispose();
    _stopDetector.dispose();
    _batteryManager.dispose();
  }
}

