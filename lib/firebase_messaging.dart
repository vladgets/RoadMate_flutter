import 'dart:convert';
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'services/geo_time_tools.dart';

// --------------------
// Family demo (FCM)
// --------------------
// Replace with your real signed-in user id (or derive it from your auth).
const String kRoadMateUserId = 'daughter2';

// Feature flag to disable all Firebase Messaging behavior temporarily.
const bool enableFcm = false;

Future<void> registerFcmTokenWithServer(String token, String serverUrl) async {
  try {
    await http.post(
      Uri.parse('$serverUrl/device/register_token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_id': kRoadMateUserId,
        'fcm_token': token,
      }),
    );
    debugPrint('[FCM] Token registered with server for user=$kRoadMateUserId');
  } catch (e) {
    debugPrint('[FCM] Failed to register token: $e');
  }
}

Future<void> respondToFamilyLocationPing(RemoteMessage message, String serverUrl) async {
  if (message.data['type'] != 'family_location_ping') return;

  final requestId = message.data['request_id']?.toString() ?? '';
  final toUserId = message.data['to_user_id']?.toString() ?? kRoadMateUserId;

  // Hardcoded demo location (replace later with getCurrentLocation())
  // final hardcodedLocation = {
  //   'lat': 37.3861,
  //   'lon': -122.0839,
  //   'label': 'Mountain View (hardcoded)',
  //   'accuracy_m': 999,
  //   'timestamp': DateTime.now().toIso8601String(),
  // };

  // final realLocation = await getCurrentLocation();
  final realLocation = await getBestEffortBackgroundLocation();

  final source = (realLocation.containsKey('source')) ? realLocation['source'] : 'unknown';
  realLocation.remove('source');

  try {
    await http.post(
      Uri.parse('$serverUrl/family/location_response'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'request_id': requestId,
        'to_user_id': toUserId,
        'location': realLocation,
        'source': source,
      }),
    );
    debugPrint('[FCM] Responded to family_location_ping (request_id=$requestId)');
  } catch (e) {
    debugPrint('[FCM] Failed to respond to ping: $e');
  }
}

/// Background handler MUST be top-level.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!enableFcm) return;

  debugPrint("[FCM] Background message received: ${message.data}");
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await respondToFamilyLocationPing(message, Config.serverUrl);
}


Future<void> initFcm() async {
  try {
    if (!enableFcm) {
      debugPrint('[FCM] initFcm skipped (disabled)');
      return;
    }

    // iOS requires permission; Android typically grants by default.
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
    }
    debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Ask iOS/APNs for its token first
      String? apns;
      for (int i = 0; i < 10; i++) {
        apns = await FirebaseMessaging.instance.getAPNSToken();
        if (apns != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      debugPrint('[FCM] APNs token: $apns');
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      debugPrint('[FCM] Token: $token');
      await registerFcmTokenWithServer(token, Config.serverUrl);
    } else {
      debugPrint('[FCM] Token is null');
    }

    // Token can rotate at any time (app reinstall, OS update, security refresh).
    // Re‑register automatically so server always has the latest token.
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      debugPrint('[FCM] Token refreshed: $newToken');
      await registerFcmTokenWithServer(newToken, Config.serverUrl);
    });

    // Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('[FCM] Foreground message: ${message.data}');
      await respondToFamilyLocationPing(message, Config.serverUrl);
    });

    // If user taps a notification to open the app (useful later)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('[FCM] Message opened app: ${message.data}');
    });
  } catch (e) {
    debugPrint('[FCM] init failed: $e');
  }
}