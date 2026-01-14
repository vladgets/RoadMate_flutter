import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/activity_state.dart';

/// Менеджер для воспроизведения звуковых сигналов при смене состояния
class SoundManager {
  static SoundManager? _instance;
  static SoundManager get instance {
    _instance ??= SoundManager._();
    return _instance!;
  }
  
  SoundManager._();
  
  static const String _prefKeySoundEnabled = 'tracking_sound_enabled';
  bool _soundEnabled = true; // По умолчанию включен
  bool _isInitialized = false;
  
  /// Инициализировать менеджер звука
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    final prefs = await SharedPreferences.getInstance();
    _soundEnabled = prefs.getBool(_prefKeySoundEnabled) ?? true;
    _isInitialized = true;
  }
  
  /// Включен ли звук
  bool get isEnabled => _soundEnabled;
  
  /// Установить состояние звука
  Future<void> setEnabled(bool enabled) async {
    _soundEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeySoundEnabled, enabled);
  }
  
  /// Воспроизвести звук при смене состояния
  Future<void> playStateChangeSound(ActivityState newState) async {
    if (!_soundEnabled) return;
    
    try {
      // Используем разные системные звуки для разных состояний
      switch (newState) {
        case ActivityState.still:
          // Короткий низкий звук для остановки
          SystemSound.play(SystemSoundType.alert);
          break;
        case ActivityState.walking:
          // Средний звук для ходьбы
          SystemSound.play(SystemSoundType.click);
          break;
        case ActivityState.inVehicle:
          // Более заметный звук для движения в транспорте
          SystemSound.play(SystemSoundType.alert);
          // Небольшая задержка и второй звук для более заметного сигнала
          await Future.delayed(const Duration(milliseconds: 100));
          SystemSound.play(SystemSoundType.click);
          break;
      }
    } catch (e) {
      // Игнорируем ошибки воспроизведения звука
      // ignore: avoid_print
      print('Failed to play sound: $e');
    }
  }
}
