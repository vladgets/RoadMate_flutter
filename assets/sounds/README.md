# Thinking Sound

This directory contains the audio file played while long-running tools (like web search) are executing.

## Required File

You need to add a file named `thinking.mp3` to this directory.

## Sound Characteristics

The sound should be:
- **Subtle and ambient**: Not intrusive or distracting
- **Loopable**: Should sound natural when repeating (no obvious start/end)
- **Duration**: 2-5 seconds
- **Format**: MP3
- **Volume**: Will be played at 30% volume (configured in code)

## Similar to ChatGPT Voice

ChatGPT uses a gentle, ambient "whoosh" or "pulse" sound - like a subtle digital thinking indicator.

## Options to Get the Sound

### Option 1: Generate with AI
Use an AI audio generator (e.g., ElevenLabs, Suno) with a prompt like:
> "Generate a subtle, ambient looping sound effect for a thinking indicator. Should sound like gentle digital pulses or soft whoosh sounds, 3 seconds, seamlessly loopable."

### Option 2: Free Sound Libraries
Download from free sound effect sites:
- [Freesound.org](https://freesound.org) - Search for "ambient loop", "thinking sound", "processing sound"
- [Pixabay](https://pixabay.com/sound-effects) - Free sound effects
- [ZapSplat](https://www.zapsplat.com) - Free with attribution

### Option 3: Simple Sine Wave
Create a simple sine wave loop using audio software:
- Audacity (free): Generate > Tone > Sine wave at 440Hz, add fade in/out
- Export as MP3

### Option 4: No Sound (Fallback)
The app will work without the sound file - it will fail silently and just continue without audio feedback.

## Tools That Trigger the Sound

The thinking sound plays for these tools:
- `web_search` - Web search requests
- `gmail_search` - Gmail search
- `gmail_read_email` - Reading email content
- `traffic_eta` - Getting traffic information
- `youtube_get_subscriptions_feed` - Fetching YouTube feed

You can modify the list in `lib/main.dart` in the `_executeToolCallFromEvent` method.
