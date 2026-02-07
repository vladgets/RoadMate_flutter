import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'youtube_history_screen.dart';
import '../services/photo_index_service.dart';
import '../services/youtube_client.dart';


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
          Builder(
            builder: (context) {
              final stats = PhotoIndexService.instance.getStats();
              final indexed = stats['indexed'] as int;
              final total = stats['total'] as int;
              final subtitle = indexed == 0
                  ? 'Not indexed yet'
                  : '$indexed of $total photos indexed';
              return ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Photo Album Index'),
                subtitle: Text(subtitle),
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
