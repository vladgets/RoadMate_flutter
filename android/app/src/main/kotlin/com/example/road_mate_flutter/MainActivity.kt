package com.example.road_mate_flutter

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.roadmate.ai/assistant"
    private var isAssistLaunch = false
    private var assistQuery: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Check intent before calling super
        checkAssistIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        checkAssistIntent(intent)
    }

    private fun checkAssistIntent(intent: Intent?) {
        if (intent == null) return

        val action = intent.action
        isAssistLaunch = action == Intent.ACTION_ASSIST ||
                         action == Intent.ACTION_VOICE_COMMAND ||
                         action == Intent.ACTION_SEARCH_LONG_PRESS

        if (isAssistLaunch) {
            // Try to get query from intent extras
            assistQuery = intent.getStringExtra(Intent.EXTRA_ASSIST_CONTEXT)
                ?: intent.getStringExtra("query")
                ?: intent.getStringExtra(Intent.EXTRA_TEXT)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAssistInfo" -> {
                    val info = mapOf(
                        "isAssist" to isAssistLaunch,
                        "query" to assistQuery
                    )
                    // Clear after reading so subsequent calls return false
                    val response = info.toMap()
                    isAssistLaunch = false
                    assistQuery = null
                    result.success(response)
                }
                "isAssistLaunch" -> {
                    val wasAssist = isAssistLaunch
                    isAssistLaunch = false
                    result.success(wasAssist)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
