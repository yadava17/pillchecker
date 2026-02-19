import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pillchecker/constants/prefs_keys.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void>? _initFuture;
  static bool _permissionRequestInProgress = false;

  static const String _channelId = 'pill_reminders_v2';
  static const String _channelName = 'Pill Reminders';
  static const String _channelDesc = 'Daily pill reminder notifications';

  // ---- In-memory settings (defaults) ----
  static String _mode = 'standard'; // default
  static Duration _earlyLead = const Duration(minutes: 30);
  static Duration _lateAfter = const Duration(minutes: 30);

  static String get mode => _mode;
  static Duration get earlyLead => _earlyLead;
  static Duration get lateAfter => _lateAfter;

static Future<void> init() {
  // ✅ single-flight: if init is already running, everyone awaits the same Future
  _initFuture ??= _initInternal();
  return _initFuture!;
}

static Future<void> _initInternal() async {
  if (_initialized) return;

  await _configureLocalTimeZone();

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const darwinInit = DarwinInitializationSettings();

  const initSettings = InitializationSettings(
    android: androidInit,
    iOS: darwinInit,
    macOS: darwinInit,
  );

  await _plugin.initialize(
    settings: initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse r) {},
  );

  await requestPermissions();

  // Load saved notification mode + early/late timings
  await loadUserNotificationSettings();

  _initialized = true;
}


  static Future<void> loadUserNotificationSettings() async {
    final prefs = await SharedPreferences.getInstance();

    _mode = prefs.getString(kNotifModeKey) ?? 'standard';

    final earlyMin = prefs.getInt(kEarlyLeadMinKey) ?? 30;
    final lateMin = prefs.getInt(kLateAfterMinKey) ?? 30;

    _earlyLead = Duration(minutes: earlyMin.clamp(0, 240));
    _lateAfter = Duration(minutes: lateMin.clamp(0, 240));

    debugPrint(
      'NOTIF SETTINGS LOADED: mode=$_mode '
      'earlyMin=${_earlyLead.inMinutes} lateMin=${_lateAfter.inMinutes}',
    );
  }

static Future<void> requestPermissions() async {
  // ✅ prevent double-request (Android will crash with permissionRequestInProgress)
  if (_permissionRequestInProgress) return;
  _permissionRequestInProgress = true;

  try {
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    if (Platform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  } finally {
    _permissionRequestInProgress = false;
  }
}


  //  MULTI-NOTIFICATION (EARLY/LATE) — DAILY VERSION
  //
  // IMPORTANT: These use matchDateTimeComponents: DateTimeComponents.time
  // which means they repeat daily at the computed EARLY/LATE clock time.
  //
  // That is exactly what you want for now (daily repeating).
  // Later (calendar/logging), we can switch to per-day instances if needed.

  static Future<void> scheduleDailyDoseEarlyReminder({
    required int id,
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    required int totalDoses,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();

    // Load latest saved early/late times so edits apply immediately
    await loadUserNotificationSettings();

    // Early clock time (wrap across midnight safely)
    final earlyTime = _shiftTimeOfDay(time, -_earlyLead);
    final scheduled = _nextInstanceOfTime(earlyTime);

    final body = (totalDoses <= 1)
        ? "Almost time to take $pillName!"
        : "Almost time to take dose $doseNumber1Based of $pillName!";

    await _plugin.zonedSchedule(
      id: id,
      title: 'PillChecker',
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // ✅ daily repeat
    );
  }

  static Future<void> scheduleDailyDoseLateReminder({
    required int id,
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    required int totalDoses,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();

    // Load latest saved early/late times so edits apply immediately
    await loadUserNotificationSettings();

    // Late clock time (wrap across midnight safely)
    final lateTime = _shiftTimeOfDay(time, _lateAfter);
    final scheduled = _nextInstanceOfTime(lateTime);

    final body = (totalDoses <= 1)
        ? "You haven't checked $pillName yet! Check it off before it's too late!"
        : "You haven't checked dose $doseNumber1Based of $pillName yet! Check it off before it's too late!";

    await _plugin.zonedSchedule(
      id: id,
      title: 'PillChecker',
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // ✅ daily repeat
    );
  }

  // (KEEP) one-shot versions you were testing with — unchanged behavior
  // ✅ Removed redundant helper usage + added debug prints
  static Future<void> scheduleDoseEarlyReminder({
    required int id,
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    required int totalDoses,
    required int minutesBefore,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();

    final now = tz.TZDateTime.now(tz.local);

    // Next base dose instance (today or tomorrow)
    final base = _nextDoseInstance(time);

    // Early instance (may land today or tomorrow depending on base)
    final when = base.subtract(Duration(minutes: minutesBefore));

    final body = (totalDoses <= 1)
        ? "Almost time to take $pillName!"
        : "Almost time to take dose $doseNumber1Based of $pillName!";

    debugPrint(
      'ONE-SHOT EARLY: id=$id pill=$pillName dose=$doseNumber1Based '
      'base=${base.toIso8601String()} '
      'minutesBefore=$minutesBefore '
      'scheduled=${when.toIso8601String()} now=${now.toIso8601String()}',
    );

    await _plugin.zonedSchedule(
      id: id,
      title: 'PillChecker',
      body: body,
      scheduledDate: when,
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  // Put this anywhere inside NotificationService class
  static Future<void> debugDumpPending([String tag = '']) async {
    await init();
    final pending = await _plugin.pendingNotificationRequests();

    debugPrint('NOTIF DUMP $tag: pending=${pending.length}');
    for (final p in pending) {
      debugPrint('  -> id=${p.id} title=${p.title} body=${p.body}');
    }
  }

  static Future<void> scheduleDoseLateReminder({
    required int id,
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    required int totalDoses,
    required int minutesAfter,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();

    final now = tz.TZDateTime.now(tz.local);

    // Next base dose instance (today or tomorrow)
    final base = _nextDoseInstance(time);

    // Late instance
    final when = base.add(Duration(minutes: minutesAfter));

    final body = (totalDoses <= 1)
        ? "You haven't checked $pillName yet!"
        : "You haven't checked dose $doseNumber1Based of $pillName yet!";

    debugPrint(
      'ONE-SHOT LATE: id=$id pill=$pillName dose=$doseNumber1Based '
      'base=${base.toIso8601String()} '
      'minutesAfter=$minutesAfter '
      'scheduled=${when.toIso8601String()} now=${now.toIso8601String()}',
    );

    await _plugin.zonedSchedule(
      id: id,
      title: 'PillChecker',
      body: body,
      scheduledDate: when,
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  // Helper: next dose time (today or tomorrow)
  static tz.TZDateTime _nextDoseInstance(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  // ✅ HARD REQUIREMENT: exact alarms must be allowed, or we throw (no inexact fallback).
  static Future<void> _requireExactAlarmsOnAndroid() async {
    if (!Platform.isAndroid) return;

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (android == null) return;

    final can =
        await android.canScheduleExactNotifications() ??
        false; // :contentReference[oaicite:1]{index=1}
    if (can) return;

    await android
        .requestExactAlarmsPermission(); // :contentReference[oaicite:2]{index=2}

    final canAfter = await android.canScheduleExactNotifications() ?? false;
    if (!canAfter) {
      throw StateError(
        'Exact alarms are not permitted. Enable: Settings > Apps > Special access > Alarms & reminders (allow PillChecker).',
      );
    }
  }

Updated upstream
  static NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('pillchecker_notification'),
      ),
      iOS: DarwinNotificationDetails(
        presentSound: true,
        sound: 'pillchecker_notification.wav',
      ),
    );
  }

static NotificationDetails _details() {
  return const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      sound: RawResourceAndroidNotificationSound('pillchecker_notification'),
    ),
    iOS: DarwinNotificationDetails(
      presentSound: true,
      sound: 'pillchecker_notification.wav',
    ),
  );
}

Stashed changes

  // ---- DEBUG: schedule a one-shot test for N seconds/minutes from now ----
  static Future<void> scheduleTestIn(Duration fromNow) async {
    await init();
    await _requireExactAlarmsOnAndroid();

    final when = tz.TZDateTime.now(tz.local).add(fromNow);

    await _plugin.zonedSchedule(
      id: 9999,
      title: 'PillChecker',
      body: 'Test scheduled for ${fromNow.inSeconds}s from now',
      scheduledDate: when,
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    ); // exactAllowWhileIdle requires exact alarm permission :contentReference[oaicite:3]{index=3}
  }

  // ---- REAL API: daily reminder at a time ----
  static Future<void> scheduleDailyPillReminder({
    required int id,
    required String pillName,
    required TimeOfDay time,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();

    final scheduled = _nextInstanceOfTime(time);

    debugPrint(
      'NOTIF: scheduling EXACT id=$id at ${scheduled.toIso8601String()}',
    );

    await _plugin.zonedSchedule(
      id: id,
      title: 'PillChecker',
      body: "It's time to take $pillName!",
      scheduledDate: scheduled,
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // daily repeat
    );
  }

  static Future<void> scheduleDailyDoseReminder({
    required int id,
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    int? totalDoses, //  add this
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();

    final scheduled = _nextInstanceOfTime(time);

    final isSingleDose = (totalDoses != null && totalDoses <= 1);

    final body = isSingleDose
        ? "It's time to take $pillName!"
        : "It's time to take dose $doseNumber1Based of $pillName!";

    await _plugin.zonedSchedule(
      id: id,
      title: 'PillChecker',
      body: body,
      scheduledDate: scheduled,
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id: id);
  }

  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
    debugPrint('NOTIF: cancelAll() complete');
  }

  static TimeOfDay _shiftTimeOfDay(TimeOfDay t, Duration delta) {
    final base = t.hour * 60 + t.minute;
    final add = delta.inMinutes;

    // wrap into 0..1439
    var mins = (base + add) % (24 * 60);
    if (mins < 0) mins += 24 * 60;

    return TimeOfDay(hour: mins ~/ 60, minute: mins % 60);
  }

  static tz.TZDateTime _nextInstanceOfTime(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  static tz.TZDateTime _nextInstanceOfTimeWithOffset(
    TimeOfDay base,
    Duration offset,
  ) {
    final now = tz.TZDateTime.now(tz.local);

    // Start from the next occurrence of the base time (today or tomorrow)
    final baseNext = _nextInstanceOfTime(base);

    // Apply offset (can be negative)
    var scheduled = baseNext.add(offset);

    // If the offset pushed us into the past, bump by 1 day
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  static tz.TZDateTime _nextInstanceOfTimeOffset(
    TimeOfDay doseTime, {
    int minutesBefore = 0,
    int minutesAfter = 0,
  }) {
    final now = tz.TZDateTime.now(tz.local);

    // Build a DateTime for today at the dose time
    var base = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      doseTime.hour,
      doseTime.minute,
    );

    // Apply offset
    base = base
        .subtract(Duration(minutes: minutesBefore))
        .add(Duration(minutes: minutesAfter));

    // If it's already passed, schedule for next day (same offset relative to dose time)
    if (base.isBefore(now)) {
      base = base.add(const Duration(days: 1));
    }

    return base;
  }

  static Future<void> _configureLocalTimeZone() async {
    if (Platform.isWindows || Platform.isLinux) return;

    tzdata.initializeTimeZones();

    try {
      final dynamic tzInfo = await FlutterTimezone.getLocalTimezone();

      final String tzName = (tzInfo is String)
          ? tzInfo
          : ((tzInfo?.identifier as String?) ?? 'UTC');

      final safe = tzName.isEmpty ? 'UTC' : tzName;

      tz.setLocalLocation(tz.getLocation(safe));
    } catch (e) {
      // fallback that will never hang startup
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }
}
