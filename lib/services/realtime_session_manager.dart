import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'realtime_connection_service.dart';

/// Менеджер для управления Realtime сессией и отправки сообщений
/// 
/// Этот класс служит интерфейсом для отправки сообщений в Realtime сессию.
/// Он использует RealtimeConnectionService для фактического подключения,
/// что позволяет работать в фоновом режиме без зависимости от UI.
class RealtimeSessionManager {
  static RealtimeSessionManager? _instance;
  static RealtimeSessionManager get instance {
    _instance ??= RealtimeSessionManager._();
    return _instance!;
  }

  RealtimeSessionManager._();

  RTCDataChannel? _dataChannel;
  // Deprecated: используется для обратной совместимости с UI
  Future<void> Function()? _connectCallback;
  final List<String> _pendingMessages = [];
  bool _isConnecting = false;
  final Duration _connectionTimeout = const Duration(seconds: 30);
  
  // Флаг, определяющий использовать ли RealtimeConnectionService
  // или legacy callback
  bool _useConnectionService = true;
  
  // Флаг для отслеживания успешной отправки сообщений
  // (для предотвращения race condition между registerDataChannel и _waitForConnectionAndSend)
  bool _messagesSentViaCallback = false;

  /// Зарегистрировать data channel
  void registerDataChannel(RTCDataChannel? dc) {
    _dataChannel = dc;
    if (dc != null && dc.state == RTCDataChannelState.RTCDataChannelOpen) {
      // Если есть ожидающие сообщения, отправляем их
      if (_pendingMessages.isNotEmpty) {
        _processPendingMessagesAndTrack();
      }
    } else if (dc == null) {
      // Очищаем pending messages при отключении
      _pendingMessages.clear();
      _messagesSentViaCallback = false;
    }
  }
  
  /// Обработать сообщения и отметить что они отправлены
  Future<void> _processPendingMessagesAndTrack() async {
    final sent = await _processPendingMessages();
    if (sent) {
      _messagesSentViaCallback = true;
    }
  }

  /// Зарегистрировать callback для подключения (legacy, для UI)
  /// 
  /// Если callback зарегистрирован, он будет использоваться вместо
  /// RealtimeConnectionService когда UI активен.
  void registerConnectCallback(Future<void> Function()? connectFn) {
    _connectCallback = connectFn;
  }
  
  /// Включить/выключить использование RealtimeConnectionService
  /// 
  /// При false будет использоваться legacy callback (для UI).
  /// При true будет использоваться RealtimeConnectionService (для фона).
  void setUseConnectionService(bool value) {
    _useConnectionService = value;
  }

  /// Проверить, подключена ли сессия
  bool isConnected() {
    return _dataChannel != null &&
        _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen;
  }

  /// Отправить текстовое сообщение в Realtime сессию
  /// Возвращает true если сообщение успешно отправлено, false в противном случае
  /// 
  /// Если сессия не подключена, автоматически подключается через 
  /// RealtimeConnectionService (может работать в фоновом режиме).
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

    _isConnecting = true;
    try {
      // Выбираем способ подключения
      if (_useConnectionService) {
        // Используем RealtimeConnectionService (работает в фоне)
        debugPrint('[RealtimeSessionManager] Connecting via RealtimeConnectionService...');
        final connected = await RealtimeConnectionService.instance.connect();
        if (!connected) {
          debugPrint('[RealtimeSessionManager] RealtimeConnectionService failed to connect');
          _pendingMessages.clear();
          return false;
        }
      } else if (_connectCallback != null) {
        // Legacy: используем callback (требует UI)
        debugPrint('[RealtimeSessionManager] Connecting via legacy callback...');
        await _connectCallback!();
      } else {
        debugPrint('[RealtimeSessionManager] No connection method available');
        _pendingMessages.removeLast();
        return false;
      }
      
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

    // Проверяем, были ли сообщения уже отправлены через callback registerDataChannel
    if (_messagesSentViaCallback) {
      _messagesSentViaCallback = false; // Сбрасываем флаг
      return true;
    }
    
    // Если сообщения ещё не отправлены, отправляем их
    if (_pendingMessages.isNotEmpty) {
      return await _processPendingMessages();
    }
    
    // Если список пуст и флаг не установлен — странная ситуация, но считаем успехом
    // (сообщения могли быть отправлены где-то ещё)
    return true;
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
