import 'package:flutter/material.dart';
import '../config.dart';
import 'memory_settings_screen.dart';
import 'extensions_settings_screen.dart';
import 'reminders_screen.dart';
import 'voice_memories_screen.dart';
import 'developer_area_menu.dart';
import 'onboarding_screen.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

  @override
  void dispose() {
    super.dispose();
  }

  String _voiceLabel(String v) {
    if (v == Config.femaleVoice) return 'Female (marin)';
    if (v == Config.maleVoice) return 'Male (echo)';
    return v;
    }

  Future<void> _pickVoice() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text('Voice'),
          children: [
            RadioGroup<String>(
              groupValue: Config.voice,
              onChanged: (val) => Navigator.of(context).pop(val),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final v in Config.supportedVoices)
                    RadioListTile<String>(
                      value: v,
                      title: Text(_voiceLabel(v)),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (selected == null || selected == Config.voice) return;

    await Config.setVoice(selected);
    if (!mounted) return;
    setState(() {});

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Voice saved. It will apply on the next connection.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // ✅ NEW: Voice picker
          ListTile(
            leading: const Icon(Icons.record_voice_over),
            title: const Text('Voice'),
            subtitle: Text(_voiceLabel(Config.voice)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickVoice,
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Tutorial'),
            subtitle: const Text('View getting started guide'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              );
            },
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.extension),
            title: const Text('Extensions'),
            subtitle: const Text('Manage calendar and other extensions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExtensionsSettingsScreen()),
              );
            },
          ),
          const Divider(),

          // existing items unchanged
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Preferences'),
            subtitle: const Text('Edit user preferences (prompt)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PreferencesSettingsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.psychology_alt_outlined),
            title: const Text('Long-term Memory'),
            subtitle: const Text('View and manage stored memory'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MemorySettingsScreen()),
              );
            },
          ),
          // Reminders (view upcoming reminders)
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Reminders'),
            subtitle: const Text('View upcoming reminders'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RemindersScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories),
            title: const Text('Voice Notes'),
            subtitle: const Text('Browse saved voice notes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const VoiceMemoriesScreen()),
              );
            },
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.developer_mode),
            title: const Text('Developer'),
            subtitle: const Text('Debug tools and experimental features'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeveloperAreaScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}


