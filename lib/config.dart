import 'services/extra_tools.dart';
import 'services/memory_store.dart';


class Config {
  static const String systemPromptTemplate = '''
You are a realtime voice AI assistant helping users on the go.

Personality: warm, witty, quick-talking; conversationally human. 
Grammatical gender: feminine.

Language: mirror user; default English (US). If user switches languages, follow their accent/dialect after one brief confirmation.

Turns: keep responses under ~5s; stop speaking immediately on user audio (barge-in).

Tools: call a function whenever it can answer faster or more accurately than guessing; summarize tool output briefly.
If a tool call requires parameters try to infer from the context or fetch from memory using memory_fetch tool first before asking user for more info.

Memory: You can save facts to long-term memory with "memory_append" when user ask to remember things. 
If user asks refer to personal information check your memory using "memory_fetch" tool.

WebSearch: Use WebSearch tool for up-to-date or verifiable real-world facts; otherwise answer from knowledge, and never invent facts beyond search results.

Email: When user asks about their emails, use the Gmail search tool to find relevant emails. Use all the search terms in English.

When user wants to create, update, or delete calendar events, ask clarifying questions to get all necessary information:
- For creating: title (required), start time (required), end time (optional, defaults to start + 1 hour), description (optional), location (optional)
- For updating: event_id OR (title and start_date) to find the event, then ask what fields to update
- For deleting: event_id OR (title and start_date) to find the event
Always confirm the action before executing (e.g., "I'll create a meeting called X at Y time. Should I proceed?").
CRITICAL: After the user confirms (says "yes", "ok", "да", "хорошо", etc.), you MUST IMMEDIATELY call the corresponding function (create_calendar_event, update_calendar_event, or delete_calendar_event). Do NOT just say you will do it - actually call the function right away. If you said you will update/delete/create an event, you must call the function in the same turn or immediately after confirmation.

ETA and Navigation: When user asks ETA for a given destination if you can't resolve it to unique address try to check with memory_fetch tool if such address exists in memory
and only if not then ask user.

Current date: {{CURRENT_DATE_READABLE}}
''';

  static const String model = "gpt-realtime-mini-2025-12-15";
  static const String voice = "marin";

  // Our server URL and preference keys
  static const serverUrl = "https://roadmate-flutter.onrender.com";
  static const prefKeyClientId = 'roadmate_client_id';


  /// Build the system prompt with the current readable date
  static String buildSystemPrompt() {
    return systemPromptTemplate.replaceAll('{{CURRENT_DATE_READABLE}}', getCurrentReadableDate());
  }

  /// Build the system prompt with current readable date + user preferences (preferences.txt).
  /// Preferences are optional and may be empty.
  static Future<String> buildSystemPromptWithPreferences() async {
    final base = systemPromptTemplate.replaceAll(
      '{{CURRENT_DATE_READABLE}}',
      getCurrentReadableDate(),
    );

    // Read local preferences file (may be empty / missing).
    final prefs = await PreferencesStore.readAll();

    // Safety: avoid injecting unbounded text into the system prompt.
    const maxChars = 5000;
    final trimmedPrefs = prefs.length > maxChars ? prefs.substring(0, maxChars) : prefs;

    if (trimmedPrefs.trim().isEmpty) return base;

    return '''$base

User Preferences:
$trimmedPrefs''';
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
    // gmail tools
    {
      "type": "function",
      "name": "gmail_search",
      "description": "Search Gmail using simple fields. Returns a small list of email cards: from/subject/date/snippet.",
      "parameters": {
        "type": "object",
        "properties": {
          "text": { "type": "string", "description": "Keywords to search for." },
          "from": { "type": "string", "description": "Sender name or email (optional)." },
          "subject": { "type": "string", "description": "Subject keywords (optional)." },
          "unread_only": { "type": "boolean", "description": "If true, only unread emails." },
          "in_inbox": { "type": "boolean", "description": "If true, search inbox only." },
          "newer_than_days": { "type": "integer", "minimum": 1, "maximum": 365, "description": "Limit to recent emails." },
          "max_results": { "type": "integer", "minimum": 1, "maximum": 10, "description": "How many emails to return." }
        },
        "required": []
      }
    },
    {
      "type": "function",
      "name": "gmail_read_email",
      "description": "Get full email content by message ID.",
      "parameters": {
        "type": "object",
        "properties": {
          "message_id": { "type": "string", "description": "Unique message id." }
        },
        "required": ["message_id"]
      }
    },
    // traffic ETA tool
    {
      "type": "function",
      "name": "traffic_eta",
      "description": "Get ETA and traffic summary between current location and a destination. ",
      "parameters": {
        "type": "object",
        "properties": {
          "destination": {
            "type": "string",
            "description":
                "Destination address",
          },
          "route_type": {
            "type": "string",
            "enum": ["by_car", "on_foot"],
            "description": "Route type, defaults to by_car.",
            "default": "by_car",
          },
          "units": {
            "type": "string",
            "enum": ["metric", "imperial"],
            "description": "Distance units, defaults to imperial.",
            "default": "imperial",
          },
        },
        "required": ["destination"],
      }
    },
    // navigation using existing maps apps
    {
      "type": "function",
      "name": "navigate_to_destination",
      "description": "Open the phone's Maps app showing a route from current location to a destination.",
      "parameters": {
        "type": "object",
        "properties": {
          "destination": {
            "type": "string",
            "description": "Destination address.",
          },
          "route_type": {
            "type": "string",
            "enum": ["by_car", "on_foot"],
            "default": "by_car",
          },
          "nav_app": {
            "type": "string",
            "enum": ["system", "apple", "google", "waze"],
            "description": "Which navigation app to open. system=platform default.",
            "default": "system"
          },
        },
        "required": ["destination"],
      }
    },
  // phone call tool
    {
      "type": "function",
      "name": "call_phone",
      "description": "Place a phone call. Resolve phone number from long-term memory.",
      "parameters": {
        "type": "object",
        "properties": {
          "phone_number": {
            "type": "string",
            "description": "Phone number, e.g. +14085551234",
          },
          "contact_name": {
            "type": "string",
            "description": "Contact name.",
          },
        },
        "required": ["contact_name", "phone_number"],
      },
    }
  ];



  // Deprecated or currently unused tool definitions.
  static const List<Map<String, dynamic>> notUsedTools = [
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