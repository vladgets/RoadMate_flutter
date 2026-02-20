import 'package:flutter/material.dart';
import '../services/named_places_store.dart';
import '../services/geo_time_tools.dart';
import '../services/driving_log_store.dart';

class ActivitySettingsScreen extends StatefulWidget {
  const ActivitySettingsScreen({super.key});

  @override
  State<ActivitySettingsScreen> createState() => _ActivitySettingsScreenState();
}

class _ActivitySettingsScreenState extends State<ActivitySettingsScreen> {
  int _visitThresholdMinutes = 10;
  bool _poiLookupEnabled = true;
  List<NamedPlace> _namedPlaces = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await NamedPlacesStore.instance.init();
    final threshold = await NamedPlacesStore.instance.getVisitThresholdMinutes();
    final poiEnabled = await NamedPlacesStore.instance.getPoiLookupEnabled();
    setState(() {
      _visitThresholdMinutes = threshold;
      _poiLookupEnabled = poiEnabled;
      _namedPlaces = NamedPlacesStore.instance.all;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity Settings'),
      ),
      body: ListView(
        children: [
          // Visit threshold
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Visit Threshold'),
            subtitle: Text('$_visitThresholdMinutes minutes — stay this long to log a visit'),
            trailing: const Icon(Icons.edit),
            onTap: () async {
              final controller = TextEditingController(
                  text: _visitThresholdMinutes.toString());
              final result = await showDialog<String>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Visit Threshold (minutes)'),
                  content: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'e.g. 2 for testing, 10 for production',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, controller.text),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              );
              if (result != null) {
                final minutes = int.tryParse(result.trim());
                if (minutes != null && minutes >= 1) {
                  await NamedPlacesStore.instance.setVisitThresholdMinutes(minutes);
                  setState(() => _visitThresholdMinutes = minutes);
                }
              }
            },
          ),
          const Divider(),
          // POI lookup toggle
          SwitchListTile(
            secondary: const Icon(Icons.location_searching),
            title: const Text('POI Lookup'),
            subtitle: Text(_poiLookupEnabled
                ? 'Auto-detect place names (e.g. Starbucks, Whole Foods)'
                : 'Disabled — visits show address only'),
            value: _poiLookupEnabled,
            onChanged: (value) async {
              await NamedPlacesStore.instance.setPoiLookupEnabled(value);
              setState(() => _poiLookupEnabled = value);
            },
          ),
          if (_poiLookupEnabled)
            const Padding(
              padding: EdgeInsets.fromLTRB(72, 0, 16, 16),
              child: Text(
                'Uses OpenStreetMap to identify nearby points of interest. '
                'You can always edit the name by tapping it.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          const Divider(),
          // Migration button
          ListTile(
            leading: const Icon(Icons.update),
            title: const Text('Update Existing Events'),
            subtitle: const Text('Add addresses and POI names to old events'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _migrateExistingEvents,
          ),
          const Divider(),
          // Named Places section
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'NAMED PLACES',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Save frequently visited places (Home, Work, Gym) to skip POI lookup and improve accuracy.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_location),
            title: const Text('Add Place'),
            subtitle: const Text('Save current location as a named place'),
            onTap: _addNamedPlace,
          ),
          if (_namedPlaces.isNotEmpty) ...[
            const Divider(),
            for (final place in _namedPlaces)
              ListTile(
                leading: const Icon(Icons.location_on, size: 20),
                title: Text(place.label),
                subtitle: Text(
                  '${place.lat.toStringAsFixed(5)}, ${place.lon.toStringAsFixed(5)}\n'
                  'Radius: ${place.radiusM.toInt()}m',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _deleteNamedPlace(place.label),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _addNamedPlace() async {
    final messenger = ScaffoldMessenger.of(context);

    // Get current location
    final location = await getCurrentLocation();
    if (location['ok'] != true) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to get location: ${location['error'] ?? 'Unknown error'}')),
      );
      return;
    }

    final lat = (location['lat'] as num?)?.toDouble();
    final lon = (location['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('GPS coordinates not available')),
      );
      return;
    }

    // Show dialog to enter label
    if (!mounted) return;
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name This Place'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current location:\n${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'e.g., Home, Work, Gym',
                labelText: 'Label',
              ),
              autofocus: true,
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (label == null || label.trim().isEmpty || !mounted) return;

    await NamedPlacesStore.instance.save(label.trim(), lat, lon);
    await _loadSettings();
    messenger.showSnackBar(
      SnackBar(content: Text('Saved "${label.trim()}" at current location')),
    );
  }

  Future<void> _deleteNamedPlace(String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Named Place?'),
        content: Text('Remove "$label" from saved places?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    await NamedPlacesStore.instance.delete(label);
    await _loadSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted "$label"')),
    );
  }

  Future<void> _migrateExistingEvents() async {
    // Show confirmation dialog
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Existing Events?'),
        content: const Text(
          'This will update all existing events that have coordinates but no address or POI name.\n\n'
          'The process may take a few minutes depending on how many events you have. '
          'Each request waits 1 second to respect OpenStreetMap rate limits.\n\n'
          'Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(
              child: Text(
                'Updating events...\nThis may take a few minutes.',
              ),
            ),
          ],
        ),
      ),
    );

    // Run migration
    final result = await DrivingLogStore.instance.migrateExistingEvents();

    // Close progress dialog
    if (!mounted) return;
    Navigator.pop(context);

    // Show result
    final updated = result['updated'] as int;
    final total = result['total'] as int;
    final errors = result['errors'] as List<dynamic>;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Migration Complete'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Updated: $updated events'),
              Text('Total events: $total'),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Errors:',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                ),
                ...errors.map((e) => Text(
                      '• $e',
                      style: const TextStyle(fontSize: 12),
                    )),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    // Reload settings to show any new named places that might have been found
    await _loadSettings();
  }
}
