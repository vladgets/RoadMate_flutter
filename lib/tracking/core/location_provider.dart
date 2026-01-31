import 'dart:async';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import '../models/location_fix.dart';

/// Профили геолокации для разных режимов работы
enum LocationProfile {
  /// Профиль A: Active Movement - высокая частота обновлений при движении
  activeMovement,
  
  /// Профиль B: Stop Acquisition - короткое окно для точного определения остановки
  stopAcquisition,
  
  /// Профиль C: Idle/Standby - редкие обновления при стоянии
  idle,
}

/// Провайдер для получения геолокации с переключением профилей
class LocationProvider {
  StreamSubscription<Position>? _positionSubscription;
  final StreamController<LocationFix> _locationController = 
      StreamController<LocationFix>.broadcast();
  
  LocationProfile _currentProfile = LocationProfile.idle;
  LocationSettings? _currentSettings;
  bool _isRunning = false;
  
  // Параметры профилей - Distance Filter (метры)
  static const double _activeMovementDistanceFilter = 30.0;
  static const double _stopAcquisitionDistanceFilter = 5.0;
  static const double _idleDistanceFilter = 50.0;
  // iOS: меньший фильтр в idle для более частых пробуждений приложения в фоне
  // (нужно для доставки обновлений CMMotionActivityManager при смене состояния)
  static const double _idleDistanceFilterIos = 20.0;
  
  // Параметры профилей - Interval (секунды) для периодических обновлений в спящем режиме
  static const int _activeMovementIntervalSeconds = 5;
  static const int _stopAcquisitionIntervalSeconds = 3;
  static const int _idleIntervalSeconds = 60; // Даже в idle периодически пробуждаемся
  
  Stream<LocationFix> get locationStream => _locationController.stream;
  
  LocationProfile get currentProfile => _currentProfile;
  
  bool get isRunning => _isRunning;
  
  /// Переключить профиль геолокации
  Future<void> switchProfile(LocationProfile profile) async {
    if (_currentProfile == profile && _isRunning) return;
    
    _currentProfile = profile;
    
    if (_isRunning) {
      // Перезапускаем с новыми настройками
      await stop();
      await start();
    }
  }
  
  /// Начать получение геолокации
  Future<void> start() async {
    if (_isRunning) return;
    
    // Проверяем разрешения
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied');
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied forever');
    }
    
    // Для фоновой работы запрашиваем разрешение на фоновую локацию
    if (permission == LocationPermission.whileInUse) {
      // Пытаемся запросить разрешение на фоновую локацию
      try {
        permission = await Geolocator.requestPermission();
      } catch (e) {
        // ignore: avoid_print
        print('Background location permission request failed: $e');
      }
    }
    
    // Определяем настройки для текущего профиля (платформенно-специфичные)
    _currentSettings = _getSettingsForProfile(_currentProfile);
    
    // Начинаем слушать обновления позиции
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _currentSettings!,
    ).listen(
      _handlePositionUpdate,
      onError: (error) {
        // ignore: avoid_print
        print('Location stream error: $error');
      },
      cancelOnError: false,
    );
    
    _isRunning = true;
  }
  
  /// Остановить получение геолокации
  Future<void> stop() async {
    if (!_isRunning) return;
    
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _isRunning = false;
  }
  
  void _handlePositionUpdate(Position position) {
    final locationFix = LocationFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: position.heading,
      provider: 'GPS',
      timestamp: position.timestamp,
    );
    
    _locationController.add(locationFix);
  }
  
  LocationSettings _getSettingsForProfile(LocationProfile profile) {
    // Выбираем параметры в зависимости от профиля
    final double distanceFilter;
    final int intervalSeconds;
    final LocationAccuracy accuracy;
    
    switch (profile) {
      case LocationProfile.activeMovement:
        distanceFilter = _activeMovementDistanceFilter;
        intervalSeconds = _activeMovementIntervalSeconds;
        accuracy = LocationAccuracy.high;
        
      case LocationProfile.stopAcquisition:
        distanceFilter = _stopAcquisitionDistanceFilter;
        intervalSeconds = _stopAcquisitionIntervalSeconds;
        accuracy = LocationAccuracy.best;
        
      case LocationProfile.idle:
        distanceFilter = _idleDistanceFilter;
        intervalSeconds = _idleIntervalSeconds;
        accuracy = LocationAccuracy.low;
    }
    
    // Используем платформенно-специфичные настройки для корректной работы в фоне
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter.toInt(),
        // Критически важно для работы в спящем режиме:
        // intervalDuration гарантирует периодические обновления даже без движения
        intervalDuration: Duration(seconds: intervalSeconds),
        // Foreground service notification для поддержания сервиса активным
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'RoadMate Tracking',
          notificationText: 'Tracking your location in background',
          notificationChannelName: 'Location Tracking',
          enableWakeLock: true, // Wake lock предотвращает засыпание
        ),
      );
    } else if (!kIsWeb && Platform.isIOS) {
      // На iOS в idle используем меньший distanceFilter для более частых
      // обновлений в фоне — это пробуждает приложение и позволяет получать
      // обновления от CMMotionActivityManager (смена still/walking/inVehicle)
      final effectiveDistanceFilter = profile == LocationProfile.idle
          ? _idleDistanceFilterIos.toInt()
          : distanceFilter.toInt();
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: effectiveDistanceFilter,
        // Важные настройки для iOS background location:
        activityType: ActivityType.automotiveNavigation, // Оптимально для вождения
        pauseLocationUpdatesAutomatically: false, // НЕ приостанавливать автоматически
        showBackgroundLocationIndicator: true, // Синий индикатор в статус-баре
        allowBackgroundLocationUpdates: true, // Разрешить фоновые обновления
      );
    }
    
    // Fallback для других платформ
    return LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter.toInt(),
    );
  }
  
  /// Получить текущую позицию (одноразовый запрос)
  Future<LocationFix> getCurrentLocation() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
    
    return LocationFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: position.heading,
      provider: 'GPS',
      timestamp: position.timestamp,
    );
  }
  
  void dispose() {
    stop();
    _locationController.close();
  }
}

