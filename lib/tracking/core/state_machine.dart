import 'dart:async';
import '../models/activity_state.dart';
import '../models/location_fix.dart';

/// Событие изменения состояния
class StateChangeEvent {
  final ActivityState oldState;
  final ActivityState newState;
  final double confidence;
  final DateTime timestamp;
  
  StateChangeEvent({
    required this.oldState,
    required this.newState,
    required this.confidence,
    required this.timestamp,
  });
}

/// Машина состояний для стабилизации состояний движения
class StateMachine {
  final StreamController<StateChangeEvent> _stateChangeController = 
      StreamController<StateChangeEvent>.broadcast();
  
  ActivityState _currentState = ActivityState.still;
  ActivityState? _pendingState;
  DateTime? _pendingStateStartTime;
  double _pendingStateConfidence = 0.0;
  
  // Параметры стабилизации
  static const Duration _stabilizationDuration = Duration(seconds: 30);
  static const double _highConfidenceThreshold = 0.7;
  static const double _lowSpeedThreshold = 1.0; // м/с
  static const double _highSpeedThreshold = 4.0; // м/с
  
  Timer? _stabilizationTimer;
  
  Stream<StateChangeEvent> get stateChangeStream => _stateChangeController.stream;
  ActivityState get currentState => _currentState;
  
  /// Обработать обновление активности
  void processActivityUpdate(ActivityState activityState, double confidence) {
    _evaluateState(activityState, confidence, null);
  }
  
  /// Обработать обновление локации
  void processLocationUpdate(LocationFix location) {
    // Используем скорость для дополнительной валидации
    final speed = location.speed ?? 0.0;
    
    // Если скорость высокая, вероятно движение
    if (speed > _highSpeedThreshold) {
      _evaluateState(ActivityState.inVehicle, 0.6, location);
    } else if (speed < _lowSpeedThreshold) {
      // Низкая скорость - возможно стояние
      _evaluateState(ActivityState.still, 0.5, location);
    }
  }
  
  /// Обработать комбинированное обновление (активность + локация)
  void processCombinedUpdate({
    required ActivityState activityState,
    required double activityConfidence,
    LocationFix? location,
  }) {
    _evaluateState(activityState, activityConfidence, location);
  }
  
  void _evaluateState(
    ActivityState newState,
    double confidence,
    LocationFix? location,
  ) {
    // Если состояние совпадает с текущим, сбрасываем таймер
    if (newState == _currentState) {
      _pendingState = null;
      _pendingStateStartTime = null;
      _stabilizationTimer?.cancel();
      _stabilizationTimer = null;
      return;
    }
    
    // Если состояние совпадает с ожидаемым, продолжаем ждать
    if (newState == _pendingState) {
      // Проверяем, прошло ли достаточно времени
      if (_pendingStateStartTime != null) {
        final elapsed = DateTime.now().difference(_pendingStateStartTime!);
        
        // Если прошло достаточно времени ИЛИ высокая уверенность
        if (elapsed >= _stabilizationDuration || confidence >= _highConfidenceThreshold) {
          _confirmStateChange(newState, confidence);
        }
      }
      return;
    }
    
    // Новое состояние отличается - начинаем отсчет стабилизации
    _pendingState = newState;
    _pendingStateStartTime = DateTime.now();
    _pendingStateConfidence = confidence;
    
    // Если уверенность высокая, применяем сразу
    if (confidence >= _highConfidenceThreshold) {
      _confirmStateChange(newState, confidence);
      return;
    }
    
    // Иначе запускаем таймер стабилизации
    _stabilizationTimer?.cancel();
    _stabilizationTimer = Timer(_stabilizationDuration, () {
      if (_pendingState == newState && _pendingStateStartTime != null) {
        _confirmStateChange(newState, _pendingStateConfidence);
      }
    });
  }
  
  void _confirmStateChange(ActivityState newState, double confidence) {
    final oldState = _currentState;
    _currentState = newState;
    _pendingState = null;
    _pendingStateStartTime = null;
    _pendingStateConfidence = 0.0;
    _stabilizationTimer?.cancel();
    _stabilizationTimer = null;
    
    // Отправляем событие изменения состояния
    final event = StateChangeEvent(
      oldState: oldState,
      newState: newState,
      confidence: confidence,
      timestamp: DateTime.now(),
    );
    
    _stateChangeController.add(event);
  }
  
  /// Принудительно установить состояние (для тестирования или сброса)
  void forceState(ActivityState state) {
    if (state != _currentState) {
      final oldState = _currentState;
      _currentState = state;
      _pendingState = null;
      _pendingStateStartTime = null;
      _stabilizationTimer?.cancel();
      _stabilizationTimer = null;
      
      final event = StateChangeEvent(
        oldState: oldState,
        newState: state,
        confidence: 1.0,
        timestamp: DateTime.now(),
      );
      
      _stateChangeController.add(event);
    }
  }
  
  void dispose() {
    _stabilizationTimer?.cancel();
    _stateChangeController.close();
  }
}

