# Background Driving Detection

## Overview

RoadMate automatically detects when you start and stop driving — no manual interaction required. When a drive begins or ends, the app:

1. Shows a system notification with location and time
2. Logs a timestamped event (GPS + address) to a local store
3. Makes the history queryable via the `get_driving_log` voice tool

Detection works while the app is in the background via a persistent Android foreground service.

---

## How It Works

```
Device motion → ActivityRecognition API → DrivingMonitorService
                                              ↓
                              State machine (debounced)
                             /                         \
                    IN_VEHICLE × 2               STILL / ON_FOOT
                          ↓                             ↓
                   _onDrivingStarted()            _onParked()
                          ↓                             ↓
              getBestEffortBackgroundLocation()  (same)
                          ↓
              DrivingLogStore.logEvent()
                          ↓
              System notification shown
```

### State Machine

| Condition | Action |
|-----------|--------|
| `inVehicle` + confidence ≥ 60% | Increment debounce counter |
| Counter reaches 2, not already driving | Set `_isDriving = true`, fire `_onDrivingStarted()` |
| `still` / `onFoot` / `walking` + confidence ≥ 60% | Reset counter |
| Was driving + non-vehicle activity | Set `_isDriving = false`, fire `_onParked()` |
| `running`, `onBicycle`, `unknown`, `tilting` | No state change |

**Debounce**: 2 consecutive `inVehicle` readings (~60–120 s) before logging trip start, reducing false positives from buses and trains.

---

## Architecture

### New Files

#### `lib/services/driving_log_store.dart`
- `DrivingEvent` — model with `id`, `type` ('start'|'park'), `timestamp` (ISO8601 UTC), `lat?`, `lon?`, `address?`
- `DrivingLogStore` — singleton backed by SharedPreferences key `driving_events_v1`
  - Max 500 events (auto-pruned, newest-first)
  - `init()` — load on app start
  - `logEvent(type, location)` — builds address from location map, inserts, saves
  - `getRecentEvents(limit)` — unmodifiable list slice
  - `toolGetDrivingLog(args)` — tool handler returning `{ok, events[], count}`

#### `lib/services/driving_monitor_service.dart`
- `DrivingMonitorService` — singleton
- Subscribes to `ActivityRecognition().activityStream(runForegroundService: false)`
- Manages its own `FlutterLocalNotificationsPlugin` on channel `roadmate_driving_monitor`
- Notification IDs: 9001 (trip start), 9002 (parked)
- Notification body format: `"Trip started at Market St, San Francisco • 9:31 AM"`

### Modified Files

| File | Change |
|------|--------|
| `pubspec.yaml` | Added `activity_recognition_flutter: ^6.0.0` |
| `AndroidManifest.xml` | Added `ACTIVITY_RECOGNITION`, `FOREGROUND_SERVICE_LOCATION` permissions; FGS type changed to `microphone\|location` |
| `ios/Runner/Info.plist` | Added `NSMotionUsageDescription`; added `location` to `UIBackgroundModes` |
| `lib/main.dart` | Init driving log + monitor at startup; persistent FGS; updated start/stop FGS methods; notification Stop button wiring; `get_driving_log` tool entry |
| `lib/config.dart` | Added `get_driving_log` tool schema |

---

## Persistent Foreground Service

The foreground service now starts at **app launch** (not only during voice mode), keeping the process alive for activity recognition callbacks in the background.

### Notification States

| App State | Notification Text |
|-----------|-------------------|
| Idle / background | "RoadMate — Running in background" |
| Voice mode active | "RoadMate Voice Assistant — Voice mode is active" + Stop button |

### Why not stop the service after voice mode?

Stopping the service would kill the process on many Android devices, ending activity recognition. `_stopForegroundService()` now calls `updateService()` to revert the notification rather than `stopService()`.

### Boot persistence

`autoRunOnBoot: true` — if the device restarts, the foreground service (and driving monitor) automatically resumes.

---

## Voice Tool

**`get_driving_log`** — returns recent driving events.

```
User: "where did I park last?"
  → AI calls get_driving_log(limit: 5)
  → Returns last 5 events with type, timestamp, address
  → AI: "You parked on Main St, Oakland at 3:15 PM"
```

Parameters:
- `limit` (integer, optional) — max events to return, default 10, max 50

Response shape:
```json
{
  "ok": true,
  "events": [
    {
      "id": "uuid",
      "type": "park",
      "timestamp": "2026-02-16T15:15:00Z",
      "lat": 37.8044,
      "lon": -122.2712,
      "address": "Main St, Oakland, CA"
    }
  ],
  "count": 1
}
```

---

## Platform Notes

### Android
- Requires `ACTIVITY_RECOGNITION` permission (Android 10+ / API 29+) — requested at runtime on `DrivingMonitorService.start()`
- `com.google.android.gms.permission.ACTIVITY_RECOGNITION` also declared for older GMS builds
- `FOREGROUND_SERVICE_LOCATION` required for geolocator calls from within the FGS context on Android 14+

### iOS
- Uses CoreMotion (`CMMotionActivityManager`) via `activity_recognition_flutter`
- `NSMotionUsageDescription` in `Info.plist` for permission prompt
- `location` background mode enables background location access for GPS logging

---

## Testing on a Physical Device

1. Grant **Physical Activity** / **Motion & Fitness** permission when prompted
2. Drive for 2+ minutes → "Trip started" notification appears + event logged
3. Park and walk away → "You parked" notification appears + event logged
4. Minimize app → detection continues (persistent FGS)
5. Ask voice: *"where did I park last?"* → AI calls `get_driving_log`, reads address and time
