import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';

import '../config.dart';
import 'geo_time_tools.dart';
import 'memory_store.dart';
import 'calendar.dart';
import 'web_search.dart';
import 'gmail_client.dart';
import 'map_navigation.dart';
import 'phone_call.dart';
import 'reminders.dart';

/// VocalBridge voice agent service using LiveKit.
/// Replaces direct WebRTC connection to OpenAI with VocalBridge platform.
class VocalBridgeService {
  VocalBridgeService({
    required this.apiKey,
    this.apiUrl = 'https://vocalbridgeai.com',
  });

  final String apiKey;
  final String apiUrl;

  Room? _room;
  EventsListener<RoomEvent>? _listener;

  // Web search client (reuse single instance)
  final WebSearchClient _webSearchClient = WebSearchClient();
  late final WebSearchTool _webSearchTool = WebSearchTool(client: _webSearchClient);

  // Gmail client (initialized when client id is available)
  GmailClient? _gmailClient;
  String? _clientId;

  // Deduplication for action calls
  final Set<String> _handledActionIds = <String>{};

  // Connection state
  bool _connecting = false;
  bool _connected = false;

  // Callbacks for UI updates
  Function(String status)? onStatusChanged;
  Function(String error)? onError;
  Function(bool connected)? onConnectionChanged;

  bool get isConnecting => _connecting;
  bool get isConnected => _connected;

  /// Initialize the service (call once at app startup)
  Future<void> init() async {
    // Get or create client ID for Gmail
    _clientId = await ClientIdStore.getOrCreate();
    _gmailClient = GmailClient(baseUrl: Config.serverUrl, clientId: _clientId!);
    debugPrint('[VocalBridge] Initialized with clientId: $_clientId');
  }

  /// Get LiveKit token from VocalBridge API
  Future<Map<String, dynamic>> _getToken() async {
    final response = await http.post(
      Uri.parse('$apiUrl/api/v1/token'),
      headers: {
        'X-API-Key': apiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'participant_name': 'RoadMate User'}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to get token: ${response.statusCode} ${response.body}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Connect to the voice agent
  Future<void> connect() async {
    if (_connecting || _connected) return;

    _connecting = true;
    _updateStatus('Requesting token…');

    try {
      // 1. Get token from VocalBridge
      final tokenData = await _getToken();
      final livekitUrl = tokenData['livekit_url'] as String;
      final token = tokenData['token'] as String;
      final roomName = tokenData['room_name'] as String?;

      debugPrint('[VocalBridge] Connecting to room: $roomName');
      _updateStatus('Connecting to room…');

      // 2. Create LiveKit room
      _room = Room();

      // 3. Set up event listeners
      _listener = _room!.createListener();
      _setupEventHandlers();

      // 4. Connect to the room
      await _room!.connect(livekitUrl, token);
      debugPrint('[VocalBridge] Connected to room: ${_room!.name}');

      _updateStatus('Opening microphone…');

      // 5. Enable microphone
      await _room!.localParticipant?.setMicrophoneEnabled(true);
      debugPrint('[VocalBridge] Microphone enabled');

      _connected = true;
      _connecting = false;
      _updateStatus('Connected. Talk!');
      onConnectionChanged?.call(true);

    } catch (e) {
      debugPrint('[VocalBridge] Connection error: $e');
      _connecting = false;
      _connected = false;
      onError?.call(e.toString());
      onConnectionChanged?.call(false);
      await disconnect();
      rethrow;
    }
  }

  /// Set up LiveKit event handlers
  void _setupEventHandlers() {
    // Handle agent audio track (automatic playback by LiveKit)
    _listener!.on<TrackSubscribedEvent>((event) {
      if (event.track.kind == TrackType.AUDIO) {
        debugPrint('[VocalBridge] Agent audio track subscribed');
        _updateStatus('Agent connected. Talk!');
      }
    });

    // Handle track unsubscribed
    _listener!.on<TrackUnsubscribedEvent>((event) {
      debugPrint('[VocalBridge] Track unsubscribed: ${event.track.kind}');
    });

    // Handle disconnection
    _listener!.on<RoomDisconnectedEvent>((event) {
      debugPrint('[VocalBridge] Disconnected from room');
      _connected = false;
      _updateStatus('Disconnected');
      onConnectionChanged?.call(false);
    });

    // Handle client actions from agent
    _listener!.on<DataReceivedEvent>((event) {
      _handleDataReceived(event);
    });

    // Handle participant events
    _listener!.on<ParticipantConnectedEvent>((event) {
      debugPrint('[VocalBridge] Participant connected: ${event.participant.identity}');
    });

    _listener!.on<ParticipantDisconnectedEvent>((event) {
      debugPrint('[VocalBridge] Participant disconnected: ${event.participant.identity}');
    });
  }

  /// Handle incoming data from agent (client actions)
  void _handleDataReceived(DataReceivedEvent event) {
    // Only handle client_actions topic
    if (event.topic != 'client_actions') {
      debugPrint('[VocalBridge] Ignoring data on topic: ${event.topic}');
      return;
    }

    try {
      final data = jsonDecode(utf8.decode(event.data)) as Map<String, dynamic>;
      debugPrint('[VocalBridge] Received data: $data');

      if (data['type'] == 'client_action') {
        final action = data['action'] as String?;
        final payload = data['payload'] as Map<String, dynamic>? ?? {};
        final actionId = data['id']?.toString() ?? '${action}_${DateTime.now().millisecondsSinceEpoch}';

        if (action == null) {
          debugPrint('[VocalBridge] Missing action name');
          return;
        }

        // Deduplicate
        if (_handledActionIds.contains(actionId)) {
          debugPrint('[VocalBridge] Duplicate action ignored: $action ($actionId)');
          return;
        }
        _handledActionIds.add(actionId);

        debugPrint('[VocalBridge] Executing action: $action with payload: $payload');
        _executeAction(action, payload, actionId);
      }
    } catch (e) {
      debugPrint('[VocalBridge] Error parsing data: $e');
    }
  }

  /// Execute a client action and send result back
  Future<void> _executeAction(String action, Map<String, dynamic> payload, String actionId) async {
    final handler = _toolHandlers[action];

    if (handler == null) {
      debugPrint('[VocalBridge] Unknown action: $action');
      await _sendActionResult(action, actionId, {'error': 'Unknown action: $action'});
      return;
    }

    try {
      final result = await handler(payload);
      await _sendActionResult(action, actionId, result);
    } catch (e) {
      debugPrint('[VocalBridge] Action error ($action): $e');
      await _sendActionResult(action, actionId, {'error': e.toString()});
    }
  }

  /// Send action result back to agent
  Future<void> _sendActionResult(String action, String actionId, Map<String, dynamic> result) async {
    final room = _room;
    if (room == null || room.connectionState != ConnectionState.connected) {
      debugPrint('[VocalBridge] Cannot send result - not connected');
      return;
    }

    final message = jsonEncode({
      'type': 'action_result',
      'action': action,
      'id': actionId,
      'result': result,
    });

    try {
      await room.localParticipant?.publishData(
        utf8.encode(message),
        reliable: true,
        topic: 'client_actions',
      );
      debugPrint('[VocalBridge] Sent result for action: $action');
    } catch (e) {
      debugPrint('[VocalBridge] Error sending result: $e');
    }
  }

  /// Tool handlers map - same logic as original main.dart
  late final Map<String, Future<Map<String, dynamic>> Function(Map<String, dynamic> args)> _toolHandlers = {
    // Location
    'get_current_location': (_) async {
      return await getCurrentLocation();
    },

    // Memory
    'memory_append': (args) async {
      return await MemoryStore.toolAppend(args);
    },
    'memory_fetch': (_) async {
      return await MemoryStore.toolRead();
    },

    // Calendar
    'get_calendar_data': (_) async {
      return await CalendarStore.toolGetCalendarData();
    },

    // Time
    'get_current_time': (_) async {
      return await getCurrentTime();
    },

    // Web search
    'web_search': (args) async {
      return await _webSearchTool.call(args);
    },

    // Gmail
    'gmail_search': (args) async {
      if (_gmailClient == null) {
        return {'error': 'Gmail is not initialized yet. Try again in a second.'};
      }
      return await GmailSearchTool(client: _gmailClient!).call(args);
    },
    'gmail_read_email': (args) async {
      if (_gmailClient == null) {
        return {'error': 'Gmail is not initialized yet. Try again in a second.'};
      }
      return await GmailReadEmailTool(client: _gmailClient!).call(args);
    },

    // Traffic & Navigation
    'traffic_eta': (args) async {
      return await handleTrafficEtaToolCall(args);
    },
    'navigate_to_destination': (args) async {
      return await handleOpenMapsRouteToolCall(args);
    },

    // Phone
    'call_phone': (args) async {
      return await handlePhoneCallTool(args);
    },

    // Reminders
    'reminder_create': (args) async {
      return await RemindersService.instance.toolCreate(args);
    },
    'reminder_list': (_) async {
      return await RemindersService.instance.toolList();
    },
    'reminder_cancel': (args) async {
      return await RemindersService.instance.toolCancel(args);
    },

    // YouTube (new for hackathon)
    'youtube_search': (args) async {
      // TODO: Implement YouTube search
      return {'error': 'YouTube search not implemented yet', 'query': args['query']};
    },
    'youtube_get_transcript': (args) async {
      // TODO: Implement YouTube transcript fetching
      return {'error': 'YouTube transcript not implemented yet', 'video_id': args['video_id']};
    },
    'youtube_play': (args) async {
      // TODO: Implement YouTube playback
      return {'error': 'YouTube play not implemented yet', 'video_id': args['video_id']};
    },
  };

  /// Update status and notify listener
  void _updateStatus(String status) {
    debugPrint('[VocalBridge] Status: $status');
    onStatusChanged?.call(status);
  }

  /// Disconnect from the voice agent
  Future<void> disconnect() async {
    try {
      await _room?.disconnect();
    } catch (e) {
      debugPrint('[VocalBridge] Disconnect error: $e');
    } finally {
      _room = null;
      _listener = null;
      _connected = false;
      _connecting = false;
      _handledActionIds.clear();
      _updateStatus('Disconnected');
      onConnectionChanged?.call(false);
    }
  }

  /// Toggle connection state
  Future<void> toggle() async {
    if (_connecting) return;
    if (_connected) {
      await disconnect();
    } else {
      await connect();
    }
  }

  /// Clean up resources
  void dispose() {
    _webSearchClient.close();
    disconnect();
  }
}
