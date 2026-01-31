import 'dart:async';
import 'package:flutter/foundation.dart';
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
  int _pendingStateCount = 0; // Счетчик подтверждений
  
  // Параметры стабилизации (ослаблены для лучшей детекции)
  static const Duration _stabilizationDuration = Duration(seconds: 15); // Уменьшено с 30
  static const double _highConfidenceThreshold = 0.55; // Уменьшено с 0.7
  static const int _requiredConfirmations = 3; // Количество подтверждений для смены состояния
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
    debugPrint('[StateMachine] Evaluating: current=$_currentState, new=$newState, confidence=$confidence');
    
    // Если состояние совпадает с текущим, сбрасываем ожидание
    if (newState == _currentState) {
      if (_pendingState != null) {
        debugPrint('[StateMachine] State confirmed as current, resetting pending');
      }
      _pendingState = null;
      _pendingStateStartTime = null;
      _pendingStateCount = 0;
      _stabilizationTimer?.cancel();
      _stabilizationTimer = null;
      return;
    }
    
    // Если состояние совпадает с ожидаемым, увеличиваем счетчик
    if (newState == _pendingState) {
      _pendingStateCount++;
      _pendingStateConfidence = (_pendingStateConfidence + confidence) / 2; // Усредняем
      
      debugPrint('[StateMachine] Pending state confirmed: count=$_pendingStateCount, avgConfidence=$_pendingStateConfidence');
      
      // Проверяем условия для смены состояния
      if (_pendingStateStartTime != null) {
        final elapsed = DateTime.now().difference(_pendingStateStartTime!);
        
        // Условия для подтверждения смены состояния:
        // 1. Прошло достаточно времени
        // 2. ИЛИ высокая уверенность
        // 3. ИЛИ достаточно подтверждений
        if (elapsed >= _stabilizationDuration || 
            confidence >= _highConfidenceThreshold ||
            _pendingStateCount >= _requiredConfirmations) {
          debugPrint('[StateMachine] Confirming state change: elapsed=${elapsed.inSeconds}s, count=$_pendingStateCount');
          _confirmStateChange(newState, _pendingStateConfidence);
        }
      }
      return;
    }
    
    // Новое состояние отличается от текущего И от ожидаемого
    debugPrint('[StateMachine] New pending state: $newState');
    _pendingState = newState;
    _pendingStateStartTime = DateTime.now();
    _pendingStateConfidence = confidence;
    _pendingStateCount = 1;
    
    // Если уверенность высокая, применяем сразу
    if (confidence >= _highConfidenceThreshold) {
      debugPrint('[StateMachine] High confidence, immediate state change');
      _confirmStateChange(newState, confidence);
      return;
    }
    
    // Иначе запускаем таймер стабилизации
    _stabilizationTimer?.cancel();
    _stabilizationTimer = Timer(_stabilizationDuration, () {
      if (_pendingState == newState && _pendingStateStartTime != null) {
        debugPrint('[StateMachine] Stabilization timer fired, confirming state');
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
    _pendingStateCount = 0;
    _stabilizationTimer?.cancel();
    _stabilizationTimer = null;
    
    debugPrint('[StateMachine] STATE CHANGED: $oldState -> $newState (confidence: $confidence)');
    
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

