import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

/// Status of the server-side WhatsApp (Baileys) session.
class WhatsAppBaileysStatus {
  const WhatsAppBaileysStatus({
    required this.connected,
    required this.connecting,
    this.qrBase64,
    this.pairingCode,
    this.phone,
    this.lastError,
  });

  final bool connected;
  final bool connecting;
  final String? qrBase64;
  final String? pairingCode;
  final String? phone;
  final String? lastError;

  static WhatsAppBaileysStatus disconnected() =>
      const WhatsAppBaileysStatus(connected: false, connecting: false);

  static WhatsAppBaileysStatus fromJson(Map<String, dynamic> j) =>
      WhatsAppBaileysStatus(
        connected: j['connected'] as bool? ?? false,
        connecting: j['connecting'] as bool? ?? false,
        qrBase64: j['qrBase64'] as String?,
        pairingCode: j['pairingCode'] as String?,
        phone: j['phone'] as String?,
        lastError: j['lastError'] as String?,
      );
}

/// Manages the server-side WhatsApp Baileys session.
/// Sends messages fully automatically — no user tap required.
class WhatsAppBaileysService {
  WhatsAppBaileysService._();
  static final instance = WhatsAppBaileysService._();

  static String get _base => Config.serverUrl;

  Future<String> _clientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(Config.prefKeyClientId) ?? 'default';
  }

  Map<String, String> get _headers => {'Content-Type': 'application/json'};

  // ── Public API ────────────────────────────────────────────────────────────

  /// Get current session status.
  Future<WhatsAppBaileysStatus> getStatus() async {
    try {
      final id = await _clientId();
      final res = await http
          .get(Uri.parse('$_base/whatsapp/status?client_id=$id'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return WhatsAppBaileysStatus.disconnected();
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return WhatsAppBaileysStatus.fromJson(body);
    } catch (e) {
      debugPrint('[WA-Baileys] getStatus error: $e');
      return WhatsAppBaileysStatus.disconnected();
    }
  }

  /// Initiate pairing — server starts Baileys and will emit a QR.
  /// Poll getStatus() every few seconds to receive the QR image.
  Future<bool> connect() async {
    try {
      final id = await _clientId();
      final res = await http
          .post(
            Uri.parse('$_base/whatsapp/connect'),
            headers: _headers,
            body: jsonEncode({'client_id': id}),
          )
          .timeout(const Duration(seconds: 15));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('[WA-Baileys] connect error: $e');
      return false;
    }
  }

  /// Request a text pairing code as an alternative to QR scanning.
  /// [phone] must be in international format, digits only (e.g. "15551234567").
  /// Returns the code (e.g. "ABCD-EFGH") or null on failure.
  Future<String?> requestPairingCode(String phone) async {
    try {
      final id = await _clientId();
      final res = await http
          .post(
            Uri.parse('$_base/whatsapp/pairing-code'),
            headers: _headers,
            body: jsonEncode({'client_id': id, 'phone': phone}),
          )
          .timeout(const Duration(seconds: 40));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['ok'] == true) return body['pairingCode'] as String?;
      debugPrint('[WA-Baileys] requestPairingCode server error: ${body['error']}');
      return null;
    } catch (e) {
      debugPrint('[WA-Baileys] requestPairingCode error: $e');
      return null;
    }
  }

  /// Send a WhatsApp message to [phone] (international digits, e.g. "15551234567").
  /// Returns true on success.
  Future<bool> send({required String phone, required String message}) async {
    try {
      final id = await _clientId();
      final res = await http
          .post(
            Uri.parse('$_base/whatsapp/send'),
            headers: _headers,
            body: jsonEncode({
              'client_id': id,
              'phone': phone,
              'message': message,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return body['ok'] == true;
    } catch (e) {
      debugPrint('[WA-Baileys] send error: $e');
      return false;
    }
  }

  /// Disconnect and clear saved credentials from the server.
  Future<void> disconnect() async {
    try {
      final id = await _clientId();
      await http
          .post(
            Uri.parse('$_base/whatsapp/disconnect'),
            headers: _headers,
            body: jsonEncode({'client_id': id}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('[WA-Baileys] disconnect error: $e');
    }
  }
}
