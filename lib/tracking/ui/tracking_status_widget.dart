import 'package:flutter/material.dart';
import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import '../models/activity_state.dart';
import '../models/location_fix.dart';
import '../../tracking/tracking_manager.dart';

/// Виджет для отображения текущего статуса трекинга
class TrackingStatusWidget extends StatefulWidget {
  const TrackingStatusWidget({super.key});
  
  @override
  State<TrackingStatusWidget> createState() => _TrackingStatusWidgetState();
}

class _TrackingStatusWidgetState extends State<TrackingStatusWidget> {
  Timer? _updateTimer;
  ActivityState? _currentState;
  LocationFix? _lastLocation;
  bool _isRunning = false;
  BatteryState _batteryState = BatteryState.unknown;
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _batterySubscription;
  
  @override
  void initState() {
    super.initState();
    _initBatteryMonitoring();
    _updateStatus();
    // Обновляем статус каждые 2 секунды
    _updateTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _updateStatus();
    });
  }
  
  Future<void> _initBatteryMonitoring() async {
    // Получаем начальное состояние
    _batteryState = await _battery.batteryState;
    setState(() {});
    
    // Подписываемся на изменения
    _batterySubscription = _battery.onBatteryStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _batteryState = state;
        });
      }
    });
  }
  
  void _updateStatus() {
    final manager = TrackingManager.instance;
    setState(() {
      _currentState = manager.currentState;
      _lastLocation = manager.lastLocation;
      _isRunning = manager.isRunning;
    });
  }
  
  @override
  void dispose() {
    _updateTimer?.cancel();
    _batterySubscription?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      _getStateIcon(_currentState),
                      color: _getStateColor(_currentState),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Tracking Status',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isRunning ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_currentState != null) ...[
                  Text(
                    'State: ${_currentState!.name}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ] else
                  Text(
                    'No state available',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                if (_lastLocation != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Location: ${_lastLocation!.latitude.toStringAsFixed(6)}, ${_lastLocation!.longitude.toStringAsFixed(6)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (_lastLocation!.accuracy != null)
                    Text(
                      'Accuracy: ${_lastLocation!.accuracy!.toStringAsFixed(1)} m',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'No location available',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Индикатор типа питания в правом нижнем углу
          Positioned(
            right: 8,
            bottom: 8,
            child: _buildPowerIndicator(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPowerIndicator() {
    IconData icon;
    Color color;
    
    switch (_batteryState) {
      case BatteryState.charging:
        icon = Icons.power;
        color = Colors.green;
        break;
      case BatteryState.full:
        icon = Icons.battery_charging_full;
        color = Colors.green;
        break;
      case BatteryState.discharging:
        icon = Icons.battery_std;
        color = Colors.orange;
        break;
      default:
        icon = Icons.battery_unknown;
        color = Colors.grey;
    }
    
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        icon,
        size: 16,
        color: color,
      ),
    );
  }
  
  IconData _getStateIcon(ActivityState? state) {
    switch (state) {
      case ActivityState.still:
        return Icons.pause_circle;
      case ActivityState.walking:
        return Icons.directions_walk;
      case ActivityState.inVehicle:
        return Icons.directions_car;
      default:
        return Icons.help_outline;
    }
  }
  
  Color _getStateColor(ActivityState? state) {
    switch (state) {
      case ActivityState.still:
        return Colors.orange;
      case ActivityState.walking:
        return Colors.blue;
      case ActivityState.inVehicle:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}

