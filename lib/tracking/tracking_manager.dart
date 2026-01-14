import 'core/activity_provider.dart';
import 'core/location_provider.dart';
import 'core/state_machine.dart';
import 'core/stop_detector.dart';
import 'core/track_builder.dart';
import 'core/profile_manager.dart';
import 'core/battery_manager.dart';
import 'core/sound_manager.dart';
import 'background/background_tracking_service.dart';
import 'storage/tracking_database.dart';
import 'storage/event_queue.dart';
import 'service/tracking_service.dart';
import 'models/activity_state.dart';
import 'models/location_fix.dart';

/// Менеджер для управления сервисом трекинга
class TrackingManager {
  static TrackingManager? _instance;
  static TrackingManager get instance {
    _instance ??= TrackingManager._();
    return _instance!;
  }
  
  TrackingManager._();
  
  TrackingService? _service;
  TrackingDatabase? _database;
  bool _isInitialized = false;
  final BackgroundTrackingService _backgroundService = BackgroundTrackingService.instance;
  
  /// Инициализировать сервис трекинга
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Инициализируем SoundManager
      await SoundManager.instance.initialize();
      
      _database = TrackingDatabase();
      final database = _database!; // Гарантируем, что не null
      
      final activityProvider = ActivityProviderFactory.create();
      final locationProvider = LocationProvider();
      final stateMachine = StateMachine();
      final stopDetector = StopDetector();
      final trackBuilder = TrackBuilder();
      final batteryManager = BatteryManager();
      final profileManager = ProfileManager(
        locationProvider: locationProvider,
        batteryManager: batteryManager,
      );
      final eventQueue = EventQueue(database);
      
      _service = TrackingService(
        activityProvider: activityProvider,
        locationProvider: locationProvider,
        stateMachine: stateMachine,
        stopDetector: stopDetector,
        trackBuilder: trackBuilder,
        profileManager: profileManager,
        batteryManager: batteryManager,
        database: database,
        eventQueue: eventQueue,
      );
      
      _isInitialized = true;
    } catch (e) {
      // ignore: avoid_print
      print('Failed to initialize tracking service: $e');
    }
  }
  
  /// Начать трекинг (с фоновым сервисом)
  Future<void> start() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    // Запускаем обычный сервис
    await _service?.start();
    
    // Запускаем фоновый сервис для работы при заблокированном экране
    await _backgroundService.start();
  }
  
  /// Остановить трекинг
  Future<void> stop() async {
    // Останавливаем фоновый сервис сначала
    await _backgroundService.stop();
    
    // Останавливаем обычный сервис
    await _service?.stop();
  }
  
  /// Получить текущее состояние
  ActivityState? get currentState => _service?.currentState;
  
  /// Получить последнюю локацию
  LocationFix? get lastLocation => _service?.lastLocation;
  
  /// Проверяет, работает ли трекинг
  bool get isRunning => _service?.isRunning ?? false;
  
  /// Получить базу данных
  TrackingDatabase? get database => _database;
  
  /// Получить сервис
  TrackingService? get service => _service;
}

