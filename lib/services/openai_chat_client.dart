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
    Future<Map<String, dynamic>> Function(String toolName, dynamic args)? toolExecutor,
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

    // Transform tools from Realtime API format to Chat Completions API format
    final chatTools = Config.tools.map((tool) {
      return {
        'type': 'function',
        'function': {
          'name': tool['name'],
          'description': tool['description'],
          'parameters': tool['parameters'],
        },
      };
    }).toList();

    // Make API call via server proxy
    final response = await http.post(
      Uri.parse('${Config.serverUrl}/chat'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'model': 'gpt-4o-mini',
        'messages': messages,
        'tools': chatTools,
        'tool_choice': 'auto',
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
        chatTools,
        toolExecutor,
      );
    }

    // Return assistant's text response
    return choice['message']['content'] as String? ?? '';
  }

  /// Handle tool calls from assistant
  Future<String> _handleToolCalls(
    List<dynamic> toolCalls,
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> chatTools,
    Future<Map<String, dynamic>> Function(String toolName, dynamic args)? toolExecutor,
  ) async {
    // Execute all tool calls
    final toolMessages = <Map<String, dynamic>>[];

    for (final toolCall in toolCalls) {
      final toolCallId = toolCall['id'] as String;
      final functionName = toolCall['function']['name'] as String;
      final argumentsJson = toolCall['function']['arguments'] as String;
      final arguments = json.decode(argumentsJson);

      // Execute tool if executor is provided
      Map<String, dynamic> result;
      if (toolExecutor != null) {
        try {
          result = await toolExecutor(functionName, arguments);
        } catch (e) {
          result = {'error': e.toString()};
        }
      } else {
        result = {'error': 'Tool execution not available'};
      }

      toolMessages.add({
        'role': 'tool',
        'tool_call_id': toolCallId,
        'content': json.encode(result),
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
        'tools': chatTools,
        'tool_choice': 'auto',
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Chat API error (tool follow-up): ${response.statusCode} ${response.body}');
    }

    final data = json.decode(response.body);
    final choice = data['choices'][0];

    // Check if the assistant wants to make more tool calls
    if (choice['message']['tool_calls'] != null) {
      // Recursively handle more tool calls
      return await _handleToolCalls(
        choice['message']['tool_calls'],
        followUpMessages,
        chatTools,
        toolExecutor,
      );
    }

    return choice['message']['content'] as String? ?? '';
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
