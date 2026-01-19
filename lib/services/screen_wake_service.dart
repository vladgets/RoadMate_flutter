import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:battery_plus/battery_plus.dart';

/// Сервис для управления состоянием экрана (wake lock)
/// Держит экран включенным когда приложение на переднем плане и телефон подключен к зарядке
class ScreenWakeService {
  static ScreenWakeService? _instance;
  static ScreenWakeService get instance {
    _instance ??= ScreenWakeService._();
    return _instance!;
  }

  ScreenWakeService._();

  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batterySubscription;
  bool _isAppInForeground = false;
  bool _isCharging = false;
  bool _isWakeLockEnabled = false;

  /// Инициализировать сервис
  Future<void> initialize() async {
    // Проверяем начальное состояние зарядки
    final batteryState = await _battery.batteryState;
    _isCharging = batteryState == BatteryState.charging || 
                  batteryState == BatteryState.full;
    
    // Подписываемся на изменения состояния батареи
    _batterySubscription = _battery.onBatteryStateChanged.listen((state) {
      final wasCharging = _isCharging;
      _isCharging = state == BatteryState.charging || state == BatteryState.full;
      
      if (wasCharging != _isCharging) {
        _updateWakeLock();
      }
    });

    // Обновляем состояние wake lock на основе текущих условий
    _updateWakeLock();
  }

  /// Уведомить о том, что приложение перешло на передний план
  void onAppResumed() {
    _isAppInForeground = true;
    _updateWakeLock();
  }

  /// Уведомить о том, что приложение ушло в фон
  void onAppPaused() {
    _isAppInForeground = false;
    _updateWakeLock();
  }

  /// Обновить состояние wake lock на основе текущих условий
  void _updateWakeLock() {
    final shouldEnable = _isAppInForeground && _isCharging;

    if (shouldEnable && !_isWakeLockEnabled) {
      _enableWakeLock();
    } else if (!shouldEnable && _isWakeLockEnabled) {
      _disableWakeLock();
    }
  }

  /// Включить wake lock
  Future<void> _enableWakeLock() async {
    try {
      await WakelockPlus.enable();
      _isWakeLockEnabled = true;
      debugPrint('[ScreenWakeService] Wake lock enabled (charging: $_isCharging, foreground: $_isAppInForeground)');
    } catch (e) {
      debugPrint('[ScreenWakeService] Error enabling wake lock: $e');
    }
  }

  /// Отключить wake lock
  Future<void> _disableWakeLock() async {
    try {
      await WakelockPlus.disable();
      _isWakeLockEnabled = false;
      debugPrint('[ScreenWakeService] Wake lock disabled');
    } catch (e) {
      debugPrint('[ScreenWakeService] Error disabling wake lock: $e');
    }
  }

  /// Освободить ресурсы
  void dispose() {
    _batterySubscription?.cancel();
    _batterySubscription = null;
    if (_isWakeLockEnabled) {
      _disableWakeLock();
    }
  }
}
