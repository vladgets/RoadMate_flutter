class Config {
  static const String systemPrompt = '''
You are a realtime voice AI assistant helping users on the go.

Personality: warm, witty, quick-talking; conversationally human. 
When responding in languages that have grammatical gender in verbs like Russian, always use the feminine grammatical form when referring to yourself.

Language: mirror user; default English (US). If user switches languages, follow their accent/dialect after one brief confirmation.

Turns: keep responses under ~5s; stop speaking immediately on user audio (barge-in).

Tools: call a function whenever it can answer faster or more accurately than guessing; summarize tool output briefly.

Memory: You can save facts to long-term memory with "memory_append" when user ask to remember things. 
When user asks about their saved facts, retrieve them with "memory_fetch" and summarize concisely.

If user asks about their calendar events, use calendar functions to fetch the content.
''';

  static const String model = "gpt-realtime-mini-2025-12-15";
  static const String voice = "marin";


  // Tool definitions exposed to the Realtime model.
  // The model may call these by name; your app must execute them and send back
  // a `function_call_output` event with the returned JSON.
  static const List<Map<String, dynamic>> tools = [
    // location related tool
    { 
      "type": "function",
        "name": "get_current_location",
        "description": "Get the user's current GPS location.",
        "parameters": {
          "type": "object",
          "properties": {}
        }
    },
    // memory related tools
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
    // calendar related tools
    {
      "type": "function",
      "name": "get_calendar_data",
      "description": "Fetch user calendar data, vents from the past 30 days to the next 30 days.",
      "parameters": {
        "type": "object",
        "properties": {},
        "required": []
      }
    },
  ];


  // Deprecated or currently unused tool definitions.
  static const List<Map<String, dynamic>> notUsedTools = [
    {
      "type": "function",
      "name": "create_calendar_event",
      "description": "Create a new calendar event. Ask the user for title and start time (required), and optionally end time, description, and location. If end time is not provided, it defaults to start time + 1 hour.",
      "parameters": {
        "type": "object",
        "properties": {
          "title": {
            "type": "string",
            "description": "Event title (required)"
          },
          "start": {
            "type": "string",
            "description": "Start date and time in ISO 8601 format (required), e.g., '2025-12-15T14:00:00'"
          },
          "end": {
            "type": "string",
            "description": "End date and time in ISO 8601 format (optional, defaults to start + 1 hour)"
          },
          "description": {
            "type": "string",
            "description": "Event description (optional)"
          },
          "location": {
            "type": "string",
            "description": "Event location (optional)"
          },
          "calendar_id": {
            "type": "string",
            "description": "Calendar ID to create event in (optional, uses default calendar if not provided)"
          }
        },
        "required": ["title", "start"]
      }
    },
    {
      "type": "function",
      "name": "update_calendar_event",
      "description": "Update an existing calendar event. You can find the event either by event_id or by searching with title and start_date. Then specify which fields to update.",
      "parameters": {
        "type": "object",
        "properties": {
          "event_id": {
            "type": "string",
            "description": "Event ID to update (use this if you know the exact event ID)"
          },
          "title": {
            "type": "string",
            "description": "Event title - use for searching if event_id not provided, or as new title to update"
          },
          "start_date": {
            "type": "string",
            "description": "Start date in ISO 8601 format - use with title to find event if event_id not provided"
          },
          "start": {
            "type": "string",
            "description": "New start date and time in ISO 8601 format (optional, to update)"
          },
          "end": {
            "type": "string",
            "description": "New end date and time in ISO 8601 format (optional, to update)"
          },
          "description": {
            "type": "string",
            "description": "New event description (optional, to update)"
          },
          "location": {
            "type": "string",
            "description": "New event location (optional, to update)"
          }
        },
        "required": []
      }
    },
    {
      "type": "function",
      "name": "delete_calendar_event",
      "description": "Delete a calendar event. You can find the event either by event_id or by searching with title and start_date.",
      "parameters": {
        "type": "object",
        "properties": {
          "event_id": {
            "type": "string",
            "description": "Event ID to delete (use this if you know the exact event ID)"
          },
          "title": {
            "type": "string",
            "description": "Event title to search for (required if event_id not provided)"
          },
          "start_date": {
            "type": "string",
            "description": "Start date in ISO 8601 format (required if event_id not provided, used with title to find event)"
          }
        },
        "required": []
      }
    },
  ];
}