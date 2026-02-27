import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pillchecker/constants/prefs_keys.dart';

enum _Kind { early, main, late }

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
  static String _mode = 'standard'; // off | basic | standard
  static Duration _earlyLead = const Duration(minutes: 30);
  static Duration _lateAfter = const Duration(minutes: 30);

  static String get mode => _mode;
  static Duration get earlyLead => _earlyLead;
  static Duration get lateAfter => _lateAfter;

  // ============================================================
  // TODAY + TOMORROW WINDOW (2 days)
  // ============================================================

  static const int _windowDays = 2; // today + tomorrow
  static const int _inactivityDays = 1;
  static const int _cancelDayBuckets = 3;
  // cancel offsets 0..2 so we safely cover both patterns:
  // (today+tomorrow) OR (tomorrow+dayAfter)

  static const int _inactivityWarningId = 2_146_987_321; // unique + stable
  static const Duration _inactivityWarnAfter = Duration(days: 1);
  static const Duration _inactivityAfterLateBuffer = Duration(minutes: 15);

  // Deterministic IDs (no collisions, always cancellable).
  // Layout: dayBucket + pillBucket + doseBucket + kind
  static const int _idStrideDay = 100000; // separates dayOffset cleanly
  static const int _idStridePill = 1000; // room for many doses inside a pill
  static const int _idStrideDose = 10; // room for 3 kinds

  static int _idFor({
    required int dayOffset, // 0=today, 1=tomorrow
    required int pillSlot, // 0..N-1 (index in pillNames list)
    required int doseIndex, // 0..timesPerDay-1
    required _Kind kind, // early/main/late
  }) {
    return (dayOffset * _idStrideDay) +
        (pillSlot * _idStridePill) +
        (doseIndex * _idStrideDose) +
        kind.index; // 0..2
  }

  // ============================================================
  // Init
  // ============================================================

  static Future<void> init() {
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
    if (_permissionRequestInProgress) return;
    _permissionRequestInProgress = true;

    try {
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
      }

      if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }

      if (Platform.isMacOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } finally {
      _permissionRequestInProgress = false;
    }
  }

  // ============================================================
  // Window primitives
  // ============================================================

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static tz.TZDateTime _atLocalDayTime(DateTime day, TimeOfDay t) {
    return tz.TZDateTime(
      tz.local,
      day.year,
      day.month,
      day.day,
      t.hour,
      t.minute,
    );
  }

  static Future<void> _scheduleOneShot({
    required int id,
    required tz.TZDateTime when,
    required String title,
    required String body,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();

    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: when,
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      title: title,
      body: body,
    );
  }

  // Cancel 2-day window for one pill
  static Future<void> cancelWindowForPill({
    required int pillSlot,
    required int dosesPerDay,
  }) async {
    await init();
    for (int dayOffset = 0; dayOffset < _windowDays; dayOffset++) {
      for (int d = 0; d < dosesPerDay; d++) {
        for (final kind in _Kind.values) {
          await cancel(
            _idFor(
              dayOffset: dayOffset,
              pillSlot: pillSlot,
              doseIndex: d,
              kind: kind,
            ),
          );
        }
      }
    }
  }

  static TimeOfDay _parse24h(String hhmm) {
    final hh = int.parse(hhmm.substring(0, 2));
    final mm = int.parse(hhmm.substring(3, 5));
    return TimeOfDay(hour: hh, minute: mm);
  }

  static bool _isInPastToday(DateTime day, TimeOfDay t) {
    final now = tz.TZDateTime.now(tz.local);
    final when = _atLocalDayTime(day, t);
    return when.isBefore(now);
  }

  static Future<void> _scheduleTripletOneDay({
    required int dayOffset,
    required int pillSlot,
    required int doseIndex,
    required int totalDoses,
    required String pillName,
    required TimeOfDay doseTime,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();
    await loadUserNotificationSettings();

    if (_mode == 'off') return;

    final today = _dayOnly(DateTime.now());
    final day = today.add(Duration(days: dayOffset));

    final doseNumber1 = doseIndex + 1;
    final isSingle = totalDoses <= 1;

    final bodyMain = isSingle
        ? "It's time to take $pillName!"
        : "It's time to take dose $doseNumber1 of $pillName!";

    final bodyEarly = isSingle
        ? "Almost time to take $pillName!"
        : "Almost time to take dose $doseNumber1 of $pillName!";

    final bodyLate = isSingle
        ? "You haven't checked $pillName yet! Check it off before it's too late!"
        : "You haven't checked dose $doseNumber1 of $pillName yet! Check it off before it's too late!";

    final earlyTime = shiftTimeOfDay(doseTime, -_earlyLead);
    final lateTime = shiftTimeOfDay(doseTime, _lateAfter);

    // Do not “roll” times forward. We only want *this day’s* events.
    // If time already passed for today, skip it (tomorrow will cover it).
    Future<void> scheduleIfValid({
      required _Kind kind,
      required TimeOfDay t,
      required String body,
    }) async {
      if (dayOffset == 0 && _isInPastToday(day, t)) return;

      if (_mode == 'basic' && kind != _Kind.main) return;

      final id = _idFor(
        dayOffset: dayOffset,
        pillSlot: pillSlot,
        doseIndex: doseIndex,
        kind: kind,
      );

      final when = _atLocalDayTime(day, t);

      await _scheduleOneShot(
        id: id,
        when: when,
        title: 'PillChecker',
        body: body,
      );
    }

    await scheduleIfValid(kind: _Kind.early, t: earlyTime, body: bodyEarly);
    await scheduleIfValid(kind: _Kind.main, t: doseTime, body: bodyMain);
    await scheduleIfValid(kind: _Kind.late, t: lateTime, body: bodyLate);
  }

  // ============================================================
  // ✅ PUBLIC API: rebuild today+tomorrow for ALL pills
  // Call this from HomeScreen Sync after loading prefs pill lists.
  // ============================================================

  static Future<void> rebuild2DayWindow({
    required List<String> pillNames,
    required List<List<String>> doseTimes24h, // "HH:mm" per dose
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();
    await loadUserNotificationSettings();

    final today = _dayOnly(DateTime.now());

    // ---------------------------
    // A) Decide whether "today" still has ANY valid future notification time
    // If not, start scheduling from tomorrow (so you still get 2 full future days).
    // ---------------------------
    bool hasAnythingLeftToday = false;

    for (int pillSlot = 0; pillSlot < pillNames.length; pillSlot++) {
      final times = doseTimes24h[pillSlot];
      final totalDoses = times.length;

      for (int doseIndex = 0; doseIndex < times.length; doseIndex++) {
        final doseTime = _parse24h(times[doseIndex]);

        // basic/off rules
        if (_mode == 'off') break;

        // MAIN
        if (!_isInPastToday(today, doseTime)) {
          hasAnythingLeftToday = true;
          break;
        }

        // EARLY/LATE only matter in standard mode
        if (_mode == 'standard') {
          final earlyTime = shiftTimeOfDay(doseTime, -_earlyLead);
          final lateTime = shiftTimeOfDay(doseTime, _lateAfter);

          if (!_isInPastToday(today, earlyTime) ||
              !_isInPastToday(today, lateTime)) {
            hasAnythingLeftToday = true;
            break;
          }
        }
      }

      if (hasAnythingLeftToday) break;
    }

    final startOffset = hasAnythingLeftToday ? 0 : 1;

    debugPrint(
      'NOTIF: rebuild2DayWindow startOffset=$startOffset '
      '(0=today+tomorrow, 1=tomorrow+dayAfter)',
    );

    // ---------------------------
    // B) Cancel existing buckets that we might have scheduled previously.
    // We cancel offsets 0..2 to handle switching between patterns safely.
    // ---------------------------
    for (int pillSlot = 0; pillSlot < pillNames.length; pillSlot++) {
      final dosesPerDay = doseTimes24h[pillSlot].length;

      for (int dayOffset = 0; dayOffset < _cancelDayBuckets; dayOffset++) {
        for (int d = 0; d < dosesPerDay; d++) {
          for (final kind in _Kind.values) {
            await cancel(
              _idFor(
                dayOffset: dayOffset,
                pillSlot: pillSlot,
                doseIndex: d,
                kind: kind,
              ),
            );
          }
        }
      }
    }

    // ---------------------------
    // C) Schedule exactly 2 days: startOffset and startOffset+1
    // ---------------------------
    for (int i = 0; i < _windowDays; i++) {
      final dayOffset = startOffset + i;

      for (int pillSlot = 0; pillSlot < pillNames.length; pillSlot++) {
        final pillName = pillNames[pillSlot];
        final times = doseTimes24h[pillSlot];
        final totalDoses = times.length;

        for (int doseIndex = 0; doseIndex < times.length; doseIndex++) {
          final doseTime = _parse24h(times[doseIndex]);

          await _scheduleTripletOneDay(
            dayOffset: dayOffset,
            pillSlot: pillSlot,
            doseIndex: doseIndex,
            totalDoses: totalDoses,
            pillName: pillName,
            doseTime: doseTime,
          );
        }
      }
    }

    // ✅ Always re-arm the inactivity warning whenever we rebuild the window
    await rescheduleInactivityWarning(doseTimes24h: doseTimes24h);
    debugPrint('NOTIF: rebuild2DayWindow complete');
  }

  static Future<void> rescheduleInactivityWarning({
    required List<List<String>> doseTimes24h,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();
    await loadUserNotificationSettings();

    // Always kill old warning first (fixed ID)
    await cancel(_inactivityWarningId);

    // If notifs are off OR no pills, don't schedule warning.
    if (_mode == 'off') return;
    if (doseTimes24h.isEmpty) return;

    // Find the latest "late time" across all doses.
    // - standard: use (dose + lateAfter)
    // - basic: no late exists, so use main dose time as the "latest"
    TimeOfDay? latest;

    for (final timesForPill in doseTimes24h) {
      for (final hhmm in timesForPill) {
        final dose = _parse24h(hhmm);

        final candidate = (_mode == 'standard')
            ? shiftTimeOfDay(dose, _lateAfter)
            : dose;

        if (latest == null || _toMins(candidate) > _toMins(latest)) {
          latest = candidate;
        }
      }
    }

    if (latest == null) return;

    // Warning should be ~5-10 min AFTER the latest late.
    final shifted = _shiftWithDayDelta(latest, _inactivityAfterLateBuffer);

    final today = _dayOnly(DateTime.now());
    final targetDay = today.add(
      Duration(days: _inactivityDays + shifted.dayDelta),
    );

    final when = _atLocalDayTime(targetDay, shifted.time);

    await _scheduleOneShot(
      id: _inactivityWarningId,
      when: when,
      title: 'PillChecker',
      body:
          'Warning: Notifications will stop tomorrow due to 2 days of inactivity. '
          'Open PillChecker again to keep receiving reminders!',
    );

    debugPrint(
      'NOTIF: inactivity warning scheduled id=$_inactivityWarningId '
      'when=${when.toIso8601String()} (latestBase=${latest.hour}:${latest.minute})',
    );
  }

  // ============================================================
  // ✅ PUBLIC API: mute remaining notifications today
  // - muteRemainingDoses=false: cancels only this dose’s early/main/late today
  // - muteRemainingDoses=true : cancels this dose + all later doses today
  // ============================================================

  static Future<void> muteToday({
    required int pillSlot,
    required int doseIndex,
    required int dosesPerDay,
    bool muteRemainingDoses = false,
  }) async {
    await init();

    final start = doseIndex;
    final end = muteRemainingDoses ? (dosesPerDay - 1) : doseIndex;

    for (int d = start; d <= end; d++) {
      for (final kind in _Kind.values) {
        await cancel(
          _idFor(dayOffset: 0, pillSlot: pillSlot, doseIndex: d, kind: kind),
        );
      }
    }

    debugPrint(
      'NOTIF: muteToday pillSlot=$pillSlot doseIndex=$doseIndex remaining=$muteRemainingDoses',
    );
  }

  // ============================================================
  // Test helper
  // ============================================================

  static Future<void> scheduleTestIn(Duration fromNow) async {
    await init();
    await _requireExactAlarmsOnAndroid();

    final when = tz.TZDateTime.now(tz.local).add(fromNow);

    await _scheduleOneShot(
      id: 9999,
      when: when,
      title: 'PillChecker',
      body: 'Test scheduled for ${fromNow.inSeconds}s from now',
    );
  }

  // ============================================================
  // Debug / cancel
  // ============================================================

  static Future<void> debugDumpPending([String tag = '']) async {
    await init();
    final pending = await _plugin.pendingNotificationRequests();
    debugPrint('NOTIF DUMP $tag: pending=${pending.length}');
    for (final p in pending) {
      debugPrint('  -> id=${p.id} title=${p.title} body=${p.body}');
    }
  }

  static Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id: id);
    debugPrint('NOTIF: cancel(id=$id)');
  }

  static Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
    debugPrint('NOTIF: cancelAll() complete');
  }

  // ============================================================
  // Time helpers
  // ============================================================

  static TimeOfDay shiftTimeOfDay(TimeOfDay t, Duration delta) {
    final base = t.hour * 60 + t.minute;
    final add = delta.inMinutes;

    var mins = (base + add) % (24 * 60);
    if (mins < 0) mins += 24 * 60;

    return TimeOfDay(hour: mins ~/ 60, minute: mins % 60);
  }

  // ============================================================
  // Platform / details
  // ============================================================

  static Future<void> _requireExactAlarmsOnAndroid() async {
    if (!Platform.isAndroid) return;

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (android == null) return;

    final can = await android.canScheduleExactNotifications() ?? false;
    if (can) return;

    await android.requestExactAlarmsPermission();

    final canAfter = await android.canScheduleExactNotifications() ?? false;
    if (!canAfter) {
      throw StateError(
        'Exact alarms are not permitted. Enable: Settings > Apps > Special access > Alarms & reminders (allow PillChecker).',
      );
    }
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
      tz.setLocalLocation(tz.getLocation('UTC'));
    }
  }

  static Future<void> cancelInactivityWarning() async {
    await init();
    await cancel(_inactivityWarningId);
  }

  static ({TimeOfDay time, int dayDelta}) _shiftWithDayDelta(
    TimeOfDay t,
    Duration delta,
  ) {
    final base = t.hour * 60 + t.minute;
    final add = delta.inMinutes;

    final total = base + add;

    int dayDelta = 0;
    int mins = total;

    while (mins < 0) {
      mins += 24 * 60;
      dayDelta -= 1;
    }
    while (mins >= 24 * 60) {
      mins -= 24 * 60;
      dayDelta += 1;
    }

    return (
      time: TimeOfDay(hour: mins ~/ 60, minute: mins % 60),
      dayDelta: dayDelta,
    );
  }

  static int _toMins(TimeOfDay t) => t.hour * 60 + t.minute;
}
