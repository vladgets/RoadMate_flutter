import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_activity_recognition/flutter_activity_recognition.dart';
import '../models/activity_state.dart';

/// Провайдер для определения активности движения пользователя
/// Использует нативное распознавание (CMMotionActivityManager на iOS, ActivityRecognition на Android)
/// и скорость GPS как fallback
abstract class ActivityProvider {
  Stream<ActivityState> get activityStream;
  Future<void> start();
  Future<void> stop();
  void dispose();

  /// Обновить состояние на основе скорости (в м/с) — fallback при отсутствии нативных данных
  void updateFromSpeed(double? speed);
}

/// Гибридный провайдер: нативное распознавание активности на iOS/Android + fallback по скорости GPS
/// Критично для iOS в фоне: CMMotionActivityManager доставляет обновления при пробуждении приложения
/// (например, при получении обновления геолокации), в отличие от GPS-скорости, которая требует
/// частых обновлений локации.
class ActivityProviderHybrid implements ActivityProvider {
  final StreamController<ActivityState> _activityController =
      StreamController<ActivityState>.broadcast();

  ActivityState _currentState = ActivityState.still;
  bool _isRunning = false;
  StreamSubscription<Activity>? _nativeSubscription;

  // Пороги скорости для fallback (в м/с)
  static const double _walkingSpeedThreshold = 0.5; // ~1.8 км/ч
  static const double _vehicleSpeedThreshold = 2.0; // ~7.2 км/ч
  static const double _stillSpeedThreshold = 0.3; // ~1 км/ч

  /// Используется ли нативное распознавание (true на iOS/Android при успешной инициализации)
  bool _nativeAvailable = false;

  @override
  Stream<ActivityState> get activityStream => _activityController.stream;

  @override
  Future<void> start() async {
    if (_isRunning) return;

    _isRunning = true;

    // Пробуем запустить нативное распознавание на iOS и Android
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      try {
        final instance = FlutterActivityRecognition.instance;
        var permission = await instance.checkPermission();

        if (permission == PermissionRequestResult.DENIED) {
          permission = await instance.requestPermission();
          if (permission != PermissionRequestResult.GRANTED) {
            debugPrint(
                '[ActivityProvider] Native permission denied: $permission');
          }
        }

        if (permission == PermissionRequestResult.GRANTED) {
          _nativeSubscription = instance.activityStream.listen(
              _onNativeActivity,
              onError: (e) {
                debugPrint('[ActivityProvider] Native stream error: $e');
                _nativeAvailable = false;
              },
              cancelOnError: false,
            );
          _nativeAvailable = true;
          debugPrint(
              '[ActivityProvider] Native activity recognition started (iOS/Android)');
        } else {
          debugPrint(
              '[ActivityProvider] Native permission not granted: $permission');
        }
      } catch (e) {
        debugPrint('[ActivityProvider] Failed to start native recognition: $e');
        _nativeAvailable = false;
      }
    }

    if (!_nativeAvailable) {
      debugPrint(
          '[ActivityProvider] Using speed-based fallback (no native recognition)');
    }

    // Начальное состояние
    _activityController.add(ActivityState.still);
  }

  void _onNativeActivity(Activity activity) {
    if (!_isRunning) return;

    final state = _mapNativeToActivityState(activity.type);
    if (state == null) return;

    final confidence = _activityConfidenceToDouble(activity.confidence);
    if (confidence < 0.3) return; // Игнорируем низкую уверенность

    if (state != _currentState) {
      _currentState = state;
      debugPrint(
          '[ActivityProvider] Native update: ${activity.type.name} -> ${state.name} (conf: $confidence)');
      _activityController.add(state);
    }
  }

  ActivityState? _mapNativeToActivityState(ActivityType type) {
    switch (type) {
      case ActivityType.STILL:
        return ActivityState.still;
      case ActivityType.WALKING:
      case ActivityType.RUNNING:
        return ActivityState.walking;
      case ActivityType.IN_VEHICLE:
      case ActivityType.ON_BICYCLE:
        return ActivityState.inVehicle;
      case ActivityType.UNKNOWN:
        return null;
    }
  }

  double _activityConfidenceToDouble(ActivityConfidence confidence) {
    switch (confidence) {
      case ActivityConfidence.HIGH:
        return 0.85;
      case ActivityConfidence.MEDIUM:
        return 0.6;
      case ActivityConfidence.LOW:
        return 0.4;
    }
  }

  @override
  void updateFromSpeed(double? speed) {
    if (!_isRunning || speed == null) return;

    // Если нативное распознавание активно, скорость — только дополнительная валидация
    // для IN_VEHICLE при высокой скорости (GPS надёжнее при движении)
    if (_nativeAvailable) {
      // При скорости > 5 м/с (~18 км/ч) почти наверняка в транспорте
      if (speed > 5.0 && _currentState != ActivityState.inVehicle) {
        _currentState = ActivityState.inVehicle;
        _activityController.add(ActivityState.inVehicle);
      }
      return;
    }

    // Fallback: определяем только по скорости
    ActivityState? newState;

    if (speed < _stillSpeedThreshold) {
      newState = ActivityState.still;
    } else if (speed < _walkingSpeedThreshold) {
      newState = ActivityState.still; // Зона перехода
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
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
    _nativeAvailable = false;
  }

  @override
  void dispose() {
    stop();
    _activityController.close();
  }
}

/// Реализация только на основе скорости GPS (для платформ без нативного API)
class ActivityProviderImpl implements ActivityProvider {
  final StreamController<ActivityState> _activityController =
      StreamController<ActivityState>.broadcast();

  ActivityState _currentState = ActivityState.still;
  bool _isRunning = false;

  static const double _walkingSpeedThreshold = 0.5;
  static const double _vehicleSpeedThreshold = 2.0;
  static const double _stillSpeedThreshold = 0.3;

  @override
  Stream<ActivityState> get activityStream => _activityController.stream;

  @override
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    _activityController.add(ActivityState.still);
  }

  @override
  void updateFromSpeed(double? speed) {
    if (!_isRunning || speed == null) return;

    ActivityState? newState;

    if (speed < _stillSpeedThreshold) {
      newState = ActivityState.still;
    } else if (speed < _walkingSpeedThreshold) {
      newState = ActivityState.still; // Зона перехода
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

/// Фабрика: гибридный провайдер на iOS/Android, fallback на других платформах
class ActivityProviderFactory {
  static ActivityProvider create() {
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      return ActivityProviderHybrid();
    }
    return ActivityProviderImpl();
  }
}
