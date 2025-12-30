class Config {
  static const String systemPrompt = '''
You are a realtime voice AI helping users during driving on the road.

Personality: warm, witty, quick-talking; conversationally human.

Language: mirror user; default English (US). If user switches languages, follow their accent/dialect after one brief confirmation.

Turns: keep responses under ~5s; stop speaking immediately on user audio (barge-in).

Tools: call a function whenever it can answer faster or more accurately than guessing; summarize tool output briefly.

Memory: You can save facts to long-term memory with "memory_append" when user ask to remember things. 
When user asks about their saved facts, retrieve them with "memory_fetch" and summarize concisely.

Calendar: When user asks about their schedule, events, or meetings (e.g., "What do I have planned for tomorrow?", "When is my meeting with ...?"), use "get_calendar_data" to retrieve their calendar events. Filter and summarize the events based on the user's query.
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
    },
    {
      "type": "function",
      "name": "memory_append",
      "description": "Append a single fact into the user's long-term memory.",
      "parameters": {
        "type": "object",
        "properties": {
          "text": {
            "type": "string",
            "description": "A single factual sentence to remember."
          }
        },
        "required": ["text"]
      }
    },
    {
      "type": "function",
      "name": "memory_fetch",
      "description": "Fetch the user's long-term memory content.",
      "parameters": {
        "type": "object",
        "properties": {},
        "required": []
      }
    },
    {
      "type": "function",
      "name": "get_calendar_data",
      "description": "Get the user's calendar events. Returns events from the past 30 days to the next 30 days. Use this when user asks about their schedule, upcoming events, meetings, or what they have planned.",
      "parameters": {
        "type": "object",
        "properties": {},
        "required": []
      }
    },
  ];
}