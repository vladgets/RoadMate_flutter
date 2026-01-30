// lib/services/reminders_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

/// Simple Reminder model.
class Reminder {
  Reminder({
    required this.id,
    required this.text,
    required this.scheduledAtLocalIso,
    required this.createdAtLocalIso,
    this.status = ReminderStatus.scheduled,
  });

  final int id;
  final String text;

  /// ISO8601 string in *local time* (no timezone offset baked in).
  /// We store local ISO to keep UI predictable and to allow conversion via tz later.
  final String scheduledAtLocalIso;

  /// ISO8601 local timestamp for bookkeeping.
  final String createdAtLocalIso;

  ReminderStatus status;

  DateTime get scheduledAtLocal => DateTime.parse(scheduledAtLocalIso);
  DateTime get createdAtLocal => DateTime.parse(createdAtLocalIso);

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'scheduledAtLocalIso': scheduledAtLocalIso,
        'createdAtLocalIso': createdAtLocalIso,
        'status': status.name,
      };

  static Reminder fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] ?? 'scheduled').toString();
    final status = ReminderStatus.values.firstWhere(
      (e) => e.name == statusStr,
      orElse: () => ReminderStatus.scheduled,
    );

    return Reminder(
      id: (json['id'] as num).toInt(),
      text: (json['text'] ?? '').toString(),
      scheduledAtLocalIso: (json['scheduledAtLocalIso'] ?? '').toString(),
      createdAtLocalIso: (json['createdAtLocalIso'] ?? '').toString(),
      status: status,
    );
  }
}

enum ReminderStatus { scheduled, fired, canceled }

/// RoadMate local reminders service:
/// - Stores reminders in SharedPreferences
/// - Schedules local notifications using flutter_local_notifications
/// - Uses timezone package to schedule correctly with DST changes
class RemindersService {
  RemindersService._();

  static final RemindersService instance = RemindersService._();

  static const String _prefsKey = 'roadmate_reminders_v1';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _tzConfigured = false;

  /// Call once early in app lifecycle (e.g., in initState after first frame).
  Future<void> init() async {
    if (_initialized) return;

    // Timezone init (safe to call once).
    tz_data.initializeTimeZones();

    // IMPORTANT: tz.local defaults to UTC unless we set it.
    // If tz.local is UTC but the user provides local wall-clock time, scheduling can end up in the past.
    if (!_tzConfigured) {
      try {
        final tzInfo = await FlutterTimezone.getLocalTimezone();
        final String tzName = tzInfo.identifier;
        tz.setLocalLocation(tz.getLocation(tzName));
        debugPrint('[Reminders] Local timezone set to $tzName');
        debugPrint('[Reminders] tz.local is now: ${tz.local.name}');
      } catch (e) {
        // Fallback: keep tz.local as-is; scheduling may be off but app won't crash.
        debugPrint('[Reminders] Failed to set local timezone, using default tz.local. Error: $e');
      }
      _tzConfigured = true;
    }

    // Plugin init.
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);

    await _notifications.initialize(
      initSettings,
      // Optional: handle notification taps (deep-link to reminders screen)
      onDidReceiveNotificationResponse: (resp) {
        debugPrint('[Reminders] Notification tapped: ${resp.payload}');
      },
    );

    // Create Android notification channel
    const androidChannel = AndroidNotificationChannel(
      'roadmate_reminders',
      'Reminders',
      description: 'RoadMate scheduled reminders',
      importance: Importance.max,
    );

    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(androidChannel);
    }

    _initialized = true;
  }

  /// Schedule a quick test reminder 1 minute from now with the given text.
  Future<void> scheduleReminderInOneMinute(String text) async {
    await init();

    // await _notifications.cancelAll();

    // Request permission (best-effort) so notifications can show.
    final permsOk = await requestPermissions();
    debugPrint('[Test] Permissions granted: $permsOk');

    final now = DateTime.now();
    final when = now.add(const Duration(minutes: 1));

    try {
      await createReminder(text: text, whenLocal: when);
      debugPrint('[Test] Test reminder created successfully');
    } catch (e, st) {
      debugPrint('[Test] Failed to schedule test reminder: $e\n$st');
      rethrow; // if you want to propagate the error to UI
    }
  }

  /// Request notification permissions.
  /// Returns true if permissions appear granted.
  Future<bool> requestPermissions() async {
    await init();

    bool ok = true;

    // iOS/macOS permissions
    final ios = _notifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      ok = ok && (granted ?? false);
    }

    // Android 13+ runtime notification permission
    // final androidPlugin = _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    // if (androidPlugin != null) {
    //   // This is the critical check for Android 13+
    //   final bool? canScheduleExact = await androidPlugin.canScheduleExactNotifications();
    //   if (canScheduleExact == false) {
    //     // This will open the system settings page for "Alarms & Reminders"
    //     // The user MUST toggle this on for your scheduled notifications to work.
    //     await androidPlugin.requestExactAlarmsPermission(); 
    //     return false; 
    //   }
    // }

    final androidGranted =
        await _notifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission() ?? true;

    ok = ok && androidGranted;

    return ok;
  }

  /// Create + schedule a reminder notification.
  ///
  /// [whenLocal] should be a DateTime in the user's local time.
  /// Returns the created Reminder.
  Future<Reminder> createReminder({
    required String text,
    required DateTime whenLocal,
  }) async {
    await init();

    final id = _makeId(whenLocal);
    final now = DateTime.now();

    final reminder = Reminder(
      id: id,
      text: text.trim(),
      scheduledAtLocalIso: _toLocalIso(whenLocal),
      createdAtLocalIso: _toLocalIso(now),
      status: ReminderStatus.scheduled,
    );

    // Persist first, but avoid duplicates for the same id.
    final all = await _loadAll();
    all.removeWhere((r) => r.id == reminder.id);
    all.add(reminder);
    await _saveAll(all);

    // Schedule notification. If scheduling fails, roll back the persisted reminder
    // so repeated attempts don't create multiple entries.
    try {
      await _scheduleNotification(reminder);
    } catch (e) {
      debugPrint('[Reminders] Failed to schedule notification: $e');
      final rollback = await _loadAll();
      rollback.removeWhere((r) => r.id == reminder.id);
      await _saveAll(rollback);
      rethrow;
    }

    return reminder;
  }

  /// Cancel a reminder (also cancels the underlying scheduled notification).
  Future<void> cancelReminder(int id) async {
    await init();

    await _notifications.cancel(id);

    final all = await _loadAll();
    for (final r in all) {
      if (r.id == id) {
        r.status = ReminderStatus.canceled;
      }
    }
    await _saveAll(all);
  }

  /// Returns upcoming reminders (scheduledAt >= now and status == scheduled).
  Future<List<Reminder>> listUpcoming() async {
    final all = await _loadAll();
    final now = DateTime.now();

    final upcoming = all
        .where((r) =>
            r.status == ReminderStatus.scheduled &&
            r.scheduledAtLocal.isAfter(now))
        .toList();

    upcoming.sort((a, b) => a.scheduledAtLocal.compareTo(b.scheduledAtLocal));
    return upcoming;
  }

  /// Returns all reminders including canceled/fired.
  Future<List<Reminder>> listAll() async {
    final all = await _loadAll();
    all.sort((a, b) => a.scheduledAtLocal.compareTo(b.scheduledAtLocal));
    return all;
  }

  /// Optional cleanup: remove reminders that are canceled or long past.
  Future<void> prune({Duration olderThan = const Duration(days: 7)}) async {
    final all = await _loadAll();
    final cutoff = DateTime.now().subtract(olderThan);

    final kept = all.where((r) {
      if (r.status == ReminderStatus.scheduled) return true;
      // Keep fired/canceled only for a while for audit/debug UX.
      return r.scheduledAtLocal.isAfter(cutoff);
    }).toList();

    await _saveAll(kept);
  }

  // -----------------------
  // Internal implementation
  // -----------------------

  int _makeId(DateTime whenLocal) {
    // Use milliseconds for uniqueness but constrain to 32-bit signed int range.
    // This matches what many notification systems expect.
    final ms = whenLocal.millisecondsSinceEpoch;
    final id = ms % 2147483647; // 2^31-1
    return id == 0 ? 1 : id;
  }

  String _toLocalIso(DateTime dt) {
    final local = dt.toLocal();
    // No offset stored; parse later as local.
    // ISO8601 without timezone offset:
    return DateTime(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
      local.second,
      local.millisecond,
      local.microsecond,
    ).toIso8601String();
  }

  Future<void> _scheduleNotification(Reminder r) async {
    // Convert local DateTime -> tz.TZDateTime in local location.
    final localLocation = tz.local;
    final scheduledLocal = r.scheduledAtLocal;

    var tzWhen = tz.TZDateTime(
      localLocation,
      scheduledLocal.year,
      scheduledLocal.month,
      scheduledLocal.day,
      scheduledLocal.hour,
      scheduledLocal.minute,
      scheduledLocal.second,
      scheduledLocal.millisecond,
      scheduledLocal.microsecond,
    );

    // Guard: some platforms/plugins reject scheduling at or before "now".
    final nowTz = tz.TZDateTime.now(localLocation);
    if (!tzWhen.isAfter(nowTz)) {
      tzWhen = nowTz.add(const Duration(seconds: 5));
    }

    const androidDetails = AndroidNotificationDetails(
      'roadmate_reminders',
      'Reminders',
      channelDescription: 'RoadMate scheduled reminders',
      importance: Importance.max,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    Future<void> scheduleWithMode(AndroidScheduleMode mode) async {
      await _notifications.zonedSchedule(
        r.id,
        'Reminder',
        r.text,
        tzWhen,
        details,
        payload: jsonEncode({'reminder_id': r.id}),
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        // MatchDateTimeComponents is for repeating schedules; keep null for one-shot.
        matchDateTimeComponents: null,
      );
    }

    // Use inexact alarms to avoid Android 12+ exact-alarm permission friction.
    await scheduleWithMode(AndroidScheduleMode.inexactAllowWhileIdle);
    // await scheduleWithMode(AndroidScheduleMode.exactAllowWhileIdle);


    // Log pending internal queue
    final pending = await _notifications.pendingNotificationRequests();
    debugPrint('[Reminders] Pending notifications count: ${pending.length}');
    for (final p in pending) {
      debugPrint('[Reminders] Pending: id=${p.id}, title=${p.title}, body=${p.body}');
    }

    debugPrint('[Reminders] Scheduled id=${r.id} at ${r.scheduledAtLocalIso}');
  }

  Future<List<Reminder>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return <Reminder>[];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <Reminder>[];

      return decoded
          .whereType<Map>()
          .map((m) => Reminder.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      debugPrint('[Reminders] Failed to decode reminders: $e');
      return <Reminder>[];
    }
  }

  Future<void> _saveAll(List<Reminder> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(reminders.map((r) => r.toJson()).toList());
    await prefs.setString(_prefsKey, encoded);
  }


  // -----------------------
  // Tool handlers (for Realtime function calls)
  // -----------------------

  /// Tool: reminder_create
  /// Expected args:
  /// {
  ///   "text": "Call dentist",
  ///   "when_iso": "2026-01-28T18:30:00"   // local time ISO8601 (recommended)
  /// }
  /// Optional args:
  /// - "request_permissions": true/false (default true)
  Future<Map<String, dynamic>> toolCreate(dynamic args) async {
    await init();

    Map<String, dynamic> a;
    if (args == null) {
      a = <String, dynamic>{};
    } else if (args is Map<String, dynamic>) {
      a = args;
    } else if (args is Map) {
      a = args.cast<String, dynamic>();
    } else if (args is String && args.trim().isNotEmpty) {
      a = jsonDecode(args) as Map<String, dynamic>;
    } else {
      a = <String, dynamic>{};
    }

    final text = (a['text'] ?? a['message'] ?? '').toString().trim();
    final whenIso = (a['when_iso'] ?? a['when'] ?? '').toString().trim();
    final requestPerms = a['request_permissions'] == null
        ? true
        : (a['request_permissions'] == true);

    if (text.isEmpty) {
      throw Exception('reminder_create: missing "text"');
    }
    if (whenIso.isEmpty) {
      throw Exception('reminder_create: missing "when_iso"');
    }

    // Ask for notification permission if needed (best-effort).
    if (requestPerms) {
      final ok = await requestPermissions();
      if (!ok) {
        return {
          'ok': false,
          'error': 'Notifications permission not granted.',
        };
      }
    }

    final whenLocal = DateTime.parse(whenIso).toLocal();
    if (!whenLocal.isAfter(DateTime.now())) {
      return {
        'ok': false,
        'error': 'Reminder time must be in the future.',
      };
    }

    final r = await createReminder(text: text, whenLocal: whenLocal);
    return {
      'ok': true,
      'reminder': r.toJson(),
    };
  }

  /// Tool: reminder_list
  /// Returns { "reminders": [...] }
  Future<Map<String, dynamic>> toolList() async {
    final upcoming = await listUpcoming();
    return {
      'ok': true,
      'reminders': upcoming.map((r) => r.toJson()).toList(),
    };
  }

  /// Tool: reminder_cancel
  /// Expected args: { "id": 123 }
  Future<Map<String, dynamic>> toolCancel(dynamic args) async {
    await init();

    Map<String, dynamic> a;
    if (args == null) {
      a = <String, dynamic>{};
    } else if (args is Map<String, dynamic>) {
      a = args;
    } else if (args is Map) {
      a = args.cast<String, dynamic>();
    } else if (args is String && args.trim().isNotEmpty) {
      a = jsonDecode(args) as Map<String, dynamic>;
    } else {
      a = <String, dynamic>{};
    }

    final idVal = a['id'];
    if (idVal == null) {
      throw Exception('reminder_cancel: missing "id"');
    }

    final id = (idVal is num) ? idVal.toInt() : int.parse(idVal.toString());
    await cancelReminder(id);

    return {
      'ok': true,
      'id': id,
    };
  }
}
