import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// A video from the user's YouTube subscriptions feed.
class YouTubeSubscriptionVideo {
  final String videoId;
  final String title;
  final String url;
  final DateTime publishedAt;

  YouTubeSubscriptionVideo({
    required this.videoId,
    required this.title,
    required this.url,
    required this.publishedAt,
  });

  factory YouTubeSubscriptionVideo.fromJson(Map<String, dynamic> j) {
    final publishedAtStr = (j['publishedAt'] ?? '') as String;
    return YouTubeSubscriptionVideo(
      videoId: (j['videoId'] ?? '') as String,
      title: (j['title'] ?? '') as String,
      url: (j['url'] ?? '') as String,
      publishedAt: publishedAtStr.isNotEmpty ? DateTime.tryParse(publishedAtStr) ?? DateTime.now() : DateTime.now(),
    );
  }
}

/// Server-side YouTube proxy client.
/// Uses the Node service that holds OAuth tokens.
class YouTubeClient {
  final String baseUrl;
  final String? clientId;
  final Future<String?> Function()? getClientId;

  const YouTubeClient({
    required this.baseUrl,
    this.clientId,
    this.getClientId,
  });

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, String>> _headers() async {
    final h = <String, String>{
      'Content-Type': 'application/json',
    };
    final cid = clientId ?? (getClientId != null ? await getClientId!() : null);
    if (cid != null && cid.isNotEmpty) {
      h['X-Client-Id'] = cid;
    }
    return h;
  }

  /// Fetches videos from subscriptions feed (last 30 days).
  /// Throws on auth failure or server error.
  Future<List<YouTubeSubscriptionVideo>> getSubscriptionsFeed() async {
    final uri = _u('/youtube/subscriptions_feed');
    debugPrint('[YouTubeClient] getSubscriptionsFeed request: $uri');
    final r = await http.get(uri, headers: await _headers());
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    debugPrint('[YouTubeClient] getSubscriptionsFeed response (${r.statusCode}): ${r.body}');

    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('YouTube feed failed (${r.statusCode}): ${data['error'] ?? r.body}');
    }

    final list = (data['videos'] as List? ?? []).whereType<Map>().toList();
    return list.map((m) => YouTubeSubscriptionVideo.fromJson(m.cast<String, dynamic>())).toList();
  }
}
