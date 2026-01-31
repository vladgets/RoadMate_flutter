import 'dart:async';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../tracking_manager.dart';
import '../models/activity_state.dart';

/// Сервис для фонового трекинга
class BackgroundTrackingService {
  static BackgroundTrackingService? _instance;
  static BackgroundTrackingService get instance {
    _instance ??= BackgroundTrackingService._();
    return _instance!;
  }
  
  BackgroundTrackingService._();
  
  bool _isInitialized = false;
  final FlutterLocalNotificationsPlugin _notifications = 
      FlutterLocalNotificationsPlugin();
  
  /// Инициализировать фоновый сервис
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Инициализируем уведомления
    await _initializeNotifications();
    
    // Инициализируем фоновый сервис
    final service = FlutterBackgroundService();
    
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        autoStartOnBoot: true, // Автозапуск после перезагрузки
        notificationChannelId: 'roadmate_tracking',
        initialNotificationTitle: 'RoadMate Tracking',
        initialNotificationContent: 'Tracking your location',
        foregroundServiceNotificationId: 888,
        // Foreground service types для работы в Doze Mode
        // location - для геотрекинга
        // microphone - для голосового ассистента при прибытии
        foregroundServiceTypes: [
          AndroidForegroundType.location,
          AndroidForegroundType.microphone,
        ],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
    
    _isInitialized = true;
  }
  
  /// Инициализировать уведомления
  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {},
    );
  }
  
  /// Начать фоновый трекинг
  /// Примечание: TrackingService должен быть уже запущен через TrackingManager
  Future<void> start() async {
    // ignore: avoid_print
    print('[BackgroundTrackingService] start() called');
    
    if (!_isInitialized) {
      await initialize();
    }
    
    // Включаем wakelock чтобы экран не засыпал полностью
    // Это помогает поддерживать сервис активным на некоторых устройствах
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await WakelockPlus.enable();
        // ignore: avoid_print
        print('[BackgroundTrackingService] Wakelock enabled');
      }
    } catch (e) {
      // ignore: avoid_print
      print('[BackgroundTrackingService] Failed to enable wakelock: $e');
    }
    
    // Запускаем фоновый сервис
    final service = FlutterBackgroundService();
    await service.startService();
    // ignore: avoid_print
    print('[BackgroundTrackingService] Background service started');
    
    // Обновляем уведомление
    await _updateNotification('Tracking active', 'Monitoring location...');
  }
  
  /// Остановить фоновый трекинг
  /// Примечание: TrackingService должен быть остановлен через TrackingManager отдельно
  Future<void> stop() async {
    // ignore: avoid_print
    print('[BackgroundTrackingService] stop() called');
    
    // Отключаем wakelock
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await WakelockPlus.disable();
        // ignore: avoid_print
        print('[BackgroundTrackingService] Wakelock disabled');
      }
    } catch (e) {
      // ignore: avoid_print
      print('[BackgroundTrackingService] Failed to disable wakelock: $e');
    }
    
    // Останавливаем фоновый сервис
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (isRunning) {
      // ignore: avoid_print
      print('[BackgroundTrackingService] Sending stop command to background service');
      service.invoke('stop');
    } else {
      // ignore: avoid_print
      print('[BackgroundTrackingService] Background service was not running');
    }
    
    // Удаляем уведомление
    await _notifications.cancel(888);
  }
  
  /// Обновить уведомление
  Future<void> _updateNotification(String title, String content) async {
    final androidDetails = AndroidNotificationDetails(
      'roadmate_tracking',
      'Location Tracking',
      channelDescription: 'Background location tracking service',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
    );
    
    final notificationDetails = NotificationDetails(android: androidDetails);
    
    await _notifications.show(
      888,
      title,
      content,
      notificationDetails,
    );
  }
  
  /// Проверить, работает ли сервис
  Future<bool> isRunning() async {
    final service = FlutterBackgroundService();
    return await service.isRunning();
  }
  
  /// Запросить отключение оптимизации батареи (только Android)
  /// Это критически важно для работы в Doze Mode
  /// Возвращает true если разрешение получено или не требуется
  Future<bool> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return true;
    
    try {
      // Проверяем текущий статус
      final status = await Permission.ignoreBatteryOptimizations.status;
      
      if (status.isGranted) {
        return true;
      }
      
      // Запрашиваем разрешение
      final result = await Permission.ignoreBatteryOptimizations.request();
      return result.isGranted;
    } catch (e) {
      // ignore: avoid_print
      print('Failed to request battery optimization exemption: $e');
      return false;
    }
  }
  
  /// Проверить, отключена ли оптимизация батареи
  Future<bool> isBatteryOptimizationDisabled() async {
    if (!Platform.isAndroid) return true;
    
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      return status.isGranted;
    } catch (e) {
      return false;
    }
  }
}

/// Точка входа для фонового сервиса (Android)
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // ignore: avoid_print
  print('[BackgroundService] onStart called');
  
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }
  
  service.on('stop').listen((event) {
    // ignore: avoid_print
    print('[BackgroundService] Received stop command');
    service.stopSelf();
  });
  
  // Инициализируем TrackingManager в фоне (если еще не инициализирован)
  await TrackingManager.instance.initialize();
  
  // Запускаем трекинг если ещё не запущен
  // (может произойти если сервис перезапустился системой)
  if (!TrackingManager.instance.isRunning) {
    // ignore: avoid_print
    print('[BackgroundService] TrackingService not running, starting...');
    await TrackingManager.instance.service?.start();
  }
  
  // Периодически обновляем статус (каждые 60 секунд вместо 30)
  Timer.periodic(const Duration(seconds: 60), (timer) async {
    // ignore: avoid_print
    print('[BackgroundService] Heartbeat tick');
    
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        final trackingService = TrackingManager.instance.service;
        if (trackingService != null) {
          final state = trackingService.currentState;
          final location = trackingService.lastLocation;
          final isRunning = trackingService.isRunning;
          
          String status = 'State: ${state.name}';
          if (location != null) {
            status += '\nLat: ${location.latitude.toStringAsFixed(6)}, Lon: ${location.longitude.toStringAsFixed(6)}';
          }
          status += '\nRunning: $isRunning';
          
          service.setForegroundNotificationInfo(
            title: 'RoadMate Tracking',
            content: status,
          );
          
          // ignore: avoid_print
          print('[BackgroundService] Updated notification: $status');
        }
      }
    }
    
    // НЕ останавливаем сервис автоматически!
    // Остановка происходит только по явной команде 'stop'
    // Это исправляет проблему самопроизвольного отключения
  });
}

/// Точка входа для фонового сервиса (iOS)
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  // ignore: avoid_print
  print('[BackgroundService] iOS background entry point');
  
  await TrackingManager.instance.initialize();
  
  // Запускаем трекинг если ещё не запущен
  if (!TrackingManager.instance.isRunning) {
    // ignore: avoid_print
    print('[BackgroundService] iOS: TrackingService not running, starting...');
    await TrackingManager.instance.service?.start();
  }
  
  return true;
}
