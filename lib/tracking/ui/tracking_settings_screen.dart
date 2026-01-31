import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../storage/tracking_database.dart';
import '../core/sound_manager.dart';
import '../../tracking/tracking_manager.dart';
import '../background/background_tracking_service.dart';
import '../../services/realtime_session_manager.dart';
import '../../services/realtime_connection_service.dart';
import '../../services/callkit_service.dart';
import 'tracking_history_screen.dart';

/// Экран настроек трекинга
class TrackingSettingsScreen extends StatefulWidget {
  final TrackingDatabase database;
  final VoidCallback? onTrackingToggled;
  
  const TrackingSettingsScreen({
    super.key,
    required this.database,
    this.onTrackingToggled,
  });
  
  @override
  State<TrackingSettingsScreen> createState() => _TrackingSettingsScreenState();
}

class _TrackingSettingsScreenState extends State<TrackingSettingsScreen> {
  bool _isTrackingEnabled = true; // По умолчанию включён
  bool _isSoundEnabled = true;
  bool _isBatteryOptimizationDisabled = true;
  bool _isRealtimeConnected = false;
  
  // Delayed test state
  Timer? _delayedTestTimer;
  int _delayCountdown = 0;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkBatteryOptimization();
    _checkRealtimeConnection();
  }
  
  @override
  void dispose() {
    _delayedTestTimer?.cancel();
    super.dispose();
  }
  
  Future<void> _loadSettings() async {
    // Инициализируем SoundManager если еще не инициализирован
    await SoundManager.instance.initialize();
    
    setState(() {
      _isTrackingEnabled = TrackingManager.instance.isRunning;
      _isSoundEnabled = SoundManager.instance.isEnabled;
    });
  }
  
  void _checkRealtimeConnection() {
    if (mounted) {
      setState(() {
        _isRealtimeConnected = RealtimeConnectionService.instance.isConnected;
      });
    }
  }
  
  Future<void> _checkBatteryOptimization() async {
    if (!Platform.isAndroid) return;
    
    final isDisabled = await BackgroundTrackingService.instance
        .isBatteryOptimizationDisabled();
    if (mounted) {
      setState(() {
        _isBatteryOptimizationDisabled = isDisabled;
      });
    }
  }
  
  Future<void> _requestBatteryOptimizationExemption() async {
    final granted = await BackgroundTrackingService.instance
        .requestBatteryOptimizationExemption();
    
    await _checkBatteryOptimization();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(granted
              ? 'Battery optimization disabled - tracking will work in background'
              : 'Battery optimization not disabled - tracking may stop in sleep mode'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  /// DEBUG: Симулировать прибытие для тестирования автоподключения Realtime
  Future<void> _simulateArrival() async {
    // Получаем текущую локацию (или используем фейковую)
    final trackingService = TrackingManager.instance.service;
    final location = trackingService?.lastLocation;
    
    final currentTime = DateTime.now().toIso8601String();
    final locationCoords = location != null 
        ? '${location.latitude}, ${location.longitude}'
        : '37.7749, -122.4194'; // San Francisco как fallback
    
    final message = 'The current time is $currentTime, I have arrived at this geolocation $locationCoords.';
    
    // ignore: avoid_print
    print('[DEBUG] Simulating arrival with message: $message');
    
    // На iOS используем CallKit (показывает экран входящего звонка)
    if (Platform.isIOS) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Showing incoming call...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      await CallKitService.instance.showIncomingCall(
        message: message,
        locationName: 'Test Location',
      );
      
      // ignore: avoid_print
      print('[DEBUG] CallKit incoming call displayed');
    } else {
      // На Android отправляем напрямую
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Simulating arrival... Connecting to Realtime...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      
      final success = await RealtimeSessionManager.instance.sendTextMessage(message);
      
      _checkRealtimeConnection();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success 
                ? 'Arrival message sent successfully!' 
                : 'Failed to send arrival message'),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  /// DEBUG: Отключить тестовую Realtime сессию
  Future<void> _disconnectRealtime() async {
    await RealtimeConnectionService.instance.disconnect();
    _checkRealtimeConnection();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Realtime session disconnected'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
  
  /// DEBUG: Симулировать прибытие с задержкой 10 секунд
  void _simulateArrivalDelayed() {
    if (_delayedTestTimer != null) {
      // Отменить если уже запущен
      _delayedTestTimer?.cancel();
      _delayedTestTimer = null;
      setState(() => _delayCountdown = 0);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Delayed test cancelled'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }
    
    // Запускаем обратный отсчёт
    setState(() => _delayCountdown = 10);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Test will run in 10 seconds. Lock your phone now!'),
          duration: Duration(seconds: 3),
        ),
      );
    }
    
    _delayedTestTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_delayCountdown <= 1) {
        timer.cancel();
        _delayedTestTimer = null;
        setState(() => _delayCountdown = 0);
        
        // Запускаем тест
        // ignore: avoid_print
        print('[DEBUG] Delayed test triggered!');
        _simulateArrival();
      } else {
        setState(() => _delayCountdown--);
      }
    });
  }
  
  Future<void> _toggleSound() async {
    final newValue = !_isSoundEnabled;
    setState(() {
      _isSoundEnabled = newValue;
    });
    
    await SoundManager.instance.setEnabled(newValue);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newValue 
              ? 'Sound notifications enabled' 
              : 'Sound notifications disabled'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }
  
  Future<void> _toggleTracking() async {
    setState(() => _isTrackingEnabled = !_isTrackingEnabled);
    
    try {
      if (_isTrackingEnabled) {
        await TrackingManager.instance.start();
        await TrackingManager.instance.setEnabledByDefault(true);
      } else {
        await TrackingManager.instance.stop();
        await TrackingManager.instance.setEnabledByDefault(false);
      }
      widget.onTrackingToggled?.call();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isTrackingEnabled 
                ? 'Tracking started' 
                : 'Tracking stopped'),
          ),
        );
      }
    } catch (e) {
      setState(() => _isTrackingEnabled = !_isTrackingEnabled);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${_isTrackingEnabled ? 'stop' : 'start'} tracking: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracking Settings'),
      ),
      body: ListView(
        children: [
          // Переключатель трекинга
          SwitchListTile(
            title: const Text('Enable Tracking'),
            subtitle: const Text('Track your movement and detect stops'),
            value: _isTrackingEnabled,
            onChanged: (_) => _toggleTracking(),
          ),
          
          // Переключатель звуковых сигналов
          SwitchListTile(
            title: const Text('Sound Notifications'),
            subtitle: const Text('Play sound when state changes (STILL/WALKING/IN_VEHICLE)'),
            value: _isSoundEnabled,
            onChanged: (_) => _toggleSound(),
          ),
          
          // Отключение оптимизации батареи (только Android)
          if (Platform.isAndroid) ...[
            ListTile(
              title: const Text('Battery Optimization'),
              subtitle: Text(
                _isBatteryOptimizationDisabled
                    ? 'Disabled - tracking works in background'
                    : 'Enabled - tracking may stop in sleep mode',
              ),
              trailing: _isBatteryOptimizationDisabled
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : TextButton(
                      onPressed: _requestBatteryOptimizationExemption,
                      child: const Text('DISABLE'),
                    ),
            ),
          ],
          
          const Divider(),
          
          // История трекинга
          ListTile(
            title: const Text('Tracking History'),
            subtitle: const Text('View tracking start points and state transitions'),
            trailing: const Icon(Icons.history),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => TrackingHistoryScreen(
                    database: widget.database,
                  ),
                ),
              );
            },
          ),
          
          const Divider(),
          
          // DEBUG секция
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'DEBUG',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          
          // DEBUG: Симуляция прибытия (немедленно)
          ListTile(
            title: const Text('Simulate Arrival'),
            subtitle: Text(_isRealtimeConnected 
                ? 'Realtime session is connected' 
                : 'Test Realtime session auto-connect'),
            leading: Icon(
              _isRealtimeConnected ? Icons.wifi : Icons.wifi_off,
              color: _isRealtimeConnected ? Colors.green : Colors.grey,
            ),
            trailing: const Icon(Icons.play_arrow, color: Colors.orange),
            onTap: () => _simulateArrival(),
          ),
          
          // DEBUG: Симуляция прибытия с задержкой
          ListTile(
            title: Text(_delayCountdown > 0 
                ? 'Cancel Delayed Test ($_delayCountdown s)' 
                : 'Simulate in 10 seconds'),
            subtitle: Text(_delayCountdown > 0 
                ? 'Tap to cancel' 
                : 'Lock your phone after tapping'),
            leading: Icon(
              _delayCountdown > 0 ? Icons.timer : Icons.timer_outlined,
              color: _delayCountdown > 0 ? Colors.red : Colors.orange,
            ),
            trailing: _delayCountdown > 0 
                ? Text(
                    '$_delayCountdown',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  )
                : const Icon(Icons.schedule, color: Colors.orange),
            onTap: () => _simulateArrivalDelayed(),
          ),
          
          // DEBUG: Отключить Realtime сессию
          if (_isRealtimeConnected)
            ListTile(
              title: const Text('Disconnect Realtime'),
              subtitle: const Text('Stop the test session'),
              leading: const Icon(Icons.stop, color: Colors.red),
              trailing: const Icon(Icons.close, color: Colors.red),
              onTap: () => _disconnectRealtime(),
            ),
        ],
      ),
    );
  }
}

