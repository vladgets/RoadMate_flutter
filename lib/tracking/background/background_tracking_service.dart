import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
        notificationChannelId: 'roadmate_tracking',
        initialNotificationTitle: 'RoadMate Tracking',
        initialNotificationContent: 'Tracking your location',
        foregroundServiceNotificationId: 888,
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
    if (!_isInitialized) {
      await initialize();
    }
    
    // Запускаем фоновый сервис
    final service = FlutterBackgroundService();
    await service.startService();
    
    // Обновляем уведомление
    await _updateNotification('Tracking active', 'Monitoring location...');
  }
  
  /// Остановить фоновый трекинг
  /// Примечание: TrackingService должен быть остановлен через TrackingManager отдельно
  Future<void> stop() async {
    // Останавливаем фоновый сервис
    final service = FlutterBackgroundService();
    final isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke('stop');
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
}

/// Точка входа для фонового сервиса (Android)
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }
  
  service.on('stop').listen((event) {
    service.stopSelf();
  });
  
  // Инициализируем TrackingManager в фоне (если еще не инициализирован)
  await TrackingManager.instance.initialize();
  
  // НЕ запускаем TrackingService здесь, так как он уже должен быть запущен
  // через TrackingManager.start() перед вызовом BackgroundTrackingService.start()
  // Это предотвращает дублирование событий trackingStarted
  
  // Периодически обновляем статус
  Timer.periodic(const Duration(seconds: 30), (timer) async {
    if (service is AndroidServiceInstance) {
      if (await service.isForegroundService()) {
        final trackingService = TrackingManager.instance.service;
        if (trackingService != null && trackingService.isRunning) {
          final state = trackingService.currentState;
          final location = trackingService.lastLocation;
          
          String status = 'State: ${state.name}';
          if (location != null) {
            status += '\nLat: ${location.latitude.toStringAsFixed(6)}, Lon: ${location.longitude.toStringAsFixed(6)}';
          }
          
          service.setForegroundNotificationInfo(
            title: 'RoadMate Tracking',
            content: status,
          );
        }
      }
    }
    
    // Проверяем, нужно ли остановить сервис
    final isTrackingRunning = TrackingManager.instance.isRunning;
    if (!isTrackingRunning) {
      timer.cancel();
      service.stopSelf();
    }
  });
}

/// Точка входа для фонового сервиса (iOS)
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  await TrackingManager.instance.initialize();
  
  // НЕ запускаем TrackingService здесь, так как он уже должен быть запущен
  // через TrackingManager.start() перед вызовом BackgroundTrackingService.start()
  // Это предотвращает дублирование событий trackingStarted
  
  return true;
}
