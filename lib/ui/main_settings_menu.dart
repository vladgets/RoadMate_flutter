import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:just_audio/just_audio.dart';
import '../config.dart';
import 'memory_settings_screen.dart';
import 'extensions_settings_screen.dart';
import 'reminders_screen.dart';
import 'youtube_history_screen.dart';
// import '../services/reminders.dart';


class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AudioPlayer _testAudioPlayer = AudioPlayer();

  @override
  void dispose() {
    _testAudioPlayer.dispose();
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
              // Reminders
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RemindersScreen()),
              );
            },
          ),
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
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('Test New Stuff'),
            subtitle: const Text('Testing area for new features'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () async {
              // сawait testWhatsApp();
              // await openSpotifyUrl('https://open.spotify.com/episode/2pCc9DRjOeZFn8UVY9X6p7');
              // await openSpotifySearchDeep('Inworld podcast');
              // await RemindersService.instance.scheduleReminderInOneMinute('This is a test reminder from RoadMate app');
              // final text = await getYoutubeTranscriptText("https://www.youtube.com/watch?v=3hptKYix4X8");

              // final url = "https://www.youtube.com/watch?v=3hptKYix4X8";
              const testUrl = "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3";

              await _testAudioPlayer.setUrl(testUrl);
              await _testAudioPlayer.play();

              // final uri = await playYoutubeAudioFull(
              //   _testAudioPlayer,
              //   url,
              //   preferLowBandwidth: true,
              // );

              // if (!mounted) return;

              // if (uri == null) {
              //   messenger.showSnackBar(
              //     const SnackBar(
              //       content: Text('Could not start audio (no stream / blocked / no connection).'),
              //       duration: Duration(seconds: 2),
              //     ),
              //   );
              //   return;
              // }

              // messenger.showSnackBar(
              // const SnackBar(
              //   content: Text('Playing YouTube audio-only stream…'),
              //   duration: Duration(seconds: 2),
              // ),
              //);

              // navigator.maybePop();
            },
          ),
        ],
      ),
    );
  }
}


// For testing of functions

/// Opens WhatsApp with a prefilled message.
/// Note: WhatsApp generally requires the user to tap Send.
Future<void> testWhatsApp() async {
  const text = 'RoadMate app is great!';
  const phone = '14084552967';

  // Option A: Native WhatsApp scheme (best on Android if WhatsApp is installed)
  final native = Uri.parse('whatsapp://send?phone=$phone&text=${Uri.encodeComponent(text)}');

  // Option B: Universal web link fallback (works even if native scheme fails)
  // You can also target a specific phone number with: https://wa.me/<number>?text=...
  final web = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(text)}');

  try {
    if (await canLaunchUrl(native)) {
      final ok = await launchUrl(native, mode: LaunchMode.externalApplication);
      if (ok) return;
    }
  } catch (_) {
    // ignore and fall back
  }

  // Fallback
  final ok = await launchUrl(web, mode: LaunchMode.externalApplication);
  if (!ok) {
    throw Exception('Could not launch WhatsApp. Is it installed and available on this device?');
  }
}

Future<void> openSpotifyUrl(String url) async {
  final uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw Exception('Could not open $url');
  }
}

Future<void> openSpotifySearchDeep(String query) async {
  final encoded = Uri.encodeComponent(query);
  final uri = Uri.parse('spotify:search:$encoded');

  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
