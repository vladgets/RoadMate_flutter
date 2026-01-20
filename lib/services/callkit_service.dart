import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:uuid/uuid.dart';
import 'realtime_connection_service.dart';
import 'realtime_session_manager.dart';

/// Сервис для управления CallKit (входящие "звонки" от ассистента).
/// 
/// Используется для отображения UI звонка при прибытии в место назначения.
/// Это позволяет WebRTC аудио работать при заблокированном экране,
/// так как iOS не приостанавливает аудио для активных звонков.
class CallKitService {
  static CallKitService? _instance;
  static CallKitService get instance {
    _instance ??= CallKitService._();
    return _instance!;
  }
  
  CallKitService._();
  
  final _uuid = const Uuid();
  String? _currentCallId;
  bool _isInitialized = false;
  StreamSubscription? _callEventSubscription;
  
  // Сообщение которое нужно отправить после принятия звонка
  String? _pendingMessage;
  
  /// Инициализировать CallKit сервис
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (!Platform.isIOS && !Platform.isAndroid) return;
    
    // Слушаем события CallKit
    _callEventSubscription = FlutterCallkitIncoming.onEvent.listen(_handleCallEvent);
    
    _isInitialized = true;
    debugPrint('[CallKitService] Initialized');
  }
  
  /// Показать входящий "звонок" от ассистента
  /// 
  /// [message] — сообщение которое будет отправлено в Realtime сессию после принятия звонка
  /// [locationName] — название места (опционально, для отображения в UI)
  Future<void> showIncomingCall({
    required String message,
    String? locationName,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    // Сохраняем сообщение для отправки после принятия
    _pendingMessage = message;
    
    // Генерируем уникальный ID звонка
    _currentCallId = _uuid.v4();
    
    final params = CallKitParams(
      id: _currentCallId,
      nameCaller: 'RoadMate Assistant',
      appName: 'RoadMate',
      // Используем название места или координаты как "номер"
      handle: locationName ?? 'You have arrived',
      type: 0, // 0 = Audio call
      textAccept: 'Talk',
      textDecline: 'Ignore',
      // Время до автоматического отклонения (в миллисекундах)
      duration: 60000, // 60 секунд
      extra: <String, dynamic>{
        'message': message,
      },
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#4A90E2',
        actionColor: '#4CAF50',
        textColor: '#FFFFFF',
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );
    
    await FlutterCallkitIncoming.showCallkitIncoming(params);
    debugPrint('[CallKitService] Incoming call displayed: $_currentCallId');
  }
  
  /// Обработать события CallKit
  void _handleCallEvent(CallEvent? event) async {
    if (event == null) return;
    
    debugPrint('[CallKitService] Event: ${event.event}, body: ${event.body}');
    
    switch (event.event) {
      case Event.actionCallAccept:
        // Пользователь принял звонок
        await _handleCallAccepted();
        break;
        
      case Event.actionCallDecline:
        // Пользователь отклонил звонок
        _handleCallDeclined();
        break;
        
      case Event.actionCallEnded:
        // Звонок завершён
        _handleCallEnded();
        break;
        
      case Event.actionCallTimeout:
        // Звонок не был отвечен (таймаут)
        _handleCallTimeout();
        break;
        
      default:
        break;
    }
  }
  
  /// Обработать принятие звонка
  Future<void> _handleCallAccepted() async {
    debugPrint('[CallKitService] Call accepted, starting Realtime session...');
    
    if (_pendingMessage == null) {
      debugPrint('[CallKitService] No pending message, skipping...');
      return;
    }
    
    // Подключаемся к Realtime и отправляем сообщение
    final success = await RealtimeSessionManager.instance.sendTextMessage(_pendingMessage!);
    
    if (success) {
      debugPrint('[CallKitService] Message sent successfully');
    } else {
      debugPrint('[CallKitService] Failed to send message');
      // Завершаем звонок при ошибке
      await endCall();
    }
    
    _pendingMessage = null;
  }
  
  /// Обработать отклонение звонка
  void _handleCallDeclined() {
    debugPrint('[CallKitService] Call declined');
    _pendingMessage = null;
    _currentCallId = null;
  }
  
  /// Обработать завершение звонка
  void _handleCallEnded() {
    debugPrint('[CallKitService] Call ended');
    _currentCallId = null;
    
    // Отключаем Realtime сессию
    RealtimeConnectionService.instance.disconnect();
  }
  
  /// Обработать таймаут звонка
  void _handleCallTimeout() {
    debugPrint('[CallKitService] Call timeout');
    _pendingMessage = null;
    _currentCallId = null;
  }
  
  /// Завершить текущий звонок
  Future<void> endCall() async {
    if (_currentCallId == null) return;
    
    await FlutterCallkitIncoming.endCall(_currentCallId!);
    _currentCallId = null;
    debugPrint('[CallKitService] Call ended by app');
  }
  
  /// Завершить все активные звонки
  Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
    _currentCallId = null;
    debugPrint('[CallKitService] All calls ended');
  }
  
  /// Проверить, есть ли активный звонок
  bool get hasActiveCall => _currentCallId != null;
  
  void dispose() {
    _callEventSubscription?.cancel();
    _callEventSubscription = null;
    _isInitialized = false;
  }
}
