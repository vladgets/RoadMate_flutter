import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:activity_recognition_flutter/activity_recognition_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'driving_log_store.dart';
import 'geo_time_tools.dart';

/// Monitors device activity to detect driving start/stop events.
/// Subscribes to the activity recognition stream and maintains a simple
/// debounced state machine: STILL → driving=false, IN_VEHICLE → driving=true.
class DrivingMonitorService {
  DrivingMonitorService._();
  static final DrivingMonitorService instance = DrivingMonitorService._();

  static const int _debounceCount = 2;
  static const int _minConfidence = 60;

  static const int _notifIdStart = 9001;
  static const int _notifIdPark = 9002;
  static const String _channelId = 'roadmate_driving_monitor';
  static const String _channelName = 'Driving Monitor';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _notifInitialized = false;

  static const _bridge = MethodChannel('roadmate/driving_bridge');
  static const _uuid = Uuid();

  final StreamController<ActivityEvent> _rawEventController =
      StreamController<ActivityEvent>.broadcast();

  /// Raw activity events from the sensor — every event, before any filtering.
  /// Subscribe in the Developer Area to confirm the sensor pipeline is alive.
  Stream<ActivityEvent> get rawEvents => _rawEventController.stream;

  StreamSubscription<ActivityEvent>? _subscription;
  bool _isDriving = false;
  int _vehicleReadings = 0;

  // Throttle: only call setFlutterAlive once per 60 s to avoid MethodChannel spam.
  DateTime? _lastAlivePing;

  /// Start monitoring. On Android requests ACTIVITY_RECOGNITION permission.
  Future<void> start() async {
    if (_subscription != null) return; // already running

    await _initNotifications();

    // Tell the native receiver Flutter is alive (suppresses native duplicates).
    await _pingAlive();

    // Drain any events the native receiver queued while the app was dead.
    if (Platform.isAndroid) {
      await _drainNativePendingEvents();
    }

    // Request permission on Android 10+ (API 29+)
    if (Platform.isAndroid) {
      final status = await Permission.activityRecognition.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        debugPrint('[DrivingMonitor] Activity recognition permission denied — monitoring disabled');
        return;
      }
    }

    try {
      final stream = ActivityRecognition().activityStream(
        runForegroundService: false,
      );
      _subscription = stream.listen(_onActivity, onError: (e) {
        debugPrint('[DrivingMonitor] Stream error: $e');
      });
      debugPrint('[DrivingMonitor] Started');
    } catch (e) {
      debugPrint('[DrivingMonitor] Failed to start: $e');
    }
  }

  /// Stop monitoring and reset state.
  /// Simulate a trip start — for testing in the office without driving.
  /// Bypasses the sensor pipeline and directly fires the driving-started logic.
  Future<void> simulateTripStart() async {
    await _initNotifications();
    _isDriving = true;
    _vehicleReadings = _debounceCount;
    _onDrivingStarted();
  }

  /// Simulate a park — for testing in the office without driving.
  Future<void> simulateParked() async {
    await _initNotifications();
    _isDriving = false;
    _vehicleReadings = 0;
    _onParked();
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _isDriving = false;
    _vehicleReadings = 0;
    debugPrint('[DrivingMonitor] Stopped');
  }

  void _onActivity(ActivityEvent event) {
    final type = event.type;
    final confidence = event.confidence;

    debugPrint('[DrivingMonitor] Activity: $type confidence=$confidence isDriving=$_isDriving');

    _rawEventController.add(event); // forward to diagnostic stream before filtering
    unawaited(_pingAlive()); // keep native receiver suppressed while Dart is running

    if (confidence < _minConfidence) return;

    switch (type) {
      case ActivityType.inVehicle:
        _vehicleReadings++;
        if (_vehicleReadings >= _debounceCount && !_isDriving) {
          _isDriving = true;
          _onDrivingStarted();
        }
        break;

      case ActivityType.still:
      case ActivityType.onFoot:
      case ActivityType.walking:
        _vehicleReadings = 0;
        if (_isDriving) {
          _isDriving = false;
          _onParked();
        }
        break;

      // running, onBicycle, unknown, tilting, invalid — no state change
      default:
        break;
    }
  }

  /// Tell the native DrivingDetectionReceiver that Flutter is alive.
  /// Throttled to once per 60 s — called on start and on every activity event.
  Future<void> _pingAlive() async {
    if (!Platform.isAndroid) return;
    final now = DateTime.now();
    if (_lastAlivePing != null && now.difference(_lastAlivePing!).inSeconds < 60) return;
    _lastAlivePing = now;
    try {
      await _bridge.invokeMethod('setFlutterAlive');
    } catch (_) {}
  }

  /// Read events queued by the native receiver while the app was dead,
  /// insert them into DrivingLogStore, then clear the native queue.
  Future<void> _drainNativePendingEvents() async {
    try {
      final json = await _bridge.invokeMethod<String>('getPendingEvents');
      if (json == null || json == '[]') return;
      final list = jsonDecode(json) as List<dynamic>;
      for (final raw in list) {
        if (raw is! Map) continue;
        final type = raw['type'] as String? ?? 'start';
        final tsMs = raw['ts'] as int? ?? DateTime.now().millisecondsSinceEpoch;
        final event = DrivingEvent(
          id: _uuid.v4(),
          type: type,
          timestamp: DateTime.fromMillisecondsSinceEpoch(tsMs).toUtc().toIso8601String(),
        );
        await DrivingLogStore.instance.insertEvent(event);
        debugPrint('[DrivingMonitor] Drained native event: $type at ${event.timestamp}');
      }
    } catch (e) {
      debugPrint('[DrivingMonitor] Failed to drain native events: $e');
    }
  }

  void _onDrivingStarted() {
    debugPrint('[DrivingMonitor] Driving started');
    _captureAndLog('start', 'Trip started', 'Detecting your drive…');
  }

  void _onParked() {
    debugPrint('[DrivingMonitor] Parked');
    _captureAndLog('park', 'You parked', 'Logging your parking spot…');
  }

  Future<void> _captureAndLog(
      String type, String notifTitle, String notifBodyFallback) async {
    try {
      final location = await getBestEffortBackgroundLocation();

      // Log to store
      final event = await DrivingLogStore.instance.logEvent(type, location);

      // Build notification body
      final timeStr = DateFormat('h:mm a').format(DateTime.now());
      String body;
      if (event.address != null && event.address!.isNotEmpty) {
        final verb = type == 'start' ? 'Trip started at' : 'Parked at';
        body = '$verb ${event.address} • $timeStr';
      } else {
        body = '${type == 'start' ? 'Trip started' : 'Parked'} • $timeStr';
      }

      await _showNotification(
        id: type == 'start' ? _notifIdStart : _notifIdPark,
        title: notifTitle,
        body: body,
      );
    } catch (e) {
      debugPrint('[DrivingMonitor] Error in _captureAndLog: $e');
    }
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Automatic drive start/stop detection',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        autoCancel: true,
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentSound: false,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(id, title, body, details);
      debugPrint('[DrivingMonitor] Notification shown: $title — $body');
    } catch (e) {
      debugPrint('[DrivingMonitor] Failed to show notification: $e');
    }
  }

  Future<void> _initNotifications() async {
    if (_notifInitialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _notifications.initialize(initSettings);

    // Create Android notification channel
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Automatic drive start/stop detection',
      importance: Importance.defaultImportance,
    );

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
    }

    _notifInitialized = true;
    debugPrint('[DrivingMonitor] Notifications initialized');
  }
}
