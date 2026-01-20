import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Сервис для поддержания аудио сессии активной в фоновом режиме на iOS.
/// 
/// iOS приостанавливает аудио когда приложение уходит в фон.
/// Этот сервис воспроизводит "тишину" чтобы держать аудио сессию активной,
/// что позволяет WebRTC аудио работать в фоне.
class BackgroundAudioService {
  static BackgroundAudioService? _instance;
  static BackgroundAudioService get instance {
    _instance ??= BackgroundAudioService._();
    return _instance!;
  }
  
  BackgroundAudioService._();
  
  static const _channel = MethodChannel('com.roadmate/audio');
  bool _isRunning = false;
  
  bool get isRunning => _isRunning;
  
  /// Запустить фоновое аудио для поддержания сессии активной.
  /// Вызывайте перед началом WebRTC соединения.
  Future<void> start() async {
    if (!Platform.isIOS) return;
    if (_isRunning) return;
    
    try {
      await _channel.invokeMethod('startBackgroundAudio');
      _isRunning = true;
      debugPrint('[BackgroundAudioService] Started');
    } catch (e) {
      debugPrint('[BackgroundAudioService] Failed to start: $e');
    }
  }
  
  /// Остановить фоновое аудио.
  /// Вызывайте после завершения WebRTC соединения.
  Future<void> stop() async {
    if (!Platform.isIOS) return;
    if (!_isRunning) return;
    
    try {
      await _channel.invokeMethod('stopBackgroundAudio');
      _isRunning = false;
      debugPrint('[BackgroundAudioService] Stopped');
    } catch (e) {
      debugPrint('[BackgroundAudioService] Failed to stop: $e');
    }
  }
}
