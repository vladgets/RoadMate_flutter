# Vocal Bridge Voice Agent Integration

## Overview
Integrate the "roadmate" voice agent into your application.
This agent uses WebRTC via LiveKit for real-time voice communication.

## Agent Configuration
- **Agent Name**: roadmate
- **Mode**: openai_concierge
- **Greeting**: "Hello! This is roadmate.ai, how can I help you today"
- **Phone Number**: +14849845421

## Client Actions (Bidirectional)

### Agent to App (Outbound)
The agent can trigger these actions in your client application:

| Action | Description | Payload |
|--------|-------------|---------|
| `get_current_location` | Get GPS location | None |
| `memory_append` | Save fact to memory | `{"text": "..."}` |
| `memory_fetch` | Fetch all memory facts | None |
| `get_calendar_data` | Fetch calendar events | None |
| `get_current_time` | Get current date/time | None |
| `web_search` | Search the web | `{"query": "..."}` |
| `gmail_search` | Search Gmail | `{"text": "...", "from": "...", "max_results": 5}` |
| `gmail_read_email` | Read email by ID | `{"message_id": "..."}` |
| `traffic_eta` | Get ETA to destination | `{"destination": "...", "route_type": "by_car"}` |
| `navigate_to_destination` | Open Maps app | `{"destination": "...", "nav_app": "system"}` |
| `call_phone` | Place phone call | `{"phone_number": "...", "contact_name": "..."}` |
| `reminder_create` | Create reminder | `{"text": "...", "when_iso": "..."}` |
| `reminder_list` | List reminders | None |
| `reminder_cancel` | Cancel reminder | `{"id": 12345}` |
| `youtube_search` | Search YouTube | `{"query": "...", "max_results": 5}` |
| `youtube_get_transcript` | Get video transcript | `{"video_id": "..."}` |
| `youtube_play` | Play video | `{"video_id": "..."}` |

### App to Agent (Inbound) - Respond
Your client app sends these responses back to the agent:

| Action | Description |
|--------|-------------|
| `get_current_location` | Returns GPS coords and address |
| `get_current_time` | Returns readable date/time |
| `get_calendar_data` | Returns calendar events |
| `memory_fetch` | Returns stored facts |
| `web_search` | Returns search results |
| `gmail_search` | Returns email list |
| `gmail_read_email` | Returns email content |
| `traffic_eta` | Returns ETA and traffic |
| `reminder_list` | Returns reminders |
| `youtube_search` | Returns video results |
| `youtube_get_transcript` | Returns transcript |

## Message Format

### Receiving (Agent to App)
```json
{
  "type": "client_action",
  "action": "get_current_location",
  "payload": {}
}
```

### Sending (App to Agent)
```json
{
  "type": "client_action",
  "action": "get_current_location",
  "payload": {
    "ok": true,
    "lat": 37.7749,
    "lon": -122.4194,
    "address": {"city": "San Francisco", "state": "CA"}
  }
}
```

## Flutter Implementation

```dart
// Send result back to agent
Future<void> sendActionToAgent(String action, Map<String, dynamic> payload) async {
  final message = jsonEncode({
    'type': 'client_action',
    'action': action,
    'payload': payload,
  });
  await room.localParticipant?.publishData(
    utf8.encode(message),
    reliable: true,
    topic: 'client_actions',
  );
}
```
