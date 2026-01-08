import '../models/activity_state.dart';
import 'location_provider.dart';
import 'battery_manager.dart';

/// Менеджер для переключения профилей GPS на основе состояния и батареи
class ProfileManager {
  final LocationProvider _locationProvider;
  final BatteryManager _batteryManager;
  
  ActivityState _currentState = ActivityState.still;
  bool _isStopAcquisitionActive = false;
  
  ProfileManager({
    required LocationProvider locationProvider,
    required BatteryManager batteryManager,
  })  : _locationProvider = locationProvider,
        _batteryManager = batteryManager {
    // Подписываемся на изменения режима батареи
    _batteryManager.modeStream.listen((_) => _updateProfile());
  }
  
  /// Обновить профиль на основе состояния
  void updateForState(ActivityState state) {
    if (_currentState == state) return;
    
    _currentState = state;
    _updateProfile();
  }
  
  /// Начать окно захвата остановки
  void startStopAcquisition() {
    _isStopAcquisitionActive = true;
    _updateProfile();
  }
  
  /// Завершить окно захвата остановки
  void endStopAcquisition() {
    _isStopAcquisitionActive = false;
    _updateProfile();
  }
  
  void _updateProfile() {
    LocationProfile targetProfile;
    
    // Если активно окно захвата остановки, используем профиль B
    if (_isStopAcquisitionActive) {
      targetProfile = LocationProfile.stopAcquisition;
    } else {
      // Выбираем профиль на основе состояния
      switch (_currentState) {
        case ActivityState.still:
          targetProfile = LocationProfile.idle;
          break;
        case ActivityState.walking:
        case ActivityState.inVehicle:
          // Проверяем режим батареи
          if (_batteryManager.currentMode == PowerMode.critical) {
            // В критическом режиме используем idle даже при движении
            targetProfile = LocationProfile.idle;
          } else if (_batteryManager.currentMode == PowerMode.powerSaving) {
            // В экономном режиме используем более редкие обновления
            targetProfile = LocationProfile.idle;
          } else {
            targetProfile = LocationProfile.activeMovement;
          }
          break;
      }
    }
    
    // Переключаем профиль, если он отличается от текущего
    if (_locationProvider.currentProfile != targetProfile) {
      _locationProvider.switchProfile(targetProfile);
    }
  }
  
  /// Получить текущий профиль
  LocationProfile get currentProfile => _locationProvider.currentProfile;
}

