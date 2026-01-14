import 'dart:async';
import 'package:geolocator/geolocator.dart';
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
  
  // Параметры профилей
  static const double _activeMovementDistanceFilter = 30.0; // метры
  static const double _stopAcquisitionDistanceFilter = 5.0; // метры
  static const double _idleDistanceFilter = 50.0; // метры
  
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
    
    // Определяем настройки для текущего профиля
    _currentSettings = _getSettingsForProfile(_currentProfile);
    
    // Начинаем слушать обновления позиции
    // Используем allowBackgroundLocationUpdates для работы в фоне
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
    switch (profile) {
      case LocationProfile.activeMovement:
        return LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: _activeMovementDistanceFilter.toInt(),
          timeLimit: null,
        );
        
      case LocationProfile.stopAcquisition:
        return LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: _stopAcquisitionDistanceFilter.toInt(),
          timeLimit: null,
        );
        
      case LocationProfile.idle:
        return LocationSettings(
          accuracy: LocationAccuracy.low,
          distanceFilter: _idleDistanceFilter.toInt(),
          timeLimit: null,
        );
    }
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

