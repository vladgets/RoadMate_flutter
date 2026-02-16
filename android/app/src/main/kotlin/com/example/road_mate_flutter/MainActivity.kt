package com.example.road_mate_flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.ComponentName
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.service.quicksettings.TileService
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var buttonEventSink: EventChannel.EventSink? = null

    // Stores a trigger event that arrived before Flutter subscribed to the channel.
    // Replayed when onListen fires.
    private var pendingButtonEvent: String? = null

    private val buttonReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            Log.d("RoadMateA11y", "MainActivity: broadcast received action=${intent.action} sink=${if (buttonEventSink != null) "set" else "NULL"}")
            if (buttonEventSink != null) {
                buttonEventSink?.success("double_tap")
                Log.d("RoadMateA11y", "MainActivity: sent double_tap to Flutter EventChannel")
            } else {
                // Flutter hasn't subscribed yet — store for replay when onListen fires
                Log.w("RoadMateA11y", "MainActivity: EventSink null — storing as pendingButtonEvent")
                pendingButtonEvent = "double_tap"
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d("RoadMateA11y", "MainActivity: configureFlutterEngine")

        // Register voice-trigger BroadcastReceiver unconditionally so it is
        // always active for the lifetime of the Activity, regardless of whether
        // the Flutter EventChannel stream has been opened yet.
        val filter = IntentFilter("com.example.road_mate_flutter.VOICE_TILE_TAPPED")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(buttonReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(buttonReceiver, filter)
        }
        Log.d("RoadMateA11y", "MainActivity: BroadcastReceiver registered (always-on)")

        // If this Activity was created fresh (app killed) with a voice-trigger intent,
        // the intent arrives as getIntent() not onNewIntent — store it as pending so it
        // is replayed when Flutter subscribes to the EventChannel.
        pendingButtonEvent = when (intent?.action) {
            "com.example.road_mate_flutter.TRIGGER_VOICE" -> "double_tap"
            "com.example.road_mate_flutter.STOP_VOICE"    -> "stop_voice"
            else -> null
        }
        if (pendingButtonEvent != null) {
            Log.d("RoadMateA11y", "MainActivity: initial intent ${intent?.action} → pending=$pendingButtonEvent")
        }

        // Move-to-background channel — lets Flutter minimize the app after triggering voice
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "roadmate/navigation")
            .setMethodCallHandler { call, result ->
                if (call.method == "moveToBackground") {
                    moveTaskToBack(true)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // Tile state channel — Flutter tells the tile whether voice is active so the
        // tile can show as selected/unselected and toggle correctly on next tap.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "roadmate/tile")
            .setMethodCallHandler { call, result ->
                if (call.method == "setActive") {
                    val active = call.argument<Boolean>("active") ?: false
                    VoiceTileService.isVoiceActive = active
                    Log.d("RoadMateA11y", "MainActivity: tile state → active=$active")
                    // Ask the system to call onStartListening so the tile refreshes (API 30+)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        TileService.requestListeningState(
                            this,
                            ComponentName(this, VoiceTileService::class.java)
                        )
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // App launcher channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app_launcher")
            .setMethodCallHandler { call, result ->
                if (call.method == "launchApp") {
                    val pkg = call.argument<String>("package") ?: run {
                        result.success(false); return@setMethodCallHandler
                    }
                    val intent = packageManager.getLaunchIntentForPackage(pkg)
                    if (intent != null) {
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                } else {
                    result.notImplemented()
                }
            }

        // Voice trigger EventChannel — receives Quick Settings tile taps (and
        // accessibility button double-taps on older Android versions).
        // The BroadcastReceiver is already registered above; onListen/onCancel
        // only manage the EventSink reference used to forward events to Flutter.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "roadmate/accessibility_button")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink) {
                    Log.d("RoadMateA11y", "MainActivity: EventChannel onListen — sink ready")
                    buttonEventSink = sink
                    // Replay any event that arrived before Flutter subscribed
                    if (pendingButtonEvent != null) {
                        Log.d("RoadMateA11y", "MainActivity: replaying pending event: $pendingButtonEvent")
                        sink.success(pendingButtonEvent)
                        pendingButtonEvent = null
                    }
                }

                override fun onCancel(args: Any?) {
                    Log.d("RoadMateA11y", "MainActivity: EventChannel onCancel — clearing sink")
                    buttonEventSink = null
                }
            })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val event = when (intent.action) {
            "com.example.road_mate_flutter.TRIGGER_VOICE" -> "double_tap"
            "com.example.road_mate_flutter.STOP_VOICE"    -> "stop_voice"
            else -> null
        } ?: return
        Log.d("RoadMateA11y", "MainActivity: onNewIntent ${intent.action} → $event")
        if (buttonEventSink != null) {
            buttonEventSink?.success(event)
            Log.d("RoadMateA11y", "MainActivity: forwarded $event to Flutter")
        } else {
            pendingButtonEvent = event
            Log.w("RoadMateA11y", "MainActivity: sink null — stored $event as pending")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(buttonReceiver) } catch (_: Exception) {}
        Log.d("RoadMateA11y", "MainActivity: onDestroy — BroadcastReceiver unregistered")
    }
}
