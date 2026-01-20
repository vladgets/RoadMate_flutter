import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'realtime_session_manager.dart';
import 'background_audio_service.dart';

/// Callback для обработки событий от OpenAI Realtime API
typedef OaiEventHandler = void Function(String eventJson);

/// Callback для обновления статуса подключения (опциональный, для UI)
typedef StatusUpdateCallback = void Function(String status);

/// Callback для обработки ошибок (опциональный, для UI)
typedef ErrorCallback = void Function(String error);

/// Сервис для управления WebRTC подключением к OpenAI Realtime API.
/// 
/// Этот сервис отделён от UI и может работать в фоновом режиме.
/// Он управляет WebRTC соединением, микрофоном и data channel.
class RealtimeConnectionService {
  static RealtimeConnectionService? _instance;
  static RealtimeConnectionService get instance {
    _instance ??= RealtimeConnectionService._();
    return _instance!;
  }
  
  RealtimeConnectionService._();
  
  // WebRTC компоненты
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  MediaStream? _mic;
  
  // Состояние
  bool _isConnecting = false;
  bool _isConnected = false;
  String? _lastError;
  
  // Callbacks
  OaiEventHandler? _eventHandler;
  StatusUpdateCallback? _statusCallback;
  ErrorCallback? _errorCallback;
  
  // Getters
  bool get isConnecting => _isConnecting;
  bool get isConnected => _isConnected;
  String? get lastError => _lastError;
  RTCDataChannel? get dataChannel => _dc;
  
  /// Зарегистрировать обработчик событий OpenAI
  void registerEventHandler(OaiEventHandler handler) {
    _eventHandler = handler;
  }
  
  /// Зарегистрировать callback для обновления статуса (опционально, для UI)
  void registerStatusCallback(StatusUpdateCallback? callback) {
    _statusCallback = callback;
  }
  
  /// Зарегистрировать callback для ошибок (опционально, для UI)
  void registerErrorCallback(ErrorCallback? callback) {
    _errorCallback = callback;
  }
  
  void _updateStatus(String status) {
    debugPrint('[RealtimeConnectionService] $status');
    _statusCallback?.call(status);
  }
  
  void _reportError(String error) {
    _lastError = error;
    debugPrint('[RealtimeConnectionService] ERROR: $error');
    _errorCallback?.call(error);
  }
  
  /// Настроить аудио сессию для работы в фоне
  Future<void> _configureAudioSession() async {
    try {
      debugPrint('[RealtimeConnectionService] Configuring audio session for background...');
      
      // На iOS запускаем фоновый аудио сервис для поддержания сессии
      if (Platform.isIOS) {
        await BackgroundAudioService.instance.start();
      }
      
      // Форсируем включение динамика для WebRTC
      // Это также активирует аудио сессию на iOS
      await Helper.setSpeakerphoneOn(true);
      
      // Небольшая задержка чтобы аудио сессия успела активироваться
      await Future.delayed(const Duration(milliseconds: 100));
      
      debugPrint('[RealtimeConnectionService] Audio session configured');
    } catch (e) {
      debugPrint('[RealtimeConnectionService] Audio session configuration warning: $e');
      // Не критичная ошибка, продолжаем
    }
  }
  
  /// Подключиться к OpenAI Realtime API
  /// 
  /// Этот метод не использует setState() и может быть вызван из фонового сервиса.
  /// Возвращает true при успешном подключении, false при ошибке.
  Future<bool> connect() async {
    if (_isConnecting) {
      debugPrint('[RealtimeConnectionService] Already connecting, skipping...');
      return false;
    }
    
    if (_isConnected && _dc?.state == RTCDataChannelState.RTCDataChannelOpen) {
      debugPrint('[RealtimeConnectionService] Already connected');
      return true;
    }
    
    _isConnecting = true;
    _lastError = null;
    
    // Completer для ожидания открытия data channel
    final dataChannelCompleter = Completer<bool>();
    
    try {
      // 0) Настраиваем аудио сессию для работы в фоне
      await _configureAudioSession();
      
      // 1) Получаем ephemeral key с бэкенда
      _updateStatus('Requesting token...');
      final tokenResp = await http.get(
        Uri.parse('${Config.serverUrl}/token'),
      ).timeout(const Duration(seconds: 15));
      
      if (tokenResp.statusCode != 200) {
        throw Exception('Token request failed: ${tokenResp.statusCode}');
      }
      
      final tokenJson = jsonDecode(tokenResp.body) as Map<String, dynamic>;
      final ephemeralKey = tokenJson['value'] as String;
      
      // 2) Создаём PeerConnection
      _updateStatus('Creating peer connection...');
      _pc = await createPeerConnection({
        // Можно добавить STUN сервер если есть проблемы с ICE
        // 'iceServers': [{'urls': 'stun:stun.l.google.com:19302'}]
      });
      
      // 3) Обработка входящего аудио трека
      _pc!.onTrack = (RTCTrackEvent e) async {
        if (e.track.kind == 'audio') {
          debugPrint('[RealtimeConnectionService] Received audio track, enabling speaker...');
          
          // Включаем громкую связь - это критично для воспроизведения в фоне
          try {
            await Helper.setSpeakerphoneOn(true);
          } catch (err) {
            debugPrint('[RealtimeConnectionService] Speaker error: $err');
          }
          
          // Убеждаемся что трек включён
          e.track.enabled = true;
          
          _updateStatus('Assistant connected. Talk!');
        }
      };
      
      // 4) Получаем доступ к микрофону
      _updateStatus('Opening microphone...');
      _mic = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      
      final audioTrack = _mic!.getAudioTracks().first;
      await _pc!.addTrack(audioTrack, _mic!);
      
      // 5) Создаём data channel
      _dc = await _pc!.createDataChannel('oai-events', RTCDataChannelInit());
      
      _dc!.onDataChannelState = (RTCDataChannelState state) {
        debugPrint('[RealtimeConnectionService] DataChannel state: $state');
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          _isConnected = true;
          RealtimeSessionManager.instance.registerDataChannel(_dc);
          // Сигнализируем что data channel готов
          if (!dataChannelCompleter.isCompleted) {
            dataChannelCompleter.complete(true);
          }
        } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
          _isConnected = false;
        }
      };
      
      _dc!.onMessage = (RTCDataChannelMessage msg) {
        // Передаём события в зарегистрированный обработчик
        _eventHandler?.call(msg.text);
      };
      
      // 6) SDP Offer/Answer обмен
      _updateStatus('Creating offer...');
      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 0,
      });
      await _pc!.setLocalDescription(offer);
      
      _updateStatus('Calling OpenAI Realtime...');
      final answerSdp = await _createCallAndGetAnswerSdp(
        ephemeralKey: ephemeralKey,
        offerSdp: offer.sdp!,
      );
      
      await _pc!.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
      
      _updateStatus('Waiting for data channel to open...');
      
      // 7) Ждём открытия data channel (с таймаутом)
      final dataChannelOpened = await dataChannelCompleter.future
          .timeout(const Duration(seconds: 10), onTimeout: () {
        debugPrint('[RealtimeConnectionService] Data channel open timeout');
        return false;
      });
      
      if (!dataChannelOpened) {
        throw Exception('Data channel failed to open');
      }
      
      _updateStatus('Connected. Talk!');
      
      return true;
    } catch (e) {
      _reportError(e.toString());
      if (!dataChannelCompleter.isCompleted) {
        dataChannelCompleter.complete(false);
      }
      await disconnect();
      return false;
    } finally {
      _isConnecting = false;
    }
  }
  
  /// Создать вызов и получить SDP ответ от OpenAI
  Future<String> _createCallAndGetAnswerSdp({
    required String ephemeralKey,
    required String offerSdp,
  }) async {
    final uri = Uri.parse('https://api.openai.com/v1/realtime/calls');
    final req = http.MultipartRequest('POST', uri);
    
    req.headers['Authorization'] = 'Bearer $ephemeralKey';
    
    final instructions = await Config.buildSystemPromptWithPreferences();
    
    req.fields['session'] = jsonEncode({
      'type': 'realtime',
      'model': Config.model,
      'instructions': instructions,
      'tools': Config.tools,
      'tool_choice': 'auto',
      'audio': {
        'input': {
          'turn_detection': {'type': 'server_vad'},
          'transcription': {'model': 'gpt-4o-mini-transcribe'}
        },
        'output': {'voice': Config.voice},
      }
    });
    
    req.fields['sdp'] = offerSdp;
    
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    
    if (streamed.statusCode != 200 && streamed.statusCode != 201) {
      throw Exception('OpenAI create call failed ${streamed.statusCode}: $body');
    }
    
    return body; // SDP answer
  }
  
  /// Отключиться от OpenAI Realtime API
  Future<void> disconnect() async {
    try {
      // Уведомляем RealtimeSessionManager об отключении
      RealtimeSessionManager.instance.registerDataChannel(null);
      
      await _dc?.close();
      await _pc?.close();
      
      final tracks = _mic?.getTracks() ?? [];
      for (final t in tracks) {
        await t.stop();
      }
      await _mic?.dispose();
      
      // Останавливаем фоновый аудио сервис на iOS
      if (Platform.isIOS) {
        await BackgroundAudioService.instance.stop();
      }
    } catch (e) {
      debugPrint('[RealtimeConnectionService] Disconnect error: $e');
    } finally {
      _dc = null;
      _pc = null;
      _mic = null;
      _isConnected = false;
      _isConnecting = false;
      _updateStatus('Disconnected.');
    }
  }
  
  /// Переключить состояние подключения
  Future<bool> toggle() async {
    if (_isConnecting) return false;
    
    if (_isConnected) {
      await disconnect();
      return false;
    } else {
      return await connect();
    }
  }
  
  /// Отправить результат выполнения инструмента
  Future<void> sendToolOutput({
    required String callId,
    required String name,
    required Map<String, dynamic> output,
  }) async {
    final dc = _dc;
    if (dc == null || dc.state != RTCDataChannelState.RTCDataChannelOpen) {
      debugPrint('[RealtimeConnectionService] Cannot send tool output: data channel not ready');
      return;
    }
    
    final payload = {
      'type': 'conversation.item.create',
      'item': {
        'type': 'function_call_output',
        'call_id': callId,
        'output': jsonEncode(output),
      },
    };
    
    dc.send(RTCDataChannelMessage(jsonEncode(payload)));
    
    // Запрашиваем продолжение от модели
    dc.send(RTCDataChannelMessage(jsonEncode({'type': 'response.create'})));
    debugPrint('[RealtimeConnectionService] Sent tool output: $name (call_id=$callId)');
  }
  
  void dispose() {
    disconnect();
    _eventHandler = null;
    _statusCallback = null;
    _errorCallback = null;
  }
}
