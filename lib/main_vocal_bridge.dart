import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'vocal_bridge_page.dart';

/// Entry point for VocalBridge-powered version of RoadMate.
/// Run with: flutter run -t lib/main_vocal_bridge.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const VocalBridgeApp());
}

class VocalBridgeApp extends StatelessWidget {
  const VocalBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RoadMate (VocalBridge)',
      theme: ThemeData.dark(),
      home: const VocalBridgePage(),
    );
  }
}
