import 'services/extra_tools.dart';


class Config {
  static const String systemPromptTemplate = '''
You are a realtime voice AI assistant helping users on the go.

Personality: warm, witty, quick-talking; conversationally human. 
When responding in languages that have grammatical gender in verbs like Russian, always use the feminine grammatical form when referring to yourself.

Language: mirror user; default English (US). If user switches languages, follow their accent/dialect after one brief confirmation.

Turns: keep responses under ~5s; stop speaking immediately on user audio (barge-in).

Tools: call a function whenever it can answer faster or more accurately than guessing; summarize tool output briefly.
If user asks about their calendar events, use calendar functions to fetch the content.

Memory: You can save facts to long-term memory with "memory_append" when user ask to remember things. 
When user asks about their saved facts, retrieve them with "memory_fetch" and summarize concisely.

WebSearch: Use WebSearch tool for up-to-date or verifiable real-world facts; otherwise answer from knowledge, and never invent facts beyond search results.

Mail: When user asks about their emails, use the Gmail search tool to find relevant emails.

Current date: {{CURRENT_DATE_READABLE}}
''';

  static const String model = "gpt-realtime-mini-2025-12-15";
  static const String voice = "marin";


  /// Build the system prompt with the current readable date
  static String buildSystemPrompt() {
    return systemPromptTemplate.replaceAll('{{CURRENT_DATE_READABLE}}', getCurrentReadableDate());
  }


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
      }
    },
    // calendar related tools
    {
      "type": "function",
      "name": "get_calendar_data",
      "description": "Fetch user calendar data.",
      "parameters": {
        "type": "object",
        "properties": {},
      }
    },
    // time and date
    {
      "type": "function",
      "name": "get_current_time",
      "description": "Returns the user's current local date and time.",
      "parameters": {
        "type": "object",
        "properties": {}
      }
    },
    // web search tool
    {
      "type": "function",
      "name": "web_search",
      "description": "Search the web for up-to-date real-world information.",
      "parameters": {
        "type": "object",
        "properties": {
          "query": {
            "type": "string",
          }
        },
        "required": ["query"]
      }
    },
    // gmail search tool
    {
      "type": "function",
      "name": "gmail_search",
      "description": "Search Gmail using simple fields (voice-friendly). Returns a small list of email cards: from/subject/date/snippet.",
      "parameters": {
        "type": "object",
        "properties": {
          "text": { "type": "string", "description": "Keywords to search for." },
          "from": { "type": "string", "description": "Sender name or email (optional)." },
          "subject": { "type": "string", "description": "Subject keywords (optional)." },
          "unread_only": { "type": "boolean", "description": "If true, only unread emails." },
          "in_inbox": { "type": "boolean", "description": "If true (default), search inbox only." },
          "newer_than_days": { "type": "integer", "minimum": 1, "maximum": 365, "description": "Limit to recent emails." },
          "max_results": { "type": "integer", "minimum": 1, "maximum": 10, "description": "How many emails to return." }
        },
        "required": []
      }
    }
  ];


  // Deprecated or currently unused tool definitions.
  static const List<Map<String, dynamic>> notUsedTools = [
    // gmail read email tool
    {
      "type": "function",
      "name": "gmail_read_email",
      "description": "Read one email (metadata/snippet). Use after gmail_search_simple when user picks an email.",
      "parameters": {
        "type": "object",
        "properties": {
          "id": { "type": "string", "description": "Email message id." }
        },
        "required": ["id"]
      }
    },

    // calendar event management tools
    {
      "type": "function",
      "name": "create_calendar_event",
      "description": "Create a new calendar event.",
      "parameters": {
        "type": "object",
        "properties": {
          "title": {
            "type": "string",
            "description": "Event title"
          },
          "start": {
            "type": "string",
            "description": "Start date and time in ISO 8601 format"
          },
          "end": {
            "type": "string",
            "description": "End date and time in ISO 8601 format (optional)"
          },
          "description": {
            "type": "string",
            "description": "Event description (optional)"
          },
          "location": {
            "type": "string",
            "description": "Event location (optional)"
          },
        },
        "required": ["title", "start"]
      }
    },
    {
      "type": "function",
      "name": "update_calendar_event",
      "description": "Update an existing calendar event.",
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
      "description": "Delete a calendar event.",
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