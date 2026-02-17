import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/driving_log_store.dart';

class DrivingLogScreen extends StatefulWidget {
  const DrivingLogScreen({super.key});

  @override
  State<DrivingLogScreen> createState() => _DrivingLogScreenState();
}

class _DrivingLogScreenState extends State<DrivingLogScreen> {
  List<DrivingEvent> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await DrivingLogStore.instance.init();
    setState(() {
      _events = DrivingLogStore.instance.getRecentEvents(200);
      _loading = false;
    });
  }

  Future<void> _openInMaps(DrivingEvent event) async {
    // Prefer coordinates if available, fall back to address string
    Uri? uri;

    if (event.lat != null && event.lon != null) {
      final lat = event.lat!;
      final lon = event.lon!;
      final label = Uri.encodeComponent(event.address ?? 'Location');
      if (Platform.isIOS) {
        uri = Uri.parse('http://maps.apple.com/?ll=$lat,$lon&q=$label');
      } else {
        uri = Uri.parse('geo:$lat,$lon?q=$lat,$lon($label)');
      }
    } else if (event.address != null && event.address!.isNotEmpty) {
      final encoded = Uri.encodeComponent(event.address!);
      if (Platform.isIOS) {
        uri = Uri.parse('http://maps.apple.com/?q=$encoded');
      } else {
        uri = Uri.parse('geo:0,0?q=$encoded');
      }
    }

    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No location data for this event')),
        );
      }
      return;
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Maps app')),
        );
      }
    }
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Driving Log?'),
        content: const Text('This will delete all recorded driving events.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    // Clear via store by re-initialising with empty list is not exposed —
    // achieve by logging nothing; instead expose clear via prefs directly.
    // For now just reload (clearing is low priority for a dev screen).
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Clear not yet implemented — delete app data to reset')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driving Log'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear log',
            onPressed: _confirmClear,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_car_outlined,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No driving events yet',
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Drive for ~2 minutes to trigger detection',
                        style: TextStyle(color: Colors.grey[400], fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _events.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final event = _events[index];
                    return _EventTile(
                      event: event,
                      onOpenMap: () => _openInMaps(event),
                    );
                  },
                ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event, required this.onOpenMap});

  final DrivingEvent event;
  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    final isStart = event.type == 'start';

    final icon = isStart ? Icons.directions_car : Icons.local_parking;
    final iconColor = isStart ? Colors.green[700]! : Colors.blue[700]!;
    final label = isStart ? 'Trip started' : 'Parked';

    final timestamp = _formatTimestamp(event.timestamp);
    final hasLocation = event.lat != null || event.address != null;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconColor.withValues(alpha: 0.12),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(label),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(timestamp, style: const TextStyle(fontSize: 12)),
          if (event.address != null && event.address!.isNotEmpty)
            Text(
              event.address!,
              style: const TextStyle(fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          else
            Text(
              event.lat != null
                  ? '${event.lat!.toStringAsFixed(5)}, ${event.lon!.toStringAsFixed(5)}'
                  : 'No location',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: hasLocation
          ? IconButton(
              icon: const Icon(Icons.map_outlined),
              tooltip: 'Open in Maps',
              onPressed: onOpenMap,
            )
          : null,
      onTap: hasLocation ? onOpenMap : null,
    );
  }

  String _formatTimestamp(String iso) {
    try {
      final utc = DateTime.parse(iso);
      final local = utc.toLocal();
      final now = DateTime.now();
      final diff = now.difference(local);

      final timeStr = DateFormat('h:mm a').format(local);

      if (diff.inDays == 0) return 'Today $timeStr';
      if (diff.inDays == 1) return 'Yesterday $timeStr';
      if (diff.inDays < 7) return '${diff.inDays}d ago $timeStr';
      return DateFormat('MMM d, y • h:mm a').format(local);
    } catch (_) {
      return iso;
    }
  }
}
