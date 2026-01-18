import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Менеджер для управления Realtime сессией и отправки сообщений
class RealtimeSessionManager {
  static RealtimeSessionManager? _instance;
  static RealtimeSessionManager get instance {
    _instance ??= RealtimeSessionManager._();
    return _instance!;
  }

  RealtimeSessionManager._();

  RTCDataChannel? _dataChannel;
  Future<void> Function()? _connectCallback;
  final List<String> _pendingMessages = [];
  bool _isConnecting = false;
  final Duration _connectionTimeout = const Duration(seconds: 30);

  /// Зарегистрировать data channel
  void registerDataChannel(RTCDataChannel? dc) {
    _dataChannel = dc;
    if (dc != null) {
      // Если есть ожидающие сообщения, отправляем их
      _processPendingMessages();
    } else {
      // Очищаем pending messages при отключении
      _pendingMessages.clear();
    }
  }

  /// Зарегистрировать callback для подключения
  void registerConnectCallback(Future<void> Function() connectFn) {
    _connectCallback = connectFn;
  }

  /// Проверить, подключена ли сессия
  bool isConnected() {
    return _dataChannel != null &&
        _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen;
  }

  /// Отправить текстовое сообщение в Realtime сессию
  /// Возвращает true если сообщение успешно отправлено, false в противном случае
  Future<bool> sendTextMessage(String text) async {
    // Если сессия уже подключена, отправляем сразу
    if (isConnected()) {
      return await _sendMessage(text);
    }

    // Если сессия не подключена, добавляем в очередь и пытаемся подключиться
    _pendingMessages.add(text);

    // Если уже идет процесс подключения, просто ждем
    if (_isConnecting) {
      return await _waitForConnectionAndSend();
    }

    // Запускаем новую сессию
    if (_connectCallback == null) {
      debugPrint('[RealtimeSessionManager] Connect callback not registered');
      _pendingMessages.removeLast(); // Удаляем сообщение из очереди
      return false;
    }

    _isConnecting = true;
    try {
      // Запускаем подключение
      await _connectCallback!();
      
      // Ждем подключения и отправляем сообщения
      return await _waitForConnectionAndSend();
    } catch (e) {
      debugPrint('[RealtimeSessionManager] Failed to connect: $e');
      _pendingMessages.clear();
      return false;
    } finally {
      _isConnecting = false;
    }
  }

  /// Ожидать подключения и отправить ожидающие сообщения
  Future<bool> _waitForConnectionAndSend() async {
    final startTime = DateTime.now();
    
    // Ждем пока data channel откроется
    while (!isConnected()) {
      if (DateTime.now().difference(startTime) > _connectionTimeout) {
        debugPrint('[RealtimeSessionManager] Connection timeout');
        _pendingMessages.clear();
        return false;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Отправляем все ожидающие сообщения
    return await _processPendingMessages();
  }

  /// Обработать и отправить все ожидающие сообщения
  Future<bool> _processPendingMessages() async {
    if (!isConnected() || _pendingMessages.isEmpty) {
      return false;
    }

    bool allSent = true;
    final messagesToSend = List<String>.from(_pendingMessages);
    _pendingMessages.clear();

    for (final message in messagesToSend) {
      final sent = await _sendMessage(message);
      if (!sent) {
        allSent = false;
      }
    }

    return allSent;
  }

  /// Отправить одно сообщение через data channel
  Future<bool> _sendMessage(String text) async {
    if (!isConnected()) {
      return false;
    }

    try {
      // Формируем сообщение согласно Realtime API
      final payload = {
        'type': 'conversation.item.create',
        'item': {
          'type': 'message',
          'role': 'user',
          'content': [
            {
              'type': 'input_text',
              'text': text,
            }
          ]
        }
      };

      _dataChannel!.send(RTCDataChannelMessage(jsonEncode(payload)));

      // Запрашиваем ответ от модели
      _dataChannel!.send(
        RTCDataChannelMessage(jsonEncode({'type': 'response.create'})),
      );

      debugPrint('[RealtimeSessionManager] Message sent: $text');
      return true;
    } catch (e) {
      debugPrint('[RealtimeSessionManager] Failed to send message: $e');
      return false;
    }
  }
}
