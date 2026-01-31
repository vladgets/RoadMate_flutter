import 'package:flutter/material.dart';
import 'services/vocal_bridge_service.dart';
import 'services/reminders.dart';
import 'ui/main_settings_menu.dart';

/// VocalBridge-powered voice assistant page.
/// Uses LiveKit via VocalBridge instead of direct OpenAI WebRTC.
class VocalBridgePage extends StatefulWidget {
  const VocalBridgePage({super.key});

  @override
  State<VocalBridgePage> createState() => _VocalBridgePageState();
}

class _VocalBridgePageState extends State<VocalBridgePage> with WidgetsBindingObserver {
  // VocalBridge API key - for hackathon only
  // In production, get token from your backend instead
  static const _apiKey = 'vb_fVxcZYHBfAgBYPmwmCLEa99wgy0m_eVvgkL5lNbTipk';

  late final VocalBridgeService _service;

  String _status = 'Initializing...';
  String? _error;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _service = VocalBridgeService(apiKey: _apiKey);

    // Set up callbacks
    _service.onStatusChanged = (status) {
      if (mounted) setState(() => _status = status);
    };

    _service.onError = (error) {
      if (mounted) setState(() => _error = error);
    };

    _service.onConnectionChanged = (connected) {
      if (mounted) setState(() {});
    };

    // Initialize service and auto-connect
    _initAndConnect();
  }

  Future<void> _initAndConnect() async {
    try {
      // Initialize reminders service
      await RemindersService.instance.init();

      // Initialize VocalBridge service
      await _service.init();

      setState(() {
        _initialized = true;
        _status = 'Ready. Tap to connect.';
      });

      // Auto-connect on launch
      await _service.connect();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _status = 'Initialization failed';
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto-reconnect when app returns to foreground
    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;
      if (_service.isConnected || _service.isConnecting) return;
      if (_initialized) {
        _service.connect();
      }
    }
  }

  Future<void> _toggle() async {
    if (_service.isConnecting) return;

    setState(() => _error = null);

    try {
      await _service.toggle();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _service.isConnected;
    final isConnecting = _service.isConnecting;
    final isBusy = isConnecting || !_initialized;

    final label = isConnected ? "Tap to stop" : "Tap to talk";
    final icon = isConnected ? Icons.stop_circle : Icons.mic;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'VocalBridge',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Status indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? Colors.green.withOpacity(0.2)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConnected ? Colors.green : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isConnected ? 'Connected' : 'Disconnected',
                        style: TextStyle(
                          color: isConnected ? Colors.green : Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Status text
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),

                // Error text
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],

                const SizedBox(height: 48),

                // Main button
                GestureDetector(
                  onTap: isBusy ? null : _toggle,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected ? Colors.redAccent : Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: (isConnected ? Colors.redAccent : Colors.white)
                              .withOpacity(0.3),
                          blurRadius: 24,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                    child: isBusy
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.black54,
                              strokeWidth: 3,
                            ),
                          )
                        : Icon(
                            icon,
                            size: 72,
                            color: isConnected ? Colors.white : Colors.black,
                          ),
                  ),
                ),

                const SizedBox(height: 24),

                // Label
                Text(
                  isBusy ? "Connecting..." : label,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),

                const SizedBox(height: 8),

                // Subtitle
                Text(
                  isConnected ? "Speak now" : (isBusy ? "Please wait" : "Not connected"),
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),

                const SizedBox(height: 48),

                // Powered by badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Powered by VocalBridge + LiveKit',
                    style: TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
