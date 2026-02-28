import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Service to detect and handle assistant/voice activation launches.
///
/// On Android: Detects ASSIST intent (long-press home button)
/// On iOS: Detects Siri Shortcut launch with voice_mode parameter
class AssistantLaunchService {
  static final AssistantLaunchService instance = AssistantLaunchService._();
  AssistantLaunchService._();

  static const _channel = MethodChannel('com.roadmate.ai/assistant');

  bool _launchedAsAssistant = false;
  String? _initialQuery;

  /// Whether the app was launched via assistant action (long-press home, Siri, etc.)
  bool get launchedAsAssistant => _launchedAsAssistant;

  /// Initial query passed from assistant (if any)
  String? get initialQuery => _initialQuery;

  /// Initialize and check launch mode
  Future<void> init() async {
    if (Platform.isAndroid) {
      await _checkAndroidAssistLaunch();
    } else if (Platform.isIOS) {
      await _checkIOSShortcutLaunch();
    }
  }

  /// Check if launched via Android ASSIST intent
  Future<void> _checkAndroidAssistLaunch() async {
    try {
      final result = await _channel.invokeMethod<Map>('getAssistInfo');
      if (result != null) {
        _launchedAsAssistant = result['isAssist'] == true;
        _initialQuery = result['query'] as String?;
        debugPrint('[AssistantLaunch] Android assist launch: $_launchedAsAssistant, query: $_initialQuery');
      }
    } on MissingPluginException {
      // Native code not implemented yet, check via alternative method
      debugPrint('[AssistantLaunch] Method channel not available, using fallback');
      _launchedAsAssistant = false;
    } catch (e) {
      debugPrint('[AssistantLaunch] Error checking assist launch: $e');
      _launchedAsAssistant = false;
    }
  }

  /// Check if launched via iOS Siri Shortcut
  Future<void> _checkIOSShortcutLaunch() async {
    try {
      final result = await _channel.invokeMethod<Map>('getShortcutInfo');
      if (result != null) {
        _launchedAsAssistant = result['isShortcut'] == true;
        _initialQuery = result['query'] as String?;
        debugPrint('[AssistantLaunch] iOS shortcut launch: $_launchedAsAssistant, query: $_initialQuery');
      }
    } on MissingPluginException {
      debugPrint('[AssistantLaunch] iOS method channel not available');
      _launchedAsAssistant = false;
    } catch (e) {
      debugPrint('[AssistantLaunch] Error checking shortcut launch: $e');
      _launchedAsAssistant = false;
    }
  }

  /// Reset launch state (call after handling the assistant launch)
  void clearLaunchState() {
    _launchedAsAssistant = false;
    _initialQuery = null;
  }
}
