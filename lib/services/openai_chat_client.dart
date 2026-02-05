import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/chat_message.dart';

/// Client for OpenAI Chat Completions API (text-based chat)
class OpenAIChatClient {
  OpenAIChatClient();

  /// Send a chat message and get a response
  /// Returns the assistant's response text
  /// Throws exception on error
  Future<String> sendMessage(
    List<ChatMessage> conversationHistory,
    String newMessage, {
    Function(Map<String, dynamic>)? onToolCall,
  }) async {
    // Build messages array for API
    final messages = [
      {
        'role': 'system',
        'content': Config.systemPromptTemplate
            .replaceAll('{{CURRENT_DATE_READABLE}}', _getCurrentDate()),
      },
      // Add conversation history (limit to last 20 messages for context)
      ...conversationHistory
          .take(conversationHistory.length > 20 ? 20 : conversationHistory.length)
          .map((msg) => {
                'role': msg.role,
                'content': msg.content,
              }),
      // Add new message
      {
        'role': 'user',
        'content': newMessage,
      },
    ];

    // Make API call via server proxy
    final response = await http.post(
      Uri.parse('${Config.serverUrl}/chat'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'model': 'gpt-4o-mini',
        'messages': messages,
        'tools': Config.tools,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Chat API error: ${response.statusCode} ${response.body}');
    }

    final data = json.decode(response.body);
    final choice = data['choices'][0];

    // Check if assistant wants to call tools
    if (choice['message']['tool_calls'] != null) {
      return await _handleToolCalls(
        choice['message']['tool_calls'],
        messages,
        onToolCall,
      );
    }

    // Return assistant's text response
    return choice['message']['content'] as String? ?? '';
  }

  /// Handle tool calls from assistant
  Future<String> _handleToolCalls(
    List<dynamic> toolCalls,
    List<Map<String, dynamic>> messages,
    Function(Map<String, dynamic>)? onToolCall,
  ) async {
    // Execute all tool calls
    final toolMessages = <Map<String, dynamic>>[];

    for (final toolCall in toolCalls) {
      final toolCallId = toolCall['id'] as String;
      final functionName = toolCall['function']['name'] as String;
      final argumentsJson = toolCall['function']['arguments'] as String;

      // Notify callback
      if (onToolCall != null) {
        onToolCall({
          'name': functionName,
          'arguments': json.decode(argumentsJson),
        });
      }

      // Execute tool (this will be delegated to main.dart's tool handlers)
      // For now, we'll return a placeholder - actual integration happens in chat_screen.dart
      toolMessages.add({
        'role': 'tool',
        'tool_call_id': toolCallId,
        'content': json.encode({
          'error': 'Tool execution not yet integrated',
        }),
      });
    }

    // Make follow-up API call with tool results
    final followUpMessages = [
      ...messages,
      {
        'role': 'assistant',
        'tool_calls': toolCalls,
      },
      ...toolMessages,
    ];

    final response = await http.post(
      Uri.parse('${Config.serverUrl}/chat'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'model': 'gpt-4o-mini',
        'messages': followUpMessages,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Chat API error (tool follow-up): ${response.statusCode} ${response.body}');
    }

    final data = json.decode(response.body);
    return data['choices'][0]['message']['content'] as String? ?? '';
  }

  String _getCurrentDate() {
    final now = DateTime.now();
    final weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${weekdays[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}, ${now.year}';
  }
}
