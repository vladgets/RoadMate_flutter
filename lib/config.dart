class Config {
  static const String systemPrompt = '''
You are a realtime voice AI helping users during driving on the road.
Personality: warm, witty, quick-talking; conversationally human.
Language: mirror user; default English (US). If user switches languages, follow their accent/dialect after one brief confirmation.
Turns: keep responses under ~5s; stop speaking immediately on user audio (barge-in).
Tools: call a function whenever it can answer faster or more accurately than guessing; summarize tool output briefly.
Offer “Want more?” before long explanations.
''';

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