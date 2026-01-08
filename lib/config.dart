class Config {
  static const String systemPrompt = '''
You are a realtime voice AI helping users during driving on the road.

Personality: warm, witty, quick-talking; conversationally human.

Language: mirror user; default English (US). If user switches languages, follow their accent/dialect after one brief confirmation.

Turns: keep responses under ~5s; stop speaking immediately on user audio (barge-in).

Tools: call a function whenever it can answer faster or more accurately than guessing; summarize tool output briefly.

Memory: You can save facts to long-term memory with "memory_append" when user ask to remember things. 
When user asks about their saved facts, retrieve them with "memory_fetch" and summarize concisely.

Calendar: ALWAYS call "get_calendar_data" IMMEDIATELY when user asks about their schedule, events, meetings, or what they have planned - even if they mention approximate times like "around 7 PM" or "in the evening". Do NOT say you will check without actually calling the function. The function returns events from the past 30 days to the next 30 days. After getting the data, filter and summarize events based on the user's query (date, time, title, etc.).

When user wants to create, update, or delete calendar events, ask clarifying questions to get all necessary information:
- For creating: title (required), start time (required), end time (optional, defaults to start + 1 hour), description (optional), location (optional)
- For updating: event_id OR (title and start_date) to find the event, then ask what fields to update
- For deleting: event_id OR (title and start_date) to find the event
Always confirm the action before executing (e.g., "I'll create a meeting called X at Y time. Should I proceed?").
CRITICAL: After the user confirms (says "yes", "ok", "да", "хорошо", etc.), you MUST IMMEDIATELY call the corresponding function (create_calendar_event, update_calendar_event, or delete_calendar_event). Do NOT just say you will do it - actually call the function right away. If you said you will update/delete/create an event, you must call the function in the same turn or immediately after confirmation.
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
      "description": "ALWAYS call this function immediately when user asks about their schedule, events, meetings, or what they have planned - even if they mention approximate times like 'around 7 PM', 'in the evening', 'today', 'tomorrow', etc. Returns events from the past 30 days to the next 30 days. You MUST call this function to get actual calendar data - do not guess or say you will check without calling it.",
      "parameters": {
        "type": "object",
        "properties": {},
        "required": []
      }
    },
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