import 'dart:convert';
import 'package:http/http.dart' as http;

/// A compact “email card” suitable for voice UX.
class GmailEmailCard {
  final String id;
  final String threadId;
  final String subject;
  final String from;
  final String date;
  final String snippet;

  GmailEmailCard({
    required this.id,
    required this.threadId,
    required this.subject,
    required this.from,
    required this.date,
    required this.snippet,
  });

  factory GmailEmailCard.fromJson(Map<String, dynamic> j) {
    return GmailEmailCard(
      id: (j['id'] ?? '') as String,
      threadId: (j['threadId'] ?? '') as String,
      subject: (j['subject'] ?? '') as String,
      from: (j['from'] ?? '') as String,
      date: (j['date'] ?? '') as String,
      snippet: (j['snippet'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'threadId': threadId,
        'subject': subject,
        'from': from,
        'date': date,
        'snippet': snippet,
      };
}

class GmailSearchResponse {
  final bool ok;
  final String query; // the generated Gmail q string server used
  final List<GmailEmailCard> results;

  GmailSearchResponse({
    required this.ok,
    required this.query,
    required this.results,
  });

  factory GmailSearchResponse.fromJson(Map<String, dynamic> j) {
    final list = (j['results'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => GmailEmailCard.fromJson(m.cast<String, dynamic>()))
        .toList();

    return GmailSearchResponse(
      ok: j['ok'] == true,
      query: (j['query'] ?? '') as String,
      results: list,
    );
  }
}

class GmailReadResponse {
  final bool ok;
  final String id;
  final String threadId;
  final String subject;
  final String from;
  final String date;
  final String snippet;

  GmailReadResponse({
    required this.ok,
    required this.id,
    required this.threadId,
    required this.subject,
    required this.from,
    required this.date,
    required this.snippet,
  });

  factory GmailReadResponse.fromJson(Map<String, dynamic> j) {
    return GmailReadResponse(
      ok: j['ok'] == true,
      id: (j['id'] ?? '') as String,
      threadId: (j['threadId'] ?? '') as String,
      subject: (j['subject'] ?? '') as String,
      from: (j['from'] ?? '') as String,
      date: (j['date'] ?? '') as String,
      snippet: (j['snippet'] ?? '') as String,
    );
  }
}

/// Server-side Gmail proxy client.
/// Uses your existing Node service that already holds OAuth tokens.
/// This does NOT talk to Google directly from Flutter.
class GmailClient {
  /// Example:
  ///   const GmailClient(baseUrl: 'https://roadmate-flutter.onrender.com');
  final String baseUrl;

  /// Optionally pass an auth token you use for your own server (if you add one).
  final Future<String?> Function()? getServerAuthToken;

  const GmailClient({
    required this.baseUrl,
    this.getServerAuthToken,
  });

  Uri _u(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, String>> _headers() async {
    final h = <String, String>{
      'Content-Type': 'application/json',
    };

    if (getServerAuthToken != null) {
      final token = await getServerAuthToken!();
      if (token != null && token.isNotEmpty) {
        h['Authorization'] = 'Bearer $token';
      }
    }

    return h;
  }

  /// Calls POST /gmail/search_structured
  Future<GmailSearchResponse> searchSimple({
    String? text,
    String? from,
    String? subject,
    bool? unreadOnly,
    bool? inInbox,
    int? newerThanDays,
    int maxResults = 5,
  }) async {
    final body = <String, dynamic>{
      if (text != null) 'text': text,
      if (from != null) 'from': from,
      if (subject != null) 'subject': subject,
      if (unreadOnly != null) 'unread_only': unreadOnly,
      if (inInbox != null) 'in_inbox': inInbox,
      if (newerThanDays != null) 'newer_than_days': newerThanDays,
      'max_results': maxResults,
    };

    final r = await http.post(
      _u('/gmail/search_structured'),
      headers: await _headers(),
      body: jsonEncode(body),
    );

    final data = jsonDecode(r.body) as Map<String, dynamic>;

    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Gmail search failed (${r.statusCode}): ${data['error'] ?? r.body}');
    }

    return GmailSearchResponse.fromJson(data);
  }

  /// Calls GET /gmail/read?id=...
  Future<GmailReadResponse> readEmailMetadata({required String id}) async {
    final uri = _u('/gmail/read').replace(queryParameters: {'id': id});
    final r = await http.get(uri, headers: await _headers());
    final data = jsonDecode(r.body) as Map<String, dynamic>;

    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception('Gmail read failed (${r.statusCode}): ${data['error'] ?? r.body}');
    }

    return GmailReadResponse.fromJson(data);
  }
}


/// Tool wrappers to integrate into LLM function calling.
class GmailSearchTool {
  final GmailClient client;

  GmailSearchTool({required this.client});

  /// args keys follow your tool schema:
  /// text, from, subject, unread_only, in_inbox, newer_than_days, max_results
  Future<Map<String, dynamic>> call(Map<String, dynamic> args) async {
    final resp = await client.searchSimple(
      text: args['text'] as String?,
      from: args['from'] as String?,
      subject: args['subject'] as String?,
      unreadOnly: args['unread_only'] as bool?,
      inInbox: args['in_inbox'] as bool?,
      newerThanDays: args['newer_than_days'] is num ? (args['newer_than_days'] as num).toInt() : null,
      maxResults: args['max_results'] is num ? (args['max_results'] as num).toInt() : 5,
    );

    return {
      'ok': true,
      // Useful for debugging / transparency, can remove if you want even smaller.
      'query': resp.query,
      'emails': resp.results.map((e) => e.toJson()).toList(),
    };
  }
}

class GmailReadEmailTool {
  final GmailClient client;

  GmailReadEmailTool({required this.client});

  Future<Map<String, dynamic>> call(Map<String, dynamic> args) async {
    final id = args['id'] as String?;
    if (id == null || id.isEmpty) {
      return {'ok': false, 'error': 'Missing required field: id'};
    }

    final resp = await client.readEmailMetadata(id: id);

    return {
      'ok': true,
      'email': {
        'id': resp.id,
        'threadId': resp.threadId,
        'subject': resp.subject,
        'from': resp.from,
        'date': resp.date,
        'snippet': resp.snippet,
      }
    };
  }
}