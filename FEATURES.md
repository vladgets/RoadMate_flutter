# RoadMate — Feature Overview

**RoadMate** is an AI-powered voice assistant for drivers, built on OpenAI's Realtime API with WebRTC for low-latency, natural-sounding conversation. It runs on iOS and Android and is designed to be fully hands-free — the driver speaks, the car responds.

---

## Existing Capabilities

### Voice Interaction
- **Real-time conversational voice** — sub-second latency via OpenAI Realtime API + WebRTC; driver can interrupt the assistant mid-sentence (barge-in)
- **Dual interaction modes** — voice (primary, hands-free) and text chat (co-pilot or passenger use)
- **Selectable assistant voice** — Marin (female) or Echo (male)
- **Persistent conversation sessions** — up to 10 sessions with full history, browse and switch between trips
- **Dynamic personality** — assistant mirrors the user's language and adapts tone to driving context

### Autonomous Drive Detection
- **Auto-starts on driving** — uses on-device activity recognition to detect when the user enters a vehicle; voice mode activates without touching the phone
- **Auto-stops when parked** — detects stillness/walking to end the session; 90-second buffer prevents false stops at red lights
- **Background foreground service** — keeps the assistant alive with screen locked (Android + iOS)
- **Driving log** — every trip start and park event is timestamped with GPS and reverse-geocoded address

### Navigation & Traffic
- **Real-time traffic ETA** — query travel time to any destination with live traffic conditions
- **Voice-activated navigation** — opens Apple Maps, Google Maps, or Waze by voice command
- **Named places** — user can label saved locations (Home, Work, Gym) for natural references ("navigate home")
- **Place visit history** — log of locations where the user spent meaningful time

### Communication
- **Hands-free phone calls** — "Call Mom" resolves from memory and dials
- **WhatsApp messaging** — send messages and photos to contacts by voice, fully automatic when account is paired; share-sheet fallback otherwise
- **Multi-photo WhatsApp** — attach up to 10 photos from the album in a single message (by location or time period)
- **Gmail** — search and read emails by voice ("any urgent emails from Sarah?")

### Memory & Context
- **Long-term memory** — assistant remembers facts across sessions (contacts, preferences, personal details) stored locally on device
- **Voice memories / travel journal** — save narrative stories with auto-captured GPS and timestamp; searchable by location or time
- **User preferences** — plain-text preferences file injected into every session so the assistant always knows the user's context

### Reminders & Notifications
- **One-time and recurring reminders** — set by voice; daily and weekly recurrence supported
- **AI-generated reminder content** — reminders can carry a prompt (e.g., "motivational quote") and the assistant generates fresh content at fire time
- **Works when app is closed** — Android WorkManager ensures reminders fire reliably

### Photo & Media
- **Natural language photo search** — "Show me photos from Paris last summer" — searches by GPS location and date
- **YouTube subscriptions** — browse latest videos from subscriptions and play by voice
- **AI photo collage** — select photos and voice memories; DALL-E 3 generates a contextual background; layout styles: scrapbook, magazine, grid

### App Control (Android)
- **Voice control of any app** — tap buttons, type text, and launch apps in any foreground application (Spotify, Waze, Google Maps, etc.) using Android Accessibility Service
- **"Confirm the Waze alert"**, **"Skip this song"**, **"Open Instagram"** — all hands-free
- **Quick Settings tile** — double-tap hardware shortcut to start/stop voice mode without unlocking the phone

### Web & Knowledge
- **Web search** — ask any question; assistant retrieves live information via OpenAI web search and summarizes for voice

---

## Potential Future Features

These are capabilities that do not yet exist in the product but would deliver high value in a driving context.

### Safety & Driver State
- **Drowsiness / fatigue detection** — analyze voice tone, response latency, and silence patterns to detect early signs of tiredness; proactively suggest a break or coffee stop
- **Distraction scoring** — measure how much the driver is interacting with the phone vs. staying focused; surface a weekly safety report
- **Emergency SOS** — detect sudden stops, sharp deceleration, or explicit voice trigger ("call for help"); auto-share live location with emergency contacts and call 112/911

### Proactive Intelligence
- **Morning drive briefing** — before the first trip of the day, proactively summarize calendar events, weather on the route, and any urgent emails — without being asked
- **Intelligent route suggestions** — cross-reference calendar events with real-time traffic and proactively say "Your 3 PM meeting is 40 minutes away, you should leave in 10 minutes"
- **Fuel / charge level warnings** — via OBD-II or manual input, alert when range is low and suggest the nearest station on the current route
- **Weather alerts on route** — monitor forecast for the destination and warn about rain, ice, or fog ahead

### Vehicle Integration
- **OBD-II diagnostics** — read live vehicle data (speed, RPM, fuel level, fault codes) via Bluetooth OBD-II dongle; explain warning lights in plain language ("your check engine light means a loose gas cap")
- **Mileage & trip statistics** — automated logbook: distance, duration, fuel consumed per trip; useful for tax/expense reporting
- **EV charging optimization** — for electric vehicles, recommend optimal charging windows based on electricity pricing and next day's schedule

### Location Intelligence
- **Parking memory** — automatically remember where the car was parked (GPS pin + photo of surroundings); "Where did I park?" answered instantly
- **Parking finder** — suggest nearby parking options with pricing and availability near the destination
- **Frequent routes analysis** — detect habitual routes (e.g., Monday commute) and proactively report traffic on those routes without needing to ask

### Communication & Collaboration
- **Passenger handoff mode** — when a passenger is present, switch to a shared screen mode; assistant answers questions for both occupants
- **Live location sharing** — share real-time location and ETA with a contact for a current trip ("Share my ETA with Sarah")
- **Summarize missed notifications** — while driving, batch all incoming notifications and read a clean summary at a red light or when asked

### Music & Audio
- **Mood-based music** — infer driver mood from conversation tone and time of day; suggest or auto-play fitting music on Spotify/Apple Music
- **Podcast / audiobook continuity** — remember playback position across sessions; "Resume my audiobook" works even after days
- **Hands-free Spotify / Apple Music control** — native integration beyond app control (skip, like, queue, search by artist or mood)

### Health & Wellness
- **Post-drive debrief** — after a long trip, briefly summarize the drive (distance, time, places visited) and suggest a stretch or hydration reminder
- **Drive streak & habits** — track driving patterns over time; surface insights like average commute time, most visited places, time spent in the car per week

### Business & Productivity
- **Expense logging by voice** — "Log this as a business trip to the downtown client" — creates a trip record with mileage, purpose, and timestamp for expense reporting
- **Voice-to-CRM** — after a sales visit, dictate a quick note ("met with John, follow up Friday about pricing") and sync to a connected CRM
- **Meeting prep on the way** — 5 minutes before a calendar event, auto-brief the driver: who they're meeting, last email exchange, any shared documents

### Platform & Integration
- **CarPlay / Android Auto** — native integration with in-car infotainment systems for full screen and steering wheel button support
- **Smartwatch companion** — glanceable driving stats and one-tap voice trigger from the wrist
- **Home automation on arrival** — trigger smart home scenes when pulling into the driveway ("I'm home" → turn on lights, start the kettle)
- **Multi-language real-time switching** — detect when the driver switches languages mid-conversation and respond in kind without reconfiguration

### On-Device & Offline AI

Driving is one of the strongest use cases for running AI entirely on the device — or in a smart hybrid configuration — because connectivity is inherently unreliable (tunnels, rural roads, underground parking, roaming abroad) and latency is safety-critical.

- **On-device speech recognition (ASR)** — replace cloud STT with a local model (e.g., Whisper.cpp, Apple's on-device Speech framework, Android SpeechRecognizer offline mode) so voice commands work in tunnels and dead zones with zero round-trip delay
- **On-device text-to-speech (TTS)** — use platform-native TTS (iOS AVSpeechSynthesizer, Android TextToSpeech) or a compact neural TTS model as a fallback when the cloud assistant is unreachable; the driver always hears a response
- **On-device LLM for core commands** — run a small quantized model (e.g., Gemma 3, Llama 3.2, Phi-4-mini via llama.cpp or Apple MLX) locally to handle high-frequency, low-complexity requests: navigation, calls, reminders, music control — entirely offline
- **Hybrid routing by request type** — simple, latency-sensitive or offline commands (navigation, calls, reminders) route to the local model; complex, knowledge-heavy requests (web search, email drafting, calendar reasoning) route to the cloud when connectivity is available; the switch is invisible to the driver
- **Connectivity-aware fallback** — monitor network quality in real time; automatically downgrade to on-device mode when signal drops below a threshold and upgrade back to cloud when signal is restored, mid-conversation if needed
- **Privacy-first mode** — offer a setting where all voice audio and personal data never leave the device; on-device ASR + LLM + TTS forms a fully local pipeline with no cloud dependency, which is a strong differentiator for privacy-conscious users and regulated markets
- **Embedded vehicle deployment** — in an automotive OEM context (e.g., Hyundai CCNC / in-vehicle infotainment), the local model could run on the head unit's dedicated NPU rather than the driver's phone, enabling guaranteed sub-100 ms response times regardless of phone hardware or connectivity

