import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../storage/tracking_database.dart';
import '../models/tracking_event.dart';
import '../models/activity_state.dart';

/// Экран истории трекинга (точки старта и переходы состояний)
class TrackingHistoryScreen extends StatefulWidget {
  final TrackingDatabase database;
  
  const TrackingHistoryScreen({
    super.key,
    required this.database,
  });
  
  @override
  State<TrackingHistoryScreen> createState() => _TrackingHistoryScreenState();
}

class _TrackingHistoryScreenState extends State<TrackingHistoryScreen> {
  bool _isLoading = false;
  List<TrackingEvent> _historyEvents = [];
  
  @override
  void initState() {
    super.initState();
    _loadHistory();
  }
  
  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final events = await widget.database.getHistoryEvents(limit: 100);
      setState(() {
        _historyEvents = events;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load history: $e')),
        );
      }
    }
  }
  
  Future<void> _deleteEvent(TrackingEvent event) async {
    if (event.id == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: const Text('Are you sure you want to delete this event?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        await widget.database.deleteEvent(event.id!);
        await _loadHistory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Event deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete event: $e')),
          );
        }
      }
    }
  }
  
  Future<void> _deleteAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete All History'),
        content: const Text('Are you sure you want to delete all tracking history? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      try {
        await widget.database.deleteHistoryEvents();
        await _loadHistory();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All history deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete history: $e')),
          );
        }
      }
    }
  }
  
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    // Если событие сегодня, показываем время
    if (difference.inDays == 0) {
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
    // Если вчера
    if (difference.inDays == 1) {
      return 'Yesterday ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
    // Если больше дня назад
    return '${dateTime.day}.${dateTime.month}.${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
  
  Widget _getStateIcon(ActivityState state) {
    switch (state) {
      case ActivityState.still:
        return const Icon(Icons.person, size: 24, color: Colors.grey);
      case ActivityState.walking:
        return const Icon(Icons.directions_walk, size: 24, color: Colors.blue);
      case ActivityState.inVehicle:
        return const Icon(Icons.directions_car, size: 24, color: Colors.green);
    }
  }
  
  Color _getStateColor(ActivityState state) {
    switch (state) {
      case ActivityState.still:
        return Colors.grey;
      case ActivityState.walking:
        return Colors.blue;
      case ActivityState.inVehicle:
        return Colors.green;
    }
  }
  
  Future<void> _openMap(double? latitude, double? longitude) async {
    if (latitude == null || longitude == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location not available')),
        );
      }
      return;
    }
    
    // Формируем URL для открытия карты
    final url = Uri.parse('https://www.google.com/maps?q=$latitude,$longitude');
    
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot open map')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open map: $e')),
        );
      }
    }
  }
  
  Widget _buildTrackingStartedEvent(TrackingEvent event) {
    final timestampStr = event.payload['timestamp'] as String?;
    final latitude = event.payload['latitude'] as double?;
    final longitude = event.payload['longitude'] as double?;
    
    if (timestampStr == null) {
      return const SizedBox.shrink();
    }
    
    final timestamp = DateTime.tryParse(timestampStr);
    if (timestamp == null) {
      return const SizedBox.shrink();
    }
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.play_arrow, size: 24, color: Colors.green),
        ),
        title: const Text(
          'Tracking Started',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(_formatDateTime(timestamp)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (latitude != null && longitude != null)
              IconButton(
                icon: const Icon(Icons.map),
                onPressed: () => _openMap(latitude, longitude),
                tooltip: 'Open in map',
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _deleteEvent(event),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStateChangedEvent(TrackingEvent event) {
    final oldStateStr = event.payload['old_state'] as String?;
    final newStateStr = event.payload['new_state'] as String?;
    final timestampStr = event.payload['timestamp'] as String?;
    
    if (oldStateStr == null || newStateStr == null || timestampStr == null) {
      return const SizedBox.shrink();
    }
    
    final oldState = ActivityStateExtension.fromString(oldStateStr);
    final newState = ActivityStateExtension.fromString(newStateStr);
    final timestamp = DateTime.tryParse(timestampStr);
    
    if (oldState == null || newState == null || timestamp == null) {
      return const SizedBox.shrink();
    }
    
    // Пытаемся получить координаты из payload (если они были сохранены)
    double? latitude;
    double? longitude;
    
    // Проверяем разные возможные форматы сохранения координат
    if (event.payload.containsKey('latitude')) {
      latitude = event.payload['latitude'] as double?;
    }
    if (event.payload.containsKey('longitude')) {
      longitude = event.payload['longitude'] as double?;
    }
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _getStateColor(oldState).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: _getStateIcon(oldState),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.arrow_forward, size: 16),
            ),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _getStateColor(newState).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: _getStateIcon(newState),
            ),
          ],
        ),
        title: Text(
          '${oldState.name} → ${newState.name}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(_formatDateTime(timestamp)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (latitude != null && longitude != null)
              IconButton(
                icon: const Icon(Icons.map),
                onPressed: () => _openMap(latitude, longitude),
                tooltip: 'Open in map',
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () => _deleteEvent(event),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tracking History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistory,
            tooltip: 'Refresh',
          ),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete All History'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'delete_all') {
                _deleteAllHistory();
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _historyEvents.isEmpty
              ? const Center(
                  child: Text(
                    'No history yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: ListView.builder(
                    itemCount: _historyEvents.length,
                    itemBuilder: (context, index) {
                      final event = _historyEvents[index];
                      
                      switch (event.type) {
                        case TrackingEventType.trackingStarted:
                          return _buildTrackingStartedEvent(event);
                        case TrackingEventType.stateChanged:
                          return _buildStateChangedEvent(event);
                        default:
                          return const SizedBox.shrink();
                      }
                    },
                  ),
                ),
    );
  }
}
