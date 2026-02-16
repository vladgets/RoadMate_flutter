package com.example.road_mate_flutter

import android.util.Log
import slayer.accessibility.service.flutter_accessibility_service.AccessibilityListener

class RoadMateAccessibilityService : AccessibilityListener() {

    override fun onServiceConnected() {
        try {
            super.onServiceConnected()
        } catch (e: Exception) {
            // super.onServiceConnected() crashes when FlutterEngineCache is empty
            // (e.g. service reconnected after process restart). Safe to ignore.
            Log.w("RoadMateA11y", "super.onServiceConnected non-fatal: $e")
        }
    }
}
