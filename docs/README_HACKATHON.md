# RoadMate - VocalBridge Hackathon Edition

A hands-free voice assistant for drivers, powered by VocalBridge + LiveKit.

## Quick Start

### Prerequisites
- Flutter SDK (3.10.4+)
- Xcode (for iOS)
- iPhone with iOS 15.0+
- VocalBridge API key

### Run the App

```bash
# Install dependencies
flutter pub get

# Run on connected iPhone
flutter run -t lib/main_vocal_bridge.dart

# Or specify device
flutter run -t lib/main_vocal_bridge.dart -d <device_id>
```

### Run Standalone on iPhone

```bash
# Build release version (runs without Mac connected)
flutter run -t lib/main_vocal_bridge.dart --release
```

After installing, go to **Settings → General → VPN & Device Management** and trust the developer certificate.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        VocalBridge Cloud                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────┐  │
│  │ LiveKit     │◄──►│ Voice Agent │◄──►│ OpenAI GPT-4o      │  │
│  │ WebRTC      │    │ (roadmate)  │    │ Realtime API       │  │
│  └─────────────┘    └─────────────┘    └─────────────────────┘  │
└────────────▲────────────────────────────────────▲────────────────┘
             │                                    │
             │ Audio + Data Channel               │ Client Actions
             │                                    │
┌────────────▼────────────────────────────────────▼────────────────┐
│                      Flutter App (iPhone)                        │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                  vocal_bridge_service.dart                   │ │
│  │  - Connects to LiveKit room                                  │ │
│  │  - Sends/receives audio                                      │ │
│  │  - Handles client actions                                    │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                              │                                   │
│         ┌────────────────────┼────────────────────┐              │
│         ▼                    ▼                    ▼              │
│  ┌─────────────┐    ┌─────────────────┐    ┌───────────────┐    │
│  │ Location    │    │ Calendar/Gmail  │    │ Navigation    │    │
│  │ Memory      │    │ Web Search      │    │ Phone Calls   │    │
│  │ Time        │    │ Reminders       │    │ YouTube       │    │
│  └─────────────┘    └─────────────────┘    └───────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

## Supported Functions

### Location & Time

| Function | Description | Example Voice Command |
|----------|-------------|----------------------|
| `get_current_location` | GPS coordinates + reverse geocoded address | "Where am I?" |
| `get_current_time` | Current date and time | "What time is it?" |

### Memory

| Function | Description | Example Voice Command |
|----------|-------------|----------------------|
| `memory_append` | Save a fact to long-term memory | "Remember that my wife's birthday is March 15th" |
| `memory_fetch` | Retrieve all stored facts | "What do you remember about me?" |

### Calendar

| Function | Description | Example Voice Command |
|----------|-------------|----------------------|
| `get_calendar_data` | Fetch upcoming calendar events | "What's on my calendar today?" |

### Email (Gmail)

| Function | Description | Example Voice Command |
|----------|-------------|----------------------|
| `gmail_search` | Search emails by keywords, sender, subject | "Do I have any emails from John?" |
| `gmail_read_email` | Read full email content | "Read me that email" |

### Navigation & Traffic

| Function | Description | Example Voice Command |
|----------|-------------|----------------------|
| `traffic_eta` | Get ETA and traffic conditions | "How long to get to the airport?" |
| `navigate_to_destination` | Open Maps with directions | "Navigate to Whole Foods" |

Supported navigation apps: Apple Maps, Google Maps, Waze

### Phone Calls

| Function | Description | Example Voice Command |
|----------|-------------|----------------------|
| `call_phone` | Initiate a phone call | "Call mom" |

### Reminders

| Function | Description | Example Voice Command |
|----------|-------------|----------------------|
| `reminder_create` | Create a local notification reminder | "Remind me to take medicine at 6pm" |
| `reminder_list` | List all scheduled reminders | "What reminders do I have?" |
| `reminder_cancel` | Cancel a reminder by ID | "Cancel my medicine reminder" |

### Web Search

| Function | Description | Example Voice Command |
|----------|-------------|----------------------|
| `web_search` | Search the web for current information | "What's the weather in San Francisco?" |

### YouTube (Coming Soon)

| Function | Description | Example Voice Command |
|----------|-------------|----------------------|
| `youtube_search` | Search for videos | "Find videos about cooking pasta" |
| `youtube_get_transcript` | Get video transcript for summarization | "Summarize this video" |
| `youtube_play` | Play a video | "Play that video" |

## File Structure

```
lib/
├── main_vocal_bridge.dart      # Entry point for VocalBridge version
├── vocal_bridge_page.dart      # Main UI with mic button
├── config.dart                 # System prompt, voice settings
│
└── services/
    ├── vocal_bridge_service.dart   # LiveKit connection + action handling
    ├── geo_time_tools.dart         # Location + time functions
    ├── memory_store.dart           # Long-term memory storage
    ├── calendar.dart               # Device calendar access
    ├── gmail_client.dart           # Gmail API integration
    ├── web_search.dart             # Web search via backend
    ├── map_navigation.dart         # Maps + traffic ETA
    ├── phone_call.dart             # Phone call initiation
    └── reminders.dart              # Local notification reminders
```

## Configuration

### VocalBridge Agent Settings

The agent is configured in the VocalBridge dashboard with:

- **Agent Name**: roadmate
- **Mode**: openai_concierge
- **Voice**: OpenAI Realtime voice
- **Client Actions**: Bidirectional (Agent↔App)

### API Key

For hackathon use, the API key is hardcoded in `vocal_bridge_page.dart`:

```dart
static const _apiKey = 'vb_fVxcZYHBfAgBYPmwmCLEa99wgy0m_eVvgkL5lNbTipk';
```

**For production**: Move to backend token endpoint.

## Client Actions Protocol

### Receiving Actions (Agent → App)

```dart
// Listen for DataReceivedEvent on topic "client_actions"
{
  "type": "client_action",
  "action": "get_current_location",
  "payload": {}
}
```

### Sending Results (App → Agent)

```dart
// Publish data on topic "client_actions"
{
  "type": "client_action",
  "action": "get_current_location",
  "payload": {
    "ok": true,
    "lat": 37.7749,
    "lon": -122.4194,
    "address": {
      "street": "123 Main St",
      "city": "San Francisco",
      "state": "CA"
    }
  }
}
```

## Debugging

### View Logs (Mac Connected)

```bash
flutter run -t lib/main_vocal_bridge.dart
# Logs appear in terminal with [VocalBridge] prefix
```

### VocalBridge Debug Stream

```bash
# Install CLI
pip install vocal-bridge

# Authenticate
vb auth login

# Stream live events
vb debug
```

### Common Issues

| Issue | Solution |
|-------|----------|
| "Location permission denied" | Grant location permission in iOS Settings |
| "Agent says working on it but no result" | Check App→Agent actions are configured with "Respond" behavior |
| App crashes on standalone launch | Build with `--release` flag, trust developer certificate |
| No audio from agent | Check iOS audio routing, try with headphones |

## Dependencies

```yaml
dependencies:
  livekit_client: ^2.6.1      # WebRTC via LiveKit
  geolocator: ^14.0.0         # GPS location
  geocoding: ^4.0.0           # Reverse geocoding
  device_calendar: ^4.3.0     # Calendar access
  url_launcher: ^6.3.0        # Open Maps, make calls
  permission_handler: ^12.0.1 # Runtime permissions
  shared_preferences: ^2.3.0  # Local storage
  flutter_local_notifications: ^18.0.1  # Reminders
```

## Team

Built for the VocalBridge Voice Hackathon by:
- Feiyu (Flutter app)
- Vlad
- Alexey

## Links

- [VocalBridge Dashboard](https://vocalbridgeai.com)
- [LiveKit Flutter SDK](https://docs.livekit.io/client-sdk-flutter/)
- [Original RoadMate Repo](https://github.com/anthropics/roadmate)
