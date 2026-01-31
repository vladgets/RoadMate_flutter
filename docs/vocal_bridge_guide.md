# Vocal Bridge Developer Guide Summary

This is a backup reference for integrating with VocalBridge AI voice agents.

## Overview

Vocal Bridge provides voice AI agents using **WebRTC via LiveKit** (not direct OpenAI WebRTC). Your app connects to LiveKit rooms where the AI agent participates.

**Key difference from current RoadMate architecture:**
- Current: Flutter → WebRTC → OpenAI Realtime API directly
- VocalBridge: Flutter → LiveKit SDK → VocalBridge Server → AI Agent

## Architecture Flow

```
1. Your Backend calls VocalBridge API with API key
2. VocalBridge returns LiveKit URL + token
3. Your Client connects to LiveKit room using token
4. AI Agent joins the same room
5. Audio flows bidirectionally via LiveKit
6. Tool calls/data sent via LiveKit data channel
```

## Authentication

**API Key Format:** `vb_abc123def456...`

**IMPORTANT:** Never expose API key in client code. Call token endpoint from your backend.

### Get Token (Server-side)
```bash
curl -X POST "http://vocalbridgeai.com/api/v1/token" \
  -H "X-API-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"participant_name": "User"}'
```

### Token Response
```json
{
  "livekit_url": "wss://tutor-j7bhwjbm.livekit.cloud",
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "room_name": "user-abc-agent-xyz-api-12345",
  "participant_identity": "api-client-xxxx-12345",
  "expires_in": 3600,
  "agent_mode": "cascaded_concierge"
}
```

## Flutter SDK Integration

### Dependencies (pubspec.yaml)
```yaml
dependencies:
  livekit_client: ^2.3.0
  http: ^1.2.0
```

### Complete Flutter Example
```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';

class VoiceAgentService {
  Room? _room;
  EventsListener<RoomEvent>? _listener;

  // Get token from your backend (recommended for production)
  Future<Map<String, dynamic>> _getTokenFromBackend() async {
    final response = await http.get(
      Uri.parse('https://your-backend.com/api/voice-token'),
    );
    return jsonDecode(response.body);
  }

  // Connect to the voice agent
  Future<void> connect() async {
    final tokenData = await _getTokenFromBackend();
    final livekitUrl = tokenData['livekit_url'] as String;
    final token = tokenData['token'] as String;

    _room = Room();

    // Listen for agent audio
    _listener = _room!.createListener();
    _listener!.on<TrackSubscribedEvent>((event) {
      if (event.track.kind == TrackType.AUDIO) {
        // Audio is automatically played by LiveKit SDK
        print('Agent audio track subscribed');
      }
    });

    // Handle connection state
    _listener!.on<RoomDisconnectedEvent>((event) {
      print('Disconnected from room');
    });

    // Connect to the room
    await _room!.connect(livekitUrl, token);
    print('Connected to room: ${_room!.name}');

    // Enable microphone
    await _room!.localParticipant?.setMicrophoneEnabled(true);
    print('Microphone enabled - start speaking!');
  }

  // Disconnect from the agent
  Future<void> disconnect() async {
    await _room?.disconnect();
    _room = null;
    _listener = null;
  }

  bool get isConnected => _room?.connectionState == ConnectionState.connected;
}
```

### Handling Client Actions (Bidirectional Communication)

```dart
// Handle actions FROM the agent (Agent to App)
void _setupClientActionHandler() {
  _listener!.on<DataReceivedEvent>((event) {
    if (event.topic == 'client_actions') {
      final data = jsonDecode(utf8.decode(event.data));
      if (data['type'] == 'client_action') {
        _handleAgentAction(data['action'], data['payload']);
      }
    }
  });
}

void _handleAgentAction(String action, Map<String, dynamic> payload) {
  switch (action) {
    case 'navigate':
      print('Navigate to: ${payload['screen']}');
      break;
    case 'show_product':
      print('Show product: ${payload['productId']}');
      break;
    default:
      print('Unknown action: $action');
  }
}

// Send actions TO the agent (App to Agent)
Future<void> sendActionToAgent(String action, [Map<String, dynamic>? payload]) async {
  final message = jsonEncode({
    'type': 'client_action',
    'action': action,
    'payload': payload ?? {},
  });
  await _room?.localParticipant?.publishData(
    utf8.encode(message),
    reliable: true,
    topic: 'client_actions',
  );
}
```

### Platform Configuration

**iOS (ios/Runner/Info.plist):**
```xml
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for voice chat</string>
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

**Android (android/app/src/main/AndroidManifest.xml):**
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
```

## Client Actions

Bidirectional communication via LiveKit data channel on topic `client_actions`.

### Directions
- **Agent to App**: Agent triggers actions in your client (navigate, show UI, etc.)
- **App to Agent**: Your client sends events to agent (button clicked, data loaded, etc.)

### Behaviors (App to Agent)
- **respond** (default): Agent generates a reply when event arrives
- **notify**: Event silently added to context, agent doesn't reply immediately

### Message Format
```json
{
  "type": "client_action",
  "action": "action_name",
  "payload": { "key": "value" }
}
```

## MCP Tools

Model Context Protocol allows agents to connect to external services.

### Setup via Zapier (easiest)
1. Go to zapier.com/mcp
2. Configure apps to connect
3. Copy MCP server URL
4. Add to agent configuration

### Use Cases
- Calendar (Google/Outlook)
- CRM (Salesforce, HubSpot)
- Email/Messaging
- Database queries

## Post-Processing

Runs automatically after each call ends.

**Available Context:**
- Full transcript with speaker labels
- Call duration
- Timestamps
- Agent configuration
- MCP tools

**Use Cases:**
- Generate call summaries
- Update CRM records
- Send follow-up emails
- Create support tickets
- Escalation alerts

## API Endpoints

### POST /api/v1/token
Generate LiveKit access token.

**Request:**
```json
{
  "participant_name": "User Name",
  "session_id": "optional-custom-id"
}
```

**Response:**
```json
{
  "livekit_url": "wss://...",
  "token": "...",
  "room_name": "...",
  "participant_identity": "...",
  "expires_in": 3600,
  "agent_mode": "cascaded_concierge"
}
```

### GET /api/v1/agent
Get agent information.

**Response:**
```json
{
  "id": "uuid",
  "name": "My Voice Agent",
  "mode": "cascaded_concierge",
  "deployment_status": "active",
  "phone_number": "+1234567890",
  "greeting": "Hello! How can I help you?"
}
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| 403 Forbidden | Check API key is valid and not revoked |
| No audio from agent | Attach audio track to element, check autoplay permissions |
| Microphone not working | Request mic permission before setMicrophoneEnabled(true) |
| Token expired | Tokens valid 1 hour, request new token and reconnect |
| CORS errors | Call API from backend, not browser |

## Key Differences from Current RoadMate

| Aspect | Current RoadMate | VocalBridge |
|--------|------------------|-------------|
| Protocol | Direct WebRTC to OpenAI | LiveKit WebRTC |
| Token | OpenAI ephemeral token | LiveKit JWT |
| Connection | RTCPeerConnection | LiveKit Room |
| Audio | Manual track management | LiveKit handles |
| Data channel | Custom "oai-events" | LiveKit topics |
| Tool calls | Via data channel JSON | Via data channel (same pattern) |

## Migration Path

1. Replace `flutter_webrtc` with `livekit_client`
2. Change token endpoint to VocalBridge API
3. Replace RTCPeerConnection with LiveKit Room
4. Update audio handling (simpler with LiveKit)
5. Keep tool execution logic (similar pattern)
6. Update data channel to use LiveKit publishData
