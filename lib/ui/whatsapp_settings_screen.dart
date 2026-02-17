import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/whatsapp_baileys_service.dart';

class WhatsAppSettingsScreen extends StatefulWidget {
  const WhatsAppSettingsScreen({super.key});

  @override
  State<WhatsAppSettingsScreen> createState() => _WhatsAppSettingsScreenState();
}

class _WhatsAppSettingsScreenState extends State<WhatsAppSettingsScreen> {
  static const _pollInterval = Duration(seconds: 3);

  WhatsAppBaileysStatus _status = WhatsAppBaileysStatus.disconnected();
  bool _loading = true;
  bool _actionInProgress = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _refresh(silent: true));
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);

    final s = await WhatsAppBaileysService.instance.getStatus();
    if (!mounted) return;

    setState(() {
      _status = s;
      _loading = false;
    });

    // Keep polling while connecting / waiting for QR scan.
    if (!s.connected) {
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _connect() async {
    setState(() => _actionInProgress = true);
    await WhatsAppBaileysService.instance.connect();
    await _refresh(silent: true);
    setState(() => _actionInProgress = false);
    _startPolling();
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disconnect WhatsApp?'),
        content: const Text(
          'Your WhatsApp session will be removed from the server. '
          'You will need to scan a QR code again to reconnect.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionInProgress = true);
    await WhatsAppBaileysService.instance.disconnect();
    await _refresh(silent: true);
    setState(() => _actionInProgress = false);
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildStatusCard() {
    final connected = _status.connected;
    final color = connected ? Colors.green.shade600 : Colors.grey.shade500;
    final icon = connected ? Icons.check_circle : Icons.radio_button_unchecked;
    final label = connected
        ? 'Connected${_status.phone != null ? " · +${_status.phone}" : ""}'
        : 'Not connected';

    return Card(
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WhatsApp Auto-Send',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(label, style: TextStyle(color: color, fontSize: 13)),
                ],
              ),
            ),
            if (connected)
              FilledButton.tonal(
                onPressed: _actionInProgress ? null : _disconnect,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade50,
                  foregroundColor: Colors.red.shade700,
                ),
                child: const Text('Disconnect'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrSection() {
    if (_status.connected) return const SizedBox.shrink();

    final hasQr = _status.qrBase64 != null;
    final isConnecting = _status.connecting;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          if (!hasQr && !isConnecting && _status.lastError == null) ...[
            const SizedBox(height: 8),
            const Text(
              'Pair your WhatsApp account so RoadMate can send messages '
              'automatically without any user action.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _actionInProgress ? null : _connect,
                icon: const Icon(Icons.qr_code),
                label: const Text('Connect WhatsApp'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366), // WhatsApp green
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],

          if (_status.lastError != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade400, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _status.lastError!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _actionInProgress ? null : _connect,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],

          if (isConnecting && !hasQr && _status.lastError == null) ...[
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Starting connection…'),
          ],

          if (hasQr) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF25D366), width: 2),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      base64Decode(_status.qrBase64!),
                      width: 260,
                      height: 260,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Open WhatsApp → ⋮ Menu → Linked devices → Link a device',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Waiting for scan…',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    if (!_status.connected) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: Colors.green.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.green),
                  SizedBox(width: 8),
                  Text(
                    'Ready to send automatically',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'RoadMate can now send WhatsApp messages on your behalf '
                'without opening the app. The session lives on the server '
                'and reconnects automatically.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp Auto-Send'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildStatusCard(),
                _buildQrSection(),
                _buildInfoSection(),
              ],
            ),
    );
  }
}
