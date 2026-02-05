/// Model for chat messages in the conversation history
class ChatMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;
  final String type; // 'text' or 'voice_transcript'
  final String status; // 'sending', 'sent', 'error'

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.type = 'text',
    this.status = 'sent',
  });

  /// Create a user text message
  factory ChatMessage.userText(String content) {
    return ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: content,
      timestamp: DateTime.now(),
      type: 'text',
      status: 'sent',
    );
  }

  /// Create a user voice transcript message
  factory ChatMessage.userVoice(String content) {
    return ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: content,
      timestamp: DateTime.now(),
      type: 'voice_transcript',
      status: 'sent',
    );
  }

  /// Create an assistant message
  factory ChatMessage.assistant(String content) {
    return ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'assistant',
      content: content,
      timestamp: DateTime.now(),
      type: 'text',
      status: 'sent',
    );
  }

  /// Create a copy with updated fields
  ChatMessage copyWith({
    String? id,
    String? role,
    String? content,
    DateTime? timestamp,
    String? type,
    String? status,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      status: status ?? this.status,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role,
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'type': type,
      'status': status,
    };
  }

  /// Deserialize from JSON
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      role: json['role'] as String,
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: json['type'] as String? ?? 'text',
      status: json['status'] as String? ?? 'sent',
    );
  }

  @override
  String toString() {
    return 'ChatMessage(id: $id, role: $role, type: $type, content: ${content.substring(0, content.length > 50 ? 50 : content.length)}...)';
  }
}
