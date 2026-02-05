# Chat Interface Testing Guide

## Pre-Test Setup
1. Ensure backend server is running (or use production URL)
2. Ensure `OPENAI_API_KEY` is configured on server
3. Build and run the app: `flutter run`

## Test Cases

### 1. Initial App Launch
- [ ] App opens to Voice Mode (big mic button)
- [ ] Chat button appears in AppBar (bubble icon)
- [ ] Chat button is initially disabled (gray) while store initializes
- [ ] Chat button becomes enabled (white) after ~1 second

### 2. Voice Mode → Chat Navigation
- [ ] Tap Chat button in Voice Mode
- [ ] Chat screen opens with empty state
- [ ] Shows "No messages yet" with icon
- [ ] Back button returns to Voice Mode
- [ ] Settings button works

### 3. Voice Transcript Saving
- [ ] Start voice session (tap mic button)
- [ ] Speak a question: "What's the weather like?"
- [ ] Wait for assistant response
- [ ] Navigate to Chat screen
- [ ] Verify user message appears with mic icon + "Voice" label
- [ ] Verify assistant response appears below it

### 4. Text Message Sending
- [ ] Open Chat screen
- [ ] Type "Hello" in text input
- [ ] Tap Send button (or press Enter on keyboard)
- [ ] Verify user message appears (blue bubble, right side)
- [ ] Verify loading indicator shows "Thinking..."
- [ ] Verify assistant response appears (gray bubble, left side)

### 5. Mic Button in Chat
- [ ] Open Chat screen
- [ ] Tap mic button (right corner of input area)
- [ ] Verify app navigates back to Voice Mode
- [ ] Verify existing voice session continues (or starts new)

### 6. Message Persistence
- [ ] Send several messages (voice + text)
- [ ] Force quit the app
- [ ] Relaunch the app
- [ ] Open Chat screen
- [ ] Verify all previous messages still appear

### 7. Message Limit (500 messages)
*Note: This test requires automation or patience*
- [ ] Send 500+ messages
- [ ] Verify oldest messages are pruned
- [ ] Verify message count never exceeds 500

### 8. Error Handling
- [ ] Turn off WiFi/data
- [ ] Try sending a text message
- [ ] Verify error banner appears at top
- [ ] Tap X to dismiss error banner
- [ ] Reconnect WiFi
- [ ] Verify message sending works again

### 9. UI Responsiveness
- [ ] Send multiple messages in quick succession
- [ ] Verify messages appear in order
- [ ] Verify auto-scroll to bottom works
- [ ] Verify loading indicator only shows during API calls
- [ ] Verify text input clears after sending

### 10. Edge Cases
- [ ] Try sending empty message (button should be enabled but nothing happens)
- [ ] Try sending message while another is in progress (should queue or ignore)
- [ ] Try opening Chat while voice session is active (both should work)
- [ ] Try long messages (multi-line text input)
- [ ] Try very long messages (>1000 chars)

## Known Issues to Watch For

### Voice Transcript Timing
- Voice transcripts may arrive delayed
- Multiple voice turns may arrive together
- Check that order is preserved

### API Token Expiration
- Ephemeral tokens expire after ~60 seconds
- Chat client fetches new token on init
- Long chat sessions may require token refresh (not yet implemented)

### Tool Calls from Text
- Tool execution from text messages is not yet fully integrated
- If assistant requests a tool call, it will return error response
- This is expected in Phase 1

## Performance Benchmarks

### Load Time
- App launch to Voice Mode: < 2 seconds
- Voice Mode to Chat Screen: < 500ms
- Chat Screen with 100 messages: < 1 second

### Memory Usage
- 500 messages stored: ~50-100 KB
- SharedPreferences read/write: < 100ms
- No memory leaks on repeated navigation

## Debugging Tips

### Check Logs
```bash
flutter logs | grep "🧑\|🤖\|>>>"
```
- `🧑 User said:` - Voice input transcripts
- `🤖 Assistant said:` - Voice output transcripts
- `>>>` - Tool execution logs

### Inspect Storage
```dart
// In Flutter DevTools Console
SharedPreferences prefs = await SharedPreferences.getInstance();
String? history = prefs.getString('conversation_history');
print(history);
```

### Clear Storage
```dart
// To reset chat history
SharedPreferences prefs = await SharedPreferences.getInstance();
await prefs.remove('conversation_history');
```

## Regression Testing

When making future changes, verify these still work:
- [ ] Voice Mode → Chat navigation
- [ ] Voice transcripts saved to chat
- [ ] Text messages send successfully
- [ ] Messages persist across restarts
- [ ] Mic button in chat returns to voice mode
