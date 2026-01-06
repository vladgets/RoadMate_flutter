import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'ui/memory_settings_screen.dart';
import 'ui/extensions_settings_screen.dart';
import 'services/extra_tools.dart';
import 'services/memory_store.dart';
import 'services/calendar_store.dart';
import 'services/web_search.dart';
import 'services/gmail_client.dart';


void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const VoiceButtonPage(),
    );
  }
}

class VoiceButtonPage extends StatefulWidget {
  const VoiceButtonPage({super.key});

  @override
  State<VoiceButtonPage> createState() => _VoiceButtonPageState();
}

class _VoiceButtonPageState extends State<VoiceButtonPage> {
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  MediaStream? _mic;

  // final String tokenServerUrl = "http://10.0.2.2:3000/token";
  static const serverUrl = "https://roadmate-flutter.onrender.com";
  static const tokenServerUrl = '$serverUrl/token';

  // Web search (reuse single instances)
  late final WebSearchClient _webSearchClient = WebSearchClient();
  late final WebSearchTool _webSearchTool = WebSearchTool(client: _webSearchClient);
  // Gmail client
  final gmailClient = GmailClient(baseUrl: serverUrl);

  bool _connecting = false;
  bool _connected = false;
  String? _status;
  String? _error;

  @override
  void dispose() {
    _webSearchClient.close();
    _disconnect();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_connecting) return;
    if (_connected) {
      await _disconnect();
    } else {
      await _connect();
    }
  }

  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
      _status = "Requesting token…";
    });

    try {
      // 1) Get ephemeral key from your backend
      final tokenResp = await http.get(Uri.parse(tokenServerUrl));
      final tokenJson = jsonDecode(tokenResp.body) as Map<String, dynamic>;
      final ephemeralKey = tokenJson['value'] as String;

      setState(() => _status = "Creating peer connection…");

      // 2) Create PeerConnection
      _pc = await createPeerConnection({
        // Start minimal. If you see ICE failures on some networks,
        // add a STUN server:
        // 'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]
      });

      // 3) Remote audio track will arrive here.
      // On mobile, WebRTC audio generally plays via native audio output automatically.
      _pc!.onTrack = (RTCTrackEvent e) {
        if (e.track.kind == 'audio') {
          setState(() => _status = "Assistant connected (audio ready). Talk!");
        }
      };

      // 4) Local mic stream
      setState(() => _status = "Opening microphone…");
      _mic = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });

      final audioTrack = _mic!.getAudioTracks().first;
      await _pc!.addTrack(audioTrack, _mic!);

      // 5) Data channel (optional but useful for session updates / events)
      _dc = await _pc!.createDataChannel("oai-events", RTCDataChannelInit());

      _dc!.onDataChannelState = (RTCDataChannelState state) {
        debugPrint("DataChannel state: $state");

      };

      _dc!.onMessage = (RTCDataChannelMessage msg) {
        // You can log JSON events here for debugging.
        debugPrint("OAI event: ${msg.text}");

        // Best-effort parse and route.
        handleOaiEvent(msg.text);
      };

      // 6) Offer/Answer SDP exchange
      setState(() => _status = "Creating offer…");
      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _pc!.setLocalDescription(offer);

      setState(() => _status = "Calling OpenAI Realtime…");
      final answerSdp = await _createCallAndGetAnswerSdp(
        ephemeralKey: ephemeralKey,
        offerSdp: offer.sdp!,
      );

      await _pc!.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));

      setState(() {
        _connected = true;
        _status = "Connected. Talk!";
      });
    } catch (e) {
      await _disconnect();
      setState(() {
        _error = e.toString();
        _status = null;
      });
    } finally {
      setState(() => _connecting = false);
    }
  }

  Future<String> _createCallAndGetAnswerSdp({
    required String ephemeralKey,
    required String offerSdp,
  }) async {
    final uri = Uri.parse("https://api.openai.com/v1/realtime/calls");
    final req = http.MultipartRequest("POST", uri);

    // IMPORTANT: use the ephemeral key here (NOT your real API key).
    req.headers['Authorization'] = "Bearer $ephemeralKey";

    // Optional session override; can be minimal if you already set it in /token.
    req.fields['session'] = jsonEncode({
      "type": "realtime",
      "model": Config.model,
      "instructions": Config.buildSystemPrompt(),
      "tools": Config.tools,
      "tool_choice": "auto",
      "audio": {
        "input": {"turn_detection": {"type": "server_vad"}},
        "output": {"voice": Config.voice},
      }
    });

    req.fields['sdp'] = offerSdp;

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200 && streamed.statusCode != 201) {
      throw Exception("OpenAI create call failed ${streamed.statusCode}: $body");
    }
    return body; // SDP answer
  }

  Future<void> _disconnect() async {
    try {
      await _dc?.close();
      await _pc?.close();

      final tracks = _mic?.getTracks() ?? [];
      for (final t in tracks) {
        await t.stop();
      }
      await _mic?.dispose();
    } catch (_) {
      // ignore cleanup errors
    } finally {
      _dc = null;
      _pc = null;
      _mic = null;
      if (mounted) {
        setState(() {
          _connected = false;
          _connecting = false;
          _status = "Disconnected.";
        });
      }
    }
  }

  /// Simple implementation of tool handling for now
  void handleOaiEvent(String text) {
    Map<String, dynamic> evt;

    // Parse JSON
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return;
      evt = decoded;
    } catch (_) {
      return; // Ignore non-JSON messages
    }

    final item = evt['item'];

    // We only care about function/tool calls
    if (item is! Map<String, dynamic>) return;
    if (item['type'] != 'function_call') return;

    debugPrint(">>> Function call event: $item");
    final callId = item['call_id'] ?? item['id'];
    final name = item['name'];
    final arguments = item['arguments'];

    if (callId == null || name == null) return;

    _executeToolCallFromEvent(
      {
        'call_id': callId,
        'name': name,
        'arguments': arguments,
      }
    );
  }


/// Tool handlers map
 late final Map<String, Future<Map<String, dynamic>> Function(dynamic args)> _tools = {
   'get_current_location': (_) async {
     return await getCurrentLocation(); 
   },
  // Long-term memory tools
  'memory_append': (args) async {
    return await MemoryStore.toolAppend(args);
  },
  'memory_fetch': (_) async {
    return await MemoryStore.toolRead();
  },
  // Calendar tools
  'get_calendar_data': (_) async {
    return await CalendarStore.toolGetCalendarData();
  },
  // 'create_calendar_event': (args) async {
  //   return await CalendarStore.toolCreateCalendarEvent(args);
  // },
  // 'update_calendar_event': (args) async {
  //   return await CalendarStore.toolUpdateCalendarEvent(args);
  // },
  // 'delete_calendar_event': (args) async {
  //   return await CalendarStore.toolDeleteCalendarEvent(args);
  // },
  // Time and date tool
  'get_current_time': (_) async {
    return await getCurrentTime(); 
  },
  // Web search tool
  'web_search': (args) async {
    return await _webSearchTool.call(args);
  }
};


  /// Extracts tool name + arguments from an event, runs the handler,
  /// and sends the tool output back to the model over the data channel.
  Future<void> _executeToolCallFromEvent(Map<String, dynamic> evt) async {
    final String? callId = evt['call_id'];
    final String? toolName = evt['name'];
    if (callId == null || toolName == null || toolName.isEmpty) return;

    dynamic args = evt['arguments'];
    if (args == '') {
      args = {};
    }
    else if (args is String) {
      args = jsonDecode(args);
    }

    final toolHandler = _tools[toolName];
    if (toolHandler == null) return;

    try {
      final Map<String, dynamic> result = await toolHandler(args);
      // Log calendar function results for debugging
      if (toolName.contains('calendar')) {
        debugPrint('>>> Calendar function ($toolName) result: ${jsonEncode(result)}');
      }
      await _sendToolOutput(callId: callId, name: toolName, output: result);
    } catch (e) {
      debugPrint('>>> Tool execution error ($toolName): $e');
      await _sendToolOutput(
        callId: callId,
        name: toolName,
        output: {'error': e.toString()},
      );
    }
  }

  /// Sends tool output back to the model.
  ///
  /// The Realtime API expects a "tool output" / "function_call_output" item.
  /// If your logs show a different required shape, adjust here (this is the single place).
  Future<void> _sendToolOutput({
    required String callId,
    required String name,
    required Map<String, dynamic> output,
  }) async {
    final dc = _dc;
    if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen) return;

    final payload = {
      'type': 'conversation.item.create',
      'item': {
        'type': 'function_call_output',
        'call_id': callId,
        // 'name': name,
        'output': jsonEncode(output),
      },
    };

    dc.send(RTCDataChannelMessage(jsonEncode(payload)));

    // Ask the model to continue after receiving the tool output.
    dc.send(RTCDataChannelMessage(jsonEncode({'type': 'response.create'})));
  }


  /// UI part
  @override
  Widget build(BuildContext context) {
    final isBusy = _connecting;
    final label = _connected ? "Tap to stop" : "Tap to talk";
    final icon = _connected ? Icons.stop_circle : Icons.mic;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _status ?? (isBusy ? "Working…" : "Ready."),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 36),
                GestureDetector(
                  onTap: isBusy ? null : _toggle,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _connected ? Colors.redAccent : Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.25),
                          blurRadius: 24,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: Icon(
                      icon,
                      size: 72,
                      color: _connected ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
                const SizedBox(height: 10),
                Text(
                  isBusy ? "Connecting…" : (_connected ? "Speak now" : "Not connected"),
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
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
            title: const Text('Testing'),
            subtitle: const Text('Run WebSearch test (logs only)'),
            trailing: const Icon(Icons.play_arrow),
            onTap: () {
              testWebSearch();
              Navigator.of(context).maybePop();
            },
          ),
        ],
      ),
    );
  }
}

