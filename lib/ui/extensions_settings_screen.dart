import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/calendar_store.dart';

class ExtensionsSettingsScreen extends StatefulWidget {
  const ExtensionsSettingsScreen({super.key});

  @override
  State<ExtensionsSettingsScreen> createState() => _ExtensionsSettingsScreenState();
}

class _ExtensionsSettingsScreenState extends State<ExtensionsSettingsScreen> {
  bool _calendarEnabled = false;
  bool _calendarPermissionGranted = false;
  bool _loading = false;

  static const String _prefKeyCalendarEnabled = 'calendar_extension_enabled';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _calendarEnabled = prefs.getBool(_prefKeyCalendarEnabled) ?? false;
    });
    await _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final hasPermission = await CalendarStore.hasPermissions();
    setState(() {
      _calendarPermissionGranted = hasPermission;
    });
  }

  Future<void> _toggleCalendar(bool value) async {
    if (_loading) return;

    setState(() {
      _loading = true;
    });

    try {
      if (value) {
        // Request permissions when enabling
        final granted = await CalendarStore.requestPermissions();
        setState(() {
          _calendarPermissionGranted = granted;
          _calendarEnabled = granted; // Only enable if permission granted
        });

        if (!granted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Calendar permission is required to enable this feature'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        setState(() {
          _calendarEnabled = false;
        });
      }

      // Save state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyCalendarEnabled, _calendarEnabled);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Extensions'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Calendar'),
            subtitle: Text(
              _calendarPermissionGranted
                  ? 'Access to calendar data enabled'
                  : 'Calendar permission not granted',
            ),
            trailing: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Switch(
                    value: _calendarEnabled,
                    onChanged: _toggleCalendar,
                  ),
          ),
          if (!_calendarPermissionGranted && _calendarEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Please grant calendar permission in system settings to use this feature.',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

