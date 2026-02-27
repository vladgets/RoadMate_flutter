# RoadMate Voice Activation

Replace your phone's default assistant with RoadMate for hands-free voice control.

## Quick Setup

### Android: Replace Google Assistant

1. **Open Settings** → Apps → Default apps → Digital assistant app
2. **Select "RoadMate"** from the list
3. **Done!** Long-press the home button to launch RoadMate

Now when you long-press the home button (or say "OK Google" on some devices), RoadMate will open in voice mode.

### iOS: Siri Shortcut

Since iOS doesn't allow replacing Siri, we use a Shortcut that Siri can trigger.

#### Option 1: Download Pre-made Shortcut
1. Open this link on your iPhone: `[SHORTCUT_LINK]`
2. Tap "Add Shortcut"
3. Say **"Hey Siri, RoadMate"** to activate

#### Option 2: Create Your Own Shortcut
1. Open the **Shortcuts** app
2. Tap **+** to create new shortcut
3. Add these actions:

```
1. Dictate Text
   └─ (captures your voice input)

2. Get Contents of URL
   └─ URL: https://roadmate-flutter.onrender.com/siri
   └─ Method: POST
   └─ Headers: Content-Type = application/json
   └─ Request Body: JSON
      └─ input: [Dictated Text]
      └─ client_id: [your-unique-id]

3. Get Dictionary Value
   └─ Get "response" from [Contents of URL]

4. Speak Text
   └─ [Dictionary Value]
```

4. Name the shortcut **"RoadMate"**
5. Say **"Hey Siri, RoadMate"** to use it

---

## Features Available

### Via Assistant Launch (Android)
When launched via long-press home:
- Full voice conversation
- All RoadMate tools (location, calendar, memory, navigation, etc.)
- Auto-starts listening

### Via Siri Shortcut (iOS)
- Voice input → text response → Siri speaks
- Web search
- General Q&A
- Chat with memory

**Note:** Some features require opening the full app:
- Navigation (needs to open Maps)
- Phone calls
- Reminders with notifications
- Calendar access

---

## Server Endpoint

The Siri Shortcut uses the `/siri` endpoint:

### Request
```bash
curl -X POST https://roadmate-flutter.onrender.com/siri \
  -H "Content-Type: application/json" \
  -d '{"input": "What is the weather today?", "client_id": "my-device"}'
```

### Response
```json
{
  "ok": true,
  "response": "It's sunny and 72°F in San Francisco today.",
  "speech": "It's sunny and 72°F in San Francisco today."
}
```

### Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/siri` | POST | Main voice request handler |
| `/siri/health` | GET | Health check |
| `/siri/clear` | POST | Clear conversation history |

---

## Android Technical Details

### How It Works
1. User long-presses home button
2. Android sends `ACTION_ASSIST` intent to RoadMate
3. `MainActivity.kt` detects the intent
4. Flutter checks via `AssistantLaunchService`
5. App auto-starts voice mode

### Supported Intents
- `android.intent.action.ASSIST` - Long-press home
- `android.intent.action.VOICE_COMMAND` - Voice command
- `android.intent.action.SEARCH_LONG_PRESS` - Search button

### Setting as Default Assistant
Users can set RoadMate as default via:
- Settings → Apps → Default apps → Digital assistant app
- Or: Settings → Apps → Default apps → Assist app

---

## iOS Technical Details

### How It Works
1. User says "Hey Siri, RoadMate"
2. Siri triggers the Shortcut
3. Shortcut captures voice via "Dictate Text"
4. Sends HTTP POST to `/siri` endpoint
5. Server processes with OpenAI
6. Response returned to Shortcut
7. Shortcut speaks the response

### Limitations
- Requires internet connection
- ~2-3 second latency
- Cannot access on-device features directly
- Siri may interrupt for confirmation on first use

### Shortcut JSON Export
```json
{
  "WFWorkflowName": "RoadMate",
  "WFWorkflowActions": [
    {
      "WFWorkflowActionIdentifier": "is.workflow.actions.dictatetext",
      "WFWorkflowActionParameters": {}
    },
    {
      "WFWorkflowActionIdentifier": "is.workflow.actions.downloadurl",
      "WFWorkflowActionParameters": {
        "WFURL": "https://roadmate-flutter.onrender.com/siri",
        "WFHTTPMethod": "POST",
        "WFHTTPBodyType": "Json",
        "WFHTTPHeaders": {
          "Content-Type": "application/json"
        },
        "WFJSONValues": {
          "input": {"WFVariableType": "Variable", "WFVariableName": "Dictated Text"},
          "client_id": "siri-shortcut"
        }
      }
    },
    {
      "WFWorkflowActionIdentifier": "is.workflow.actions.getvalueforkey",
      "WFWorkflowActionParameters": {
        "WFDictionaryKey": "response"
      }
    },
    {
      "WFWorkflowActionIdentifier": "is.workflow.actions.speaktext",
      "WFWorkflowActionParameters": {}
    }
  ]
}
```

---

## Widgets

### Android Widget
Add a home screen widget for one-tap voice activation:
1. Long-press home screen → Widgets
2. Find "RoadMate"
3. Drag to home screen
4. Tap to launch voice mode

### iOS Widget
Add a lock screen or home screen widget:
1. Long-press home screen → Edit
2. Tap + → Search "RoadMate"
3. Add widget
4. Tap to launch app in voice mode

---

## Troubleshooting

### Android
| Issue | Solution |
|-------|----------|
| RoadMate not in assistant list | Reinstall app, ensure AndroidManifest has ASSIST intent |
| Long-press still opens Google | Check Settings → Default apps → Digital assistant |
| Voice not auto-starting | Check microphone permission |

### iOS
| Issue | Solution |
|-------|----------|
| Siri says "I can't find that shortcut" | Re-create shortcut, ensure name is "RoadMate" |
| Shortcut fails silently | Check server URL, test `/siri/health` endpoint |
| Response not spoken | Add "Speak Text" action at end of shortcut |
| Slow response | Normal latency is 2-3 seconds |

---

## Privacy

- **Android Assistant**: All processing happens on-device + OpenAI API
- **iOS Shortcut**: Voice is sent to RoadMate server, then OpenAI
- **Chat History**: Stored per client_id, cleared on request
- **No data shared** with third parties except OpenAI for processing

---

## Future Improvements

- [ ] Wake word detection ("Hey RoadMate") - Android only
- [ ] CarPlay integration
- [ ] Android Auto integration
- [ ] Lock screen voice activation
- [ ] Offline mode for basic commands
