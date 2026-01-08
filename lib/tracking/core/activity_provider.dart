import 'dart:async';
import '../models/activity_state.dart';

/// Провайдер для определения активности движения пользователя
/// Использует геолокацию и скорость для определения состояния
abstract class ActivityProvider {
  Stream<ActivityState> get activityStream;
  Future<void> start();
  Future<void> stop();
  void dispose();
  
  /// Обновить состояние на основе скорости (в м/с)
  void updateFromSpeed(double? speed);
}

/// Реализация ActivityProvider на основе скорости
class ActivityProviderImpl implements ActivityProvider {
  final StreamController<ActivityState> _activityController = 
      StreamController<ActivityState>.broadcast();
  
  ActivityState _currentState = ActivityState.still;
  bool _isRunning = false;
  
  // Пороги скорости для определения состояния (в м/с)
  static const double _walkingSpeedThreshold = 0.5; // ~1.8 км/ч
  static const double _vehicleSpeedThreshold = 2.0; // ~7.2 км/ч
  static const double _stillSpeedThreshold = 0.3; // ~1 км/ч
  
  @override
  Stream<ActivityState> get activityStream => _activityController.stream;
  
  @override
  Future<void> start() async {
    if (_isRunning) return;
    
    _isRunning = true;
    // Начальное состояние
    _activityController.add(ActivityState.still);
  }
  
  @override
  void updateFromSpeed(double? speed) {
    if (!_isRunning || speed == null) return;
    
    ActivityState? newState;
    
    if (speed < _stillSpeedThreshold) {
      newState = ActivityState.still;
    } else if (speed < _walkingSpeedThreshold) {
      // Transition zone between still and walking - treat as still
      newState = ActivityState.still;
    } else if (speed < _vehicleSpeedThreshold) {
      newState = ActivityState.walking;
    } else {
      newState = ActivityState.inVehicle;
    }
    
    if (newState != _currentState) {
      _currentState = newState;
      _activityController.add(newState);
    }
  }
  
  @override
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
  }
  
  @override
  void dispose() {
    stop();
    _activityController.close();
  }
}

/// Фабрика для создания ActivityProvider
class ActivityProviderFactory {
  static ActivityProvider create() {
    return ActivityProviderImpl();
  }
}

