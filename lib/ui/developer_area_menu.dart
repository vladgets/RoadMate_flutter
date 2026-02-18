import 'package:flutter/material.dart';
import 'youtube_history_screen.dart';
import 'driving_log_screen.dart';
import '../services/photo_index_service.dart';
import '../services/driving_monitor_service.dart';
import '../config.dart';


class DeveloperAreaScreen extends StatefulWidget {
  const DeveloperAreaScreen({super.key});

  @override
  State<DeveloperAreaScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<DeveloperAreaScreen> {
  bool _greetingEnabled = false;
  String _greetingPhrase = "Hello, how can I help you?";

  @override
  void initState() {
    super.initState();
    _loadGreetingSettings();
  }

  Future<void> _loadGreetingSettings() async {
    final enabled = await Config.getInitialGreetingEnabled();
    final phrase = await Config.getInitialGreetingPhrase();
    setState(() {
      _greetingEnabled = enabled;
      _greetingPhrase = phrase;
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Developer Area'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.directions_car_outlined),
            title: const Text('Driving Log'),
            subtitle: const Text('Trip start/stop events with location'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DrivingLogScreen()),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Simulate Trip Start'),
                    onPressed: () async {
                      await DrivingMonitorService.instance.simulateTripStart();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Trip start simulated — check notification & log')),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.stop),
                    label: const Text('Simulate Parked'),
                    onPressed: () async {
                      await DrivingMonitorService.instance.simulateParked();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Parked simulated — check notification & log')),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.video_library),
            title: const Text('YouTube history'),
            subtitle: const Text('Videos from subscriptions (last month)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const YouTubeHistoryScreen()),
              );
            },
          ),
          const Divider(),
          Builder(
            builder: (context) {
              final stats = PhotoIndexService.instance.getStats();
              final indexed = stats['indexed'] as int;
              final total = stats['total'] as int;
              final withTimestamps = stats['withTimestamps'] as int;
              final withLocation = stats['withLocation'] as int;

              final subtitle = indexed == 0
                  ? 'Not indexed yet'
                  : '$indexed indexed ($withTimestamps with timestamps, $withLocation with location)';
              return ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Photo Album Index'),
                subtitle: Text(subtitle),
                onTap: () {
                  // Show detailed stats dialog
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Photo Index Details'),
                      content: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Total photos in album: $total'),
                            Text('Photos indexed: $indexed'),
                            Text('Photos with timestamps: $withTimestamps'),
                            Text('Photos with location: $withLocation'),
                            const SizedBox(height: 16),
                            if (stats['oldestPhoto'] != null)
                              Text('Oldest photo: ${_formatDate(stats['oldestPhoto'] as String)}'),
                            if (stats['newestPhoto'] != null)
                              Text('Newest photo: ${_formatDate(stats['newestPhoto'] as String)}'),
                            if (stats['last_indexed'] != null)
                              Text('\nLast indexed: ${_formatDate(stats['last_indexed'] as String)}'),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Rebuild Index',
                  onPressed: () async {
                    // Show confirmation dialog
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Rebuild Photo Index?'),
                        content: const Text(
                          'This will rebuild the entire photo index. '
                          'Only camera photos will be included. '
                          'This may take a few minutes.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Rebuild'),
                          ),
                        ],
                      ),
                    );

                    if (confirm != true) return;

                    // Show progress dialog
                    if (!context.mounted) return;
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const AlertDialog(
                        content: Row(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(width: 20),
                            Text('Rebuilding index...'),
                          ],
                        ),
                      ),
                    );

                    // Rebuild index
                    final result = await PhotoIndexService.instance.buildIndex(forceRebuild: true);

                    // Close progress dialog
                    if (!context.mounted) return;
                    Navigator.pop(context);

                    // Show result
                    if (!context.mounted) return;
                    final message = result['ok'] == true
                        ? 'Index rebuilt successfully!\n${result['indexed']} photos indexed'
                        : 'Failed to rebuild index: ${result['error']}';

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(message)),
                    );

                    // Refresh UI
                    setState(() {});
                  },
                ),
              );
            },
          ),
          const Divider(),
          // Initial greeting settings
          SwitchListTile(
            secondary: const Icon(Icons.waving_hand),
            title: const Text('Initial Greeting'),
            subtitle: Text(_greetingEnabled ? 'Assistant greets you on connect' : 'Disabled'),
            value: _greetingEnabled,
            onChanged: (bool value) async {
              setState(() => _greetingEnabled = value);
              await Config.setInitialGreetingEnabled(value);
            },
          ),
          if (_greetingEnabled)
            ListTile(
              leading: const SizedBox(width: 24), // Indent to align with switch
              title: const Text('Greeting Phrase'),
              subtitle: Text(_greetingPhrase),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final controller = TextEditingController(text: _greetingPhrase);
                final result = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Edit Greeting Phrase'),
                    content: TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        hintText: 'Enter greeting phrase',
                      ),
                      maxLines: 2,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, controller.text),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );

                if (result != null && result.isNotEmpty) {
                  setState(() => _greetingPhrase = result);
                  await Config.setInitialGreetingPhrase(result);
                }
              },
            ),
        ],
      ),
    );
  }

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) {
        return 'Today ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      } else if (diff.inDays == 1) {
        return 'Yesterday ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      } else if (diff.inDays < 7) {
        return '${diff.inDays} days ago';
      } else {
        return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return isoString;
    }
  }
}
