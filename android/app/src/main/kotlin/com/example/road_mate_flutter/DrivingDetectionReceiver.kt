package com.example.road_mate_flutter

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.location.LocationManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.ActivityRecognitionResult
import com.google.android.gms.location.DetectedActivity

/**
 * Manifest-declared BroadcastReceiver for activity recognition events.
 *
 * Registered with its own PendingIntent (request code 77) in MainActivity,
 * independently of the activity_recognition_flutter plugin's registration.
 * Android wakes the app process briefly to deliver the broadcast — no
 * persistent foreground service required.
 *
 * When Flutter is alive (it updates [KEY_FLUTTER_ALIVE_TS] every ~60 s),
 * this receiver does nothing — the Dart DrivingMonitorService handles it.
 * When Flutter is dead (ts is stale), this receiver:
 *   1. Runs the driving state machine in SharedPreferences
 *   2. Shows a notification via Android NotificationManager
 *   3. Appends a pending event to [KEY_PENDING_EVENTS] for Flutter to pick
 *      up the next time the app is launched.
 */
class DrivingDetectionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "DrivingDetection"

        const val PREFS_NAME = "roadmate_native_bridge"
        const val KEY_FLUTTER_ALIVE_TS = "flutter_alive_ts"
        private const val KEY_IS_DRIVING = "native_is_driving"
        private const val KEY_VEHICLE_COUNT = "native_vehicle_count"
        const val KEY_PENDING_EVENTS = "native_pending_events"
        private const val KEY_LAST_VEH_LAT = "native_last_veh_lat"
        private const val KEY_LAST_VEH_LON = "native_last_veh_lon"

        // Flutter must have sent a heartbeat within this window or native takes over.
        private const val FLUTTER_ALIVE_WINDOW_MS = 120_000L

        private const val DEBOUNCE_COUNT = 2
        private const val MIN_CONFIDENCE = 60

        private const val NOTIF_CHANNEL_ID = "roadmate_driving_monitor"
        private const val NOTIF_CHANNEL_NAME = "Driving Monitor"
        private const val NOTIF_ID_START = 9001
        private const val NOTIF_ID_PARK = 9002
    }

    override fun onReceive(context: Context, intent: Intent) {
        val result = ActivityRecognitionResult.extractResult(intent) ?: return
        val mostLikely = result.probableActivities.maxByOrNull { it.confidence } ?: return

        Log.d(TAG, "Activity: type=${mostLikely.type} confidence=${mostLikely.confidence}")

        // If Flutter is alive and recently handling events, do nothing here.
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val flutterAliveTs = prefs.getLong(KEY_FLUTTER_ALIVE_TS, 0L)
        if (System.currentTimeMillis() - flutterAliveTs < FLUTTER_ALIVE_WINDOW_MS) {
            Log.d(TAG, "Flutter alive — skipping native handling")
            return
        }

        if (mostLikely.confidence < MIN_CONFIDENCE) return

        val isDriving = prefs.getBoolean(KEY_IS_DRIVING, false)
        var vehicleCount = prefs.getInt(KEY_VEHICLE_COUNT, 0)

        when (mostLikely.type) {
            DetectedActivity.IN_VEHICLE -> {
                vehicleCount++
                prefs.edit().putInt(KEY_VEHICLE_COUNT, vehicleCount).apply()
                // Snapshot the current location so park logging uses the spot
                // where the car stopped, not where the person walked to later.
                snapshotVehicleLocation(context, prefs)
                if (vehicleCount >= DEBOUNCE_COUNT && !isDriving) {
                    prefs.edit().putBoolean(KEY_IS_DRIVING, true).apply()
                    onDrivingStarted(context, prefs)
                }
            }
            DetectedActivity.STILL,
            DetectedActivity.ON_FOOT,
            DetectedActivity.WALKING -> {
                prefs.edit().putInt(KEY_VEHICLE_COUNT, 0).apply()
                if (isDriving) {
                    prefs.edit().putBoolean(KEY_IS_DRIVING, false).apply()
                    onParked(context, prefs)
                }
            }
            else -> Unit
        }
    }

    private fun onDrivingStarted(context: Context, prefs: SharedPreferences) {
        Log.d(TAG, "Drive started (native)")
        addPendingEvent(prefs, "start")
        showNotification(context, NOTIF_ID_START, "Trip started", "Your drive has begun")
    }

    private fun onParked(context: Context, prefs: SharedPreferences) {
        Log.d(TAG, "Parked (native)")
        addPendingEvent(prefs, "park")
        showNotification(context, NOTIF_ID_PARK, "You parked", "Your drive has ended")
    }

    private fun addPendingEvent(prefs: SharedPreferences, type: String) {
        val ts = System.currentTimeMillis()
        val existing = prefs.getString(KEY_PENDING_EVENTS, "[]") ?: "[]"

        // For park events, include the last-vehicle location so Flutter can
        // log the correct address (where the car stopped, not current location).
        val newEvent = if (type == "park") {
            val lat = prefs.getFloat(KEY_LAST_VEH_LAT, Float.NaN)
            val lon = prefs.getFloat(KEY_LAST_VEH_LON, Float.NaN)
            if (!lat.isNaN() && !lon.isNaN()) {
                """{"type":"$type","ts":$ts,"lat":$lat,"lon":$lon}"""
            } else {
                """{"type":"$type","ts":$ts}"""
            }
        } else {
            """{"type":"$type","ts":$ts}"""
        }

        val updated = if (existing == "[]") "[$newEvent]" else "${existing.dropLast(1)},$newEvent]"
        prefs.edit().putString(KEY_PENDING_EVENTS, updated).apply()
        Log.d(TAG, "Pending event queued: $newEvent")
    }

    @SuppressLint("MissingPermission")
    private fun snapshotVehicleLocation(context: Context, prefs: SharedPreferences) {
        try {
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            for (provider in providers) {
                val loc = lm.getLastKnownLocation(provider) ?: continue
                prefs.edit()
                    .putFloat(KEY_LAST_VEH_LAT, loc.latitude.toFloat())
                    .putFloat(KEY_LAST_VEH_LON, loc.longitude.toFloat())
                    .apply()
                Log.d(TAG, "Vehicle location snapshot: ${loc.latitude}, ${loc.longitude}")
                return
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not snapshot vehicle location: $e")
        }
    }

    private fun showNotification(context: Context, id: Int, title: String, text: String) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIF_CHANNEL_ID,
                NOTIF_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_DEFAULT
            )
            nm.createNotificationChannel(channel)
        }

        val notification = NotificationCompat.Builder(context, NOTIF_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .build()

        nm.notify(id, notification)
        Log.d(TAG, "Notification shown: $title — $text")
    }
}
