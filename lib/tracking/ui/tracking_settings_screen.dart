import 'package:flutter/material.dart';
import '../storage/tracking_database.dart';
import '../models/segment.dart';
import '../models/activity_state.dart';
import '../../tracking/tracking_manager.dart';

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
  bool _isTrackingEnabled = false;
  bool _isLoading = false;
  List<Segment> _recentSegments = [];
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadRecentSegments();
  }
  
  Future<void> _loadSettings() async {
    setState(() {
      _isTrackingEnabled = TrackingManager.instance.isRunning;
    });
  }
  
  Future<void> _loadRecentSegments() async {
    setState(() => _isLoading = true);
    try {
      final segments = await widget.database.getSegments(limit: 20);
      setState(() {
        _recentSegments = segments;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      // ignore: avoid_print
      print('Failed to load segments: $e');
    }
  }
  
  Future<void> _toggleTracking() async {
    setState(() => _isTrackingEnabled = !_isTrackingEnabled);
    
    try {
      if (_isTrackingEnabled) {
        await TrackingManager.instance.start();
      } else {
        await TrackingManager.instance.stop();
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
  
  Future<void> _deleteAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete History'),
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
        await widget.database.deleteAllData();
        await _loadRecentSegments();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('History deleted')),
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
  
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
  
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
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
          
          const Divider(),
          
          // История сегментов
          ListTile(
            title: const Text('Recent Segments'),
            subtitle: _isLoading
                ? const Text('Loading...')
                : Text('${_recentSegments.length} segments'),
          ),
          
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_recentSegments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'No segments yet',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            )
          else
            ..._recentSegments.map((segment) => ListTile(
              title: Text(segment.state.name),
              subtitle: Text(
                '${_formatDateTime(segment.tStart)} • ${segment.durationSeconds != null ? _formatDuration(Duration(seconds: segment.durationSeconds!.toInt())) : "Active"}',
              ),
              trailing: segment.type == SegmentType.stop
                  ? const Icon(Icons.location_on, size: 20)
                  : const Icon(Icons.directions_walk, size: 20),
            )),
          
          const Divider(),
          
          // Удаление истории
          ListTile(
            title: const Text('Delete All History'),
            subtitle: const Text('Permanently delete all tracking data'),
            trailing: const Icon(Icons.delete_outline, color: Colors.red),
            onTap: _deleteAllHistory,
          ),
        ],
      ),
    );
  }
}

