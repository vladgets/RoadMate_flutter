# Background Driving Detection

## Overview

RoadMate automatically detects when you start and stop driving — no manual interaction required. When a drive begins or ends, the app:

1. Shows a system notification with location and time
2. Logs a timestamped event (GPS + address) to a local store
3. Makes the history queryable via the `get_driving_log` voice tool

Detection is **best-effort**: it works as long as the app process is alive in the background. The process is not kept alive by a persistent foreground service, so aggressive Android OEMs (Samsung, Xiaomi, etc.) may kill it over time.

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

### Key Files

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

#### `lib/ui/driving_log_screen.dart`
- Developer screen: Settings → Developer → Driving Log
- Lists all events newest-first with icon, label, time, address
- Tap row or map icon → opens Maps app pinned to that location
- AppBar has Refresh and Clear buttons

### Modified Files

| File | Change |
|------|--------|
| `pubspec.yaml` | Added `activity_recognition_flutter: ^6.0.0` |
| `AndroidManifest.xml` | Added `ACTIVITY_RECOGNITION`, `FOREGROUND_SERVICE_LOCATION` permissions |
| `ios/Runner/Info.plist` | Added `NSMotionUsageDescription`; added `location` to `UIBackgroundModes` |
| `lib/main.dart` | Init driving log + monitor at startup; `get_driving_log` tool entry |
| `lib/config.dart` | Added `get_driving_log` tool schema |
| `lib/ui/developer_area_menu.dart` | Added Driving Log entry |

---

## Background Detection Reliability

The monitor subscribes to the activity stream when the app launches and keeps running as long as the process is alive. There is **no persistent foreground service** for driving detection — that would require a permanent notification icon in the Android status bar, which is undesirable UX.

### Practical expectations

| Scenario | Detection works? |
|----------|-----------------|
| App recently used, phone has free RAM | ✅ Yes |
| 10–30 min after backgrounding on Pixel | ✅ Likely |
| 10–30 min on Samsung (default battery settings) | ⚠️ Maybe |
| Phone locked overnight | ❌ Process likely killed |
| User force-stopped the app | ❌ No |

### Foreground service and notification icon

The foreground service (FGS) is only active **during voice mode**:

| App State | FGS | Notification icon |
|-----------|-----|-------------------|
| Idle / background | ❌ Not running | No icon |
| Voice mode active | ✅ Running | Icon visible + "Stop" button |

This means driving detection notifications only appear if the process happens to be alive at the moment of detection. If you want guaranteed detection at the cost of a permanent notification icon, a persistent FGS can be re-enabled (one-line change in `main.dart`).

### Future improvement options

- **Android**: `ActivityRecognitionClient` with `PendingIntent` + manifest-declared `BroadcastReceiver` — delivers updates even when the app process is killed, no FGS required. Needs native platform channel code.
- **iOS**: `CLLocationManager` significant-change monitoring — wakes the app silently for large location changes even when killed. No notification icon ever required on iOS.

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
- `FOREGROUND_SERVICE_LOCATION` declared for geolocator calls if a FGS is ever re-enabled

### iOS
- Uses CoreMotion (`CMMotionActivityManager`) via `activity_recognition_flutter`
- `NSMotionUsageDescription` in `Info.plist` for permission prompt
- `location` in `UIBackgroundModes` enables background location access for GPS logging
- No persistent notification required — iOS handles background work without FGS

---

## Testing on a Physical Device

1. Grant **Physical Activity** / **Motion & Fitness** permission when prompted
2. Keep the app recently active (don't force-stop it)
3. Drive for 2+ minutes → "Trip started" notification appears + event logged
4. Park and walk away → "You parked" notification appears + event logged
5. Check Settings → Developer → Driving Log to verify events with location
6. Ask voice: *"where did I park last?"* → AI calls `get_driving_log`, reads address and time
