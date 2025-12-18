import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;


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

  bool _connecting = false;
  bool _connected = false;
  String? _status;
  String? _error;

  // For Android emulator use: http://10.0.2.2:3000/token
  // For real phone: http://<YOUR_MAC_LAN_IP>:3000/token
  final String tokenServerUrl = "http://10.0.2.2:3000/token";

  @override
  void dispose() {
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
        // ignore: avoid_print
        print("DataChannel state: $state");

        // if (state == RTCDataChannelState.RTCDataChannelOpen) {
        //   _dc!.send(RTCDataChannelMessage(jsonEncode({
        //     "type": "session.update",
        //     "session": {
        //       "turn_detection": {"type": "server_vad"},
        //       "voice": "alloy",
        //       "modalities": ["audio", "text"]
        //     }
        //   })));
        // }

        // if (state == RTCDataChannelState.RTCDataChannelOpen) {
        //   // Deterministic test: force an audio response via text.
        //   final userText = {
        //     "type": "conversation.item.create",
        //     "item": {
        //       "type": "message",
        //       "role": "user",
        //       "content": [
        //         {"type": "input_text", "text": "Say hello in one short sentence."}
        //       ]
        //     }
        //   };

        //   final responseCreate = {
        //     "type": "response.create",
        //     "response": {
        //       "output_modalities": ["audio"],
        //     }
        //   };

        //   _dc!.send(RTCDataChannelMessage(jsonEncode(userText)));
        //   _dc!.send(RTCDataChannelMessage(jsonEncode(responseCreate)));
        // }
      };

      _dc!.onMessage = (RTCDataChannelMessage msg) {
        // You can log JSON events here for debugging.
        // ignore: avoid_print
        print("OAI event: ${msg.text}");
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
      "model": "gpt-realtime",
      "audio": {
        "input": {"turn_detection": {"type": "server_vad"}},
        "output": {"voice": "alloy"},
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

  @override
  Widget build(BuildContext context) {
    final isBusy = _connecting;
    final label = _connected ? "Tap to stop" : "Tap to talk";
    final icon = _connected ? Icons.stop_circle : Icons.mic;

    return Scaffold(
      backgroundColor: Colors.black,
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
