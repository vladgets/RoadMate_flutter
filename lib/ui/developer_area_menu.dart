import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'youtube_history_screen.dart';
import '../services/youtube.dart';


class DeveloperAreaScreen extends StatefulWidget {
  const DeveloperAreaScreen({super.key});

  @override
  State<DeveloperAreaScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<DeveloperAreaScreen> {

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
              await openYoutubeVideo("3hptKYix4X8", startSeconds: 0, autoplay: true);

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
