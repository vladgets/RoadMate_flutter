import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_message.dart';

/// Service for persisting chat conversation history
class ConversationStore {
  static const String _storageKey = 'conversation_history';
  static const int _maxMessages = 500;

  final SharedPreferences _prefs;
  List<ChatMessage> _messages = [];

  ConversationStore._(this._prefs);

  /// Initialize the store and load existing messages
  static Future<ConversationStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    final store = ConversationStore._(prefs);
    await store._load();
    return store;
  }

  /// Get all messages in chronological order
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  /// Add a new message to the conversation
  Future<void> addMessage(ChatMessage message) async {
    _messages.add(message);
    await _prune();
    await _save();
  }

  /// Add multiple messages at once
  Future<void> addMessages(List<ChatMessage> messages) async {
    _messages.addAll(messages);
    await _prune();
    await _save();
  }

  /// Update an existing message (e.g., change status from 'sending' to 'sent')
  Future<void> updateMessage(String id, ChatMessage updatedMessage) async {
    final index = _messages.indexWhere((msg) => msg.id == id);
    if (index != -1) {
      _messages[index] = updatedMessage;
      await _save();
    }
  }

  /// Clear all messages
  Future<void> clear() async {
    _messages.clear();
    await _save();
  }

  /// Get the last N messages
  List<ChatMessage> getLastMessages(int count) {
    if (_messages.length <= count) {
      return List.unmodifiable(_messages);
    }
    return List.unmodifiable(_messages.sublist(_messages.length - count));
  }

  /// Load messages from SharedPreferences
  Future<void> _load() async {
    try {
      final jsonString = _prefs.getString(_storageKey);
      if (jsonString == null || jsonString.isEmpty) {
        _messages = [];
        return;
      }

      final List<dynamic> jsonList = json.decode(jsonString);
      _messages = jsonList
          .map((json) => ChatMessage.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // Error loading conversation history
      _messages = [];
    }
  }

  /// Save messages to SharedPreferences
  Future<void> _save() async {
    try {
      final jsonList = _messages.map((msg) => msg.toJson()).toList();
      final jsonString = json.encode(jsonList);
      await _prefs.setString(_storageKey, jsonString);
    } catch (e) {
      // Error saving conversation history - fail silently
    }
  }

  /// Prune old messages if exceeding max limit
  Future<void> _prune() async {
    if (_messages.length > _maxMessages) {
      final excessCount = _messages.length - _maxMessages;
      _messages = _messages.sublist(excessCount);
    }
  }

  /// Get message count
  int get messageCount => _messages.length;

  /// Check if store is empty
  bool get isEmpty => _messages.isEmpty;
}
