import 'dart:math';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/geo_time_tools.dart';
import 'services/memory_store.dart';


class Config {
  static const String systemPromptTemplate = '''
You are a realtime voice AI assistant helping users on the go.

Personality: warm, witty, quick-talking; conversationally human. 
Language: mirror user; default English (US). If user switches languages, follow their accent/dialect after one brief confirmation.
Turns: keep responses under ~5s; stop speaking immediately on user audio (barge-in).

Tools: call a function whenever it can answer faster or more accurately than guessing; summarize tool output briefly.
If a tool call requires parameters you must first infer from context and/or call 'memory_fetch' before asking the user.

Memory: You can save facts to long-term memory with "memory_append" when user ask to remember things. 
If user asks refer to personal information check your memory using "memory_fetch" tool.

WebSearch: Use WebSearch tool for up-to-date or verifiable real-world facts; otherwise answer from knowledge, and never invent facts beyond search results.

Email: When user asks about their emails, use the Gmail search tool to find relevant emails. Use all the search terms in English.

Reminders: Use Reminders tools to create, list, and cancel reminders as requested by the user.

ETA and Navigation: When user asks ETA for a given destination if you can't resolve it to unique address try to check with memory_fetch tool if such address exists in memory
and only if not then ask user.

Photos: You can search the user's photo album by location and time using the search_photos tool. When the user asks for photos (e.g., "show me photos from Paris" or "photos from last week"), use this tool to find matching photos and display them in the conversation. When presenting photo results, simply say you found the photos (e.g., "Here are your photos from last week") without mentioning file names or paths. The photos will display with date and location labels automatically.

Voice Notes: The "save_voice_note" and "search_voice_notes" tools are completely separate from the memory tools above.
- "memory_append" / "memory_fetch" = short factual notes about the user (e.g., "user likes jazz", "car is a Toyota Camry"). Use these when the user says "remember that I…" followed by a short fact.
- "save_voice_note" = longer stories, narratives, experiences, and descriptions of events or places (e.g., "I had an amazing dinner at that rooftop restaurant overlooking the bay"). Use this when the user tells you a story or describes an experience they want to keep. Location and time are captured automatically.
- "search_voice_notes" = search saved voice notes by text, location, or time (e.g., "what did I note about that restaurant?" or "what notes do I have from last week?").

WhatsApp Messages: Use "send_whatsapp_message" to send text messages (and optionally photos) to contacts via WhatsApp. The contact must be saved in memory first (e.g., "remember mom's WhatsApp is +1234567890"). Photos can be included by specifying location and/or time. WhatsApp will open with the message pre-filled; the user must tap Send to confirm.

Current date: {{CURRENT_DATE_READABLE}}
''';

  static const String model = "gpt-realtime-mini-2025-12-15";

  static const String maleVoice = "echo"; // default male voice
  static const String femaleVoice = "marin"; // default female voice 
  static const List<String> supportedVoices = [femaleVoice, maleVoice];
  static bool get isMaleVoice => voice == maleVoice;
  static bool get isFemaleVoice => voice == femaleVoice;
  static String voice = femaleVoice;

  // Our server URL and preference keys
  static const serverUrl = "https://roadmate-flutter.onrender.com";
  static const prefKeyClientId = 'roadmate_client_id';
  static const prefKeyVoice = 'roadmate_voice';
  static const prefKeyInitialGreetingEnabled = 'roadmate_initial_greeting_enabled';
  static const prefKeyInitialGreetingPhrase = 'roadmate_initial_greeting_phrase';

  /// Read saved voice from SharedPreferences (call during app startup).
  static Future<void> loadSavedVoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(prefKeyVoice);
      if (saved != null && supportedVoices.contains(saved)) {
        voice = saved;
      }
    } catch (_) {
      // Keep default voice if prefs are unavailable.
    }
  }

  /// Persist and update current voice selection.
  static Future<void> setVoice(String newVoice) async {
    if (!supportedVoices.contains(newVoice)) return;
    voice = newVoice;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKeyVoice, newVoice);
    } catch (_) {
      // Ignore persistence errors; voice stays updated for this session.
    }
  }

  /// Get whether initial greeting is enabled (default: false)
  static Future<bool> getInitialGreetingEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(prefKeyInitialGreetingEnabled) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Set whether initial greeting is enabled
  static Future<void> setInitialGreetingEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(prefKeyInitialGreetingEnabled, enabled);
    } catch (_) {
      // Ignore persistence errors
    }
  }

  /// Get the initial greeting phrase (default: "Hello, how can I help you?")
  static Future<String> getInitialGreetingPhrase() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(prefKeyInitialGreetingPhrase) ?? "Hello, how can I help you?";
    } catch (_) {
      return "Hello, how can I help you?";
    }
  }

  /// Set the initial greeting phrase
  static Future<void> setInitialGreetingPhrase(String phrase) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKeyInitialGreetingPhrase, phrase);
    } catch (_) {
      // Ignore persistence errors
    }
  }

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
      "description": "Place a phone call. Try to resolve a phone number fetching from memory.",
      "parameters": {
        "type": "object",
        "properties": {
          "phone_number": {
            "type": "string",
            "description": "Phone number, e.g. +14085551234",
          },
          "contact_name": {
            "type": "string",
            "description": "Contact name",
          },
        },
        "required": ["contact_name", "phone_number"],
      },
    },
    // ---------------- Reminders tools ----------------
    {
      "type": "function",
      "name": "reminder_create",
      "description": "Create a local reminder that triggers a notification at a specific time.",
      "parameters": {
        "type": "object",
        "properties": {
          "text": {
            "type": "string",
            "description": "What to remind the user about."
          },
          "when_iso": {
            "type": "string",
            "description": "Local date/time in ISO 8601 format, e.g. 2026-01-28T18:30:00"
          }
        },
        "required": ["text", "when_iso"]
      },
    },
    {
      "type": "function",
      "name": "reminder_list",
      "description": "List all upcoming reminders.",
      "parameters": {
        "type": "object",
        "properties": {}
      },
    },
    {
      "type": "function",
      "name": "reminder_cancel",
      "description": "Cancel a previously created reminder by id.",
      "parameters": {
        "type": "object",
        "properties": {
          "id": {
            "type": "integer",
            "description": "Reminder id returned when the reminder was created."
          }
        },
        "required": ["id"]
      },
    },    
    /// YouTube tools
    {
      "type": "function",
      "name": "youtube_subscriptions_feed",
      "description": "Get the latest recommended videos from the user's YouTube subscriptions feed.",
      "parameters": {
        "type": "object",
        "properties": {},
      }
    },
    {
      "type": "function",
      "name": "youtube_open_video",
      "description": "Open a YouTube video.",
      "parameters": {
        "type": "object",
        "properties": {
          "url": {
            "type": "string",
            "description": "video URL"
          },
          "startSeconds": {
            "type": "integer",
            "description": "Optional start time in seconds. Defaults to 0."
          }
        },
        "required": ["url"]
      }
    },
    // Photo album search tool
    {
      "type": "function",
      "name": "search_photos",
      "description": "Search the user's photo album by location and/or time. Returns photos matching the criteria with their metadata.",
      "parameters": {
        "type": "object",
        "properties": {
          "location": {
            "type": "string",
            "description": "Location name or address to search for (e.g., 'San Francisco', 'Paris', 'home')"
          },
          "time_period": {
            "type": "string",
            "description": "Time period description (e.g., 'last week', 'yesterday', 'January 2024', 'last summer')"
          },
          "limit": {
            "type": "integer",
            "description": "Maximum number of photos to return (default: 10)"
          }
        }
      }
    },
    // Voice note tools (separate from memory_append/memory_fetch)
    {
      "type": "function",
      "name": "save_voice_note",
      "description": "Save a voice note — a story, narrative, or description of an event or place.",
      "parameters": {
        "type": "object",
        "properties": {
          "text": {
            "type": "string",
            "description": "The narrative or story text to save as a voice note."
          }
        },
        "required": ["text"]
      }
    },
    {
      "type": "function",
      "name": "search_voice_notes",
      "description": "Search the user's saved voice notes by text content, location, and/or time period.",
      "parameters": {
        "type": "object",
        "properties": {
          "text": {
            "type": "string",
            "description": "Keywords to search for in note content."
          },
          "location": {
            "type": "string",
            "description": "Location name or address to filter by."
          },
          "time_period": {
            "type": "string",
            "description": "Time period (e.g., 'today', 'last week', 'last month')."
          },
          "limit": {
            "type": "integer",
            "description": "Maximum number of notes to return (default: 5)."
          }
        }
      }
    },
    {
      "type": "function",
      "name": "send_whatsapp_message",
      "description": "Send a message to a WhatsApp contact saved in memory. Optionally include a photo from the album.",
      "parameters": {
        "type": "object",
        "properties": {
          "contact_name": {
            "type": "string",
            "description": "Name of the contact (will be looked up in memory)"
          },
          "message": {
            "type": "string",
            "description": "Text message to send"
          },
          "photo_location": {
            "type": "string",
            "description": "Optional: location to find photo (e.g., 'Paris', 'home')"
          },
          "photo_time": {
            "type": "string",
            "description": "Optional: time period (e.g., 'yesterday', 'last week')"
          },
          "include_sender_name": {
            "type": "boolean",
            "description": "If true, prepend 'From [Your Name]:' to message"
          }
        },
        "required": ["contact_name", "message"]
      }
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

/// Persistent per-install client id used for server-side token partitioning (Gmail, etc.).
/// No extra deps: uses Random.secure + base64url.
class ClientIdStore {
  static Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(Config.prefKeyClientId);
    if (existing != null && existing.isNotEmpty) return existing;

    // 16 bytes -> 22 chars base64url without padding (roughly)
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    final cid = base64UrlEncode(bytes).replaceAll('=', '');

    await prefs.setString(Config.prefKeyClientId, cid);
    return cid;
  }
}