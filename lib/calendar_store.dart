import 'package:device_calendar/device_calendar.dart';

class CalendarStore {
  static final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();

  /// Safely convert a value to String, handling null
  static String _safeString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  /// Check if calendar permissions are granted
  static Future<bool> hasPermissions() async {
    final permissions = await _deviceCalendarPlugin.hasPermissions();
    return permissions.data ?? false;
  }

  /// Request calendar permissions
  static Future<bool> requestPermissions() async {
    final result = await _deviceCalendarPlugin.requestPermissions();
    return result.data ?? false;
  }

  /// Tool-compatible wrapper: get calendar events
  /// Returns events for the current date ±30 days
  static Future<Map<String, dynamic>> toolGetCalendarData() async {
    try {
      // Check permissions
      bool hasPermission = await hasPermissions();
      if (!hasPermission) {
        hasPermission = await requestPermissions();
      }

      if (!hasPermission) {
        return {
          'ok': false,
          'error': 'Calendar permission denied',
        };
      }

      // Get list of calendars
      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      if (!calendarsResult.isSuccess) {
        final errorMsg = calendarsResult.errors.isNotEmpty 
            ? calendarsResult.errors.join(", ")
            : "Unknown error";
        return {
          'ok': false,
          'error': 'Failed to retrieve calendars: $errorMsg',
        };
      }

      if (calendarsResult.data == null) {
        return {
          'ok': false,
          'error': 'No calendars data returned',
        };
      }

      final calendars = calendarsResult.data!;
      if (calendars.isEmpty) {
        return {
          'ok': true,
          'events': [],
          'count': 0,
          'message': 'No calendars found on device',
        };
      }

      // Log all found calendars
      // ignore: avoid_print
      print('>>> Found ${calendars.length} calendars:');
      for (final cal in calendars) {
        // ignore: avoid_print
        print('  - ${cal.name ?? "Unknown"} (id: ${cal.id ?? "null"}, readOnly: ${cal.isReadOnly}, color: ${cal.color})');
      }

      // Calculate date range: today ±30 days
      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
      final endDate = DateTime(now.year, now.month, now.day).add(const Duration(days: 30));

      // Retrieve events from all calendars
      final List<Map<String, dynamic>> allEvents = [];
      final Map<String, int> calendarEventCounts = {};

      for (final calendar in calendars) {
        // Process all calendars, including read-only ones (they can still have events)
        if (calendar.id == null || calendar.id!.isEmpty) {
          // ignore: avoid_print
          print('>>> Skipping calendar ${calendar.name}: no valid ID');
          continue; // Skip calendars without valid ID
        }

        final calendarName = calendar.name ?? 'Unknown';
        try {
          // ignore: avoid_print
          print('>>> Retrieving events from calendar: $calendarName (id: ${calendar.id})');
          
          final eventsResult = await _deviceCalendarPlugin.retrieveEvents(
            calendar.id!,
            RetrieveEventsParams(
              startDate: startDate,
              endDate: endDate,
            ),
          );

          if (!eventsResult.isSuccess) {
            // Log but continue - some calendars may not be accessible
            // ignore: avoid_print
            print('>>> Failed to retrieve events from calendar $calendarName: ${eventsResult.errors.join(", ")}');
            calendarEventCounts[calendarName] = 0;
            continue;
          }

          if (eventsResult.data == null) {
            // ignore: avoid_print
            print('>>> Calendar $calendarName: data is null');
            calendarEventCounts[calendarName] = 0;
            continue; // No events or data is null
          }

          // Get events list - this may throw if there are parsing errors
          List<Event>? events;
          try {
            events = eventsResult.data;
            if (events == null) {
              // ignore: avoid_print
              print('>>> Calendar $calendarName: data is null');
              calendarEventCounts[calendarName] = 0;
              continue;
            }
            // ignore: avoid_print
            print('>>> Calendar $calendarName: found ${events.length} events');
          } catch (e) {
            // ignore: avoid_print
            print('>>> Calendar $calendarName: error accessing events list: $e');
            calendarEventCounts[calendarName] = 0;
            continue;
          }
          
          if (events.isEmpty) {
            calendarEventCounts[calendarName] = 0;
            continue; // No events in this calendar
          }

          int processedCount = 0;
          int failedCount = 0;
          // Process events by index to handle parsing errors in device_calendar
          // Some events may fail to parse when accessed, so we try each one individually
          for (int i = 0; i < events.length; i++) {
            try {
              // Access event by index - this may throw if event parsing failed during lazy evaluation
              final event = events[i];
              
              // Safely extract event data, handling all possible null values
              final eventMap = <String, dynamic>{
                'title': _safeString(event.title),
                'start': event.start != null ? event.start!.toIso8601String() : '',
                'end': event.end != null ? event.end!.toIso8601String() : '',
                'description': _safeString(event.description),
                'location': _safeString(event.location),
                'calendar': calendarName,
              };
              allEvents.add(eventMap);
              processedCount++;
            } catch (e, stackTrace) {
              // Log error for individual event but continue processing
              failedCount++;
              // ignore: avoid_print
              print('>>> Error processing event #$i from calendar $calendarName: $e');
              // Only print stack trace for first few errors to reduce log spam
              if (failedCount <= 3) {
                // ignore: avoid_print
                print('Stack trace: $stackTrace');
              }
            }
          }
          calendarEventCounts[calendarName] = processedCount;
          if (failedCount > 0) {
            // ignore: avoid_print
            print('>>> Calendar $calendarName: processed $processedCount/${events.length} events successfully ($failedCount failed)');
          } else {
            // ignore: avoid_print
            print('>>> Calendar $calendarName: processed $processedCount events successfully');
          }
        } catch (e, stackTrace) {
          // Log error but continue with other calendars
          // ignore: avoid_print
          print('>>> Error retrieving events from calendar $calendarName: $e');
          // ignore: avoid_print
          print('Stack trace: $stackTrace');
          calendarEventCounts[calendarName] = 0;
        }
      }

      // Log summary
      // ignore: avoid_print
      print('>>> Calendar events summary:');
      for (final entry in calendarEventCounts.entries) {
        // ignore: avoid_print
        print('  - ${entry.key}: ${entry.value} events');
      }
      // ignore: avoid_print
      print('>>> Total events collected: ${allEvents.length}');

      // Sort events by start date (only if we have events)
      if (allEvents.isNotEmpty) {
        allEvents.sort((a, b) {
          final aStart = a['start'] as String;
          final bStart = b['start'] as String;
          if (aStart.isEmpty && bStart.isEmpty) return 0;
          if (aStart.isEmpty) return 1;
          if (bStart.isEmpty) return -1;
          return aStart.compareTo(bStart);
        });
      }

      return {
        'ok': true,
        'events': allEvents,
        'count': allEvents.length,
        'date_range': {
          'start': startDate.toIso8601String(),
          'end': endDate.toIso8601String(),
        },
      };
    } catch (e) {
      return {
        'ok': false,
        'error': e.toString(),
      };
    }
  }
}


