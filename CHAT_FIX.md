# Chat API Authentication Fix

## Problem
Text chat was failing with "Incorrect API key provided" error because:
- Ephemeral tokens from `/token` endpoint are ONLY for OpenAI Realtime API (voice/WebRTC)
- They cannot be used with Chat Completions API (text chat)
- These are two different authentication mechanisms

## Solution
Created a server proxy endpoint `/chat` (similar to `/websearch`) that:
- Keeps the OpenAI API key secure on the server
- Forwards chat requests from Flutter app to OpenAI Chat Completions API
- Returns responses back to the app

## Changes Made

### Server (`server/server.js`)
Added new `/chat` endpoint:
```javascript
app.post("/chat", async (req, res) => {
  const { messages, tools, model } = req.body ?? {};
  // Proxy request to OpenAI Chat Completions API
  // Returns response to Flutter app
});
```

### Flutter Client (`lib/services/openai_chat_client.dart`)
1. Removed `_ephemeralToken` parameter from constructor
2. Changed API endpoint from `https://api.openai.com/v1/chat/completions` to `${Config.serverUrl}/chat`
3. Removed `Authorization` header (API key now on server)
4. Removed `fetchEphemeralToken()` method (no longer needed)

### Chat Screen (`lib/ui/chat_screen.dart`)
1. Changed `_chatClient` from nullable to non-nullable (`late final`)
2. Removed `_initializeChatClient()` async method
3. Instantiate client directly in `initState()`: `_chatClient = OpenAIChatClient()`
4. Removed null checks for `_chatClient`

## Deployment Steps

### Option 1: Local Server (for testing)
```bash
cd server
node server.js
```

### Option 2: Render.com (production)
```bash
cd server
git add server.js
git commit -m "Add /chat endpoint for text chat"
git push
```

Then verify deployment at: `https://roadmate-flutter.onrender.com/`

## Testing

After server is updated:
1. Hot restart Flutter app
2. Open chat screen
3. Send a text message
4. Should receive AI response without errors

## Architecture

**Before (broken):**
```
Flutter App → OpenAI Chat Completions API (with ephemeral token) ❌
```

**After (working):**
```
Flutter App → Server /chat → OpenAI Chat Completions API (with API key) ✅
```

This matches the existing pattern used by `/websearch` endpoint.

## Security Benefits
- API key never exposed to client
- Server can add rate limiting
- Server can log/monitor usage
- Consistent authentication pattern across all OpenAI endpoints
