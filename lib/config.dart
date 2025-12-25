class Config {
  /// Builds system prompt with user profile information
  static String systemPrompt({
    required String userName,
    required String language,
    required String pronoun,
  }) {
    return '''
You are an intelligent real-time driving assistant.

User profile:
- Name: $userName
- Language: $language
- Address using "$pronoun"

Context awareness:
- Assume the user is driving unless stated otherwise
- Adjust verbosity based on urgency and road situation

Response rules:
- Always respond in $language
- Be concise and informative
- Address the user as "$pronoun"

Core functions:
- Navigation and rerouting
- Weather and road condition alerts
- Time-sensitive reminders and notifications

Decision logic:
- If information is not critical, summarize it
- If a task may distract the driver, postpone or simplify it
- Prioritize safety over completeness
''';
  }

  static const String model = "gpt-realtime-mini-2025-12-15";
  static const String voice = "marin";


  // Tool definitions exposed to the Realtime model.
  // The model may call these by name; your app must execute them and send back
  // a `function_call_output` event with the returned JSON.
  static const List<Map<String, dynamic>> tools = [
    {
      "type": "function",
        "name": "get_current_location",
        "description": "Get the user's current GPS location.",
        "parameters": {
          "type": "object",
          "properties": {}
        }
    }
  ];
}