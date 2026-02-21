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
  static String _mode = 'standard'; // off | basic | standard
  static Duration _earlyLead = const Duration(minutes: 30);
  static Duration _lateAfter = const Duration(minutes: 30);

  static String get mode => _mode;
  static Duration get earlyLead => _earlyLead;
  static Duration get lateAfter => _lateAfter;

  // Default horizon if caller doesn't pass one.
  static const int _defaultHorizonDays = 7;

  // ============================================================
  // HORIZON ID MAPPING (matches your debug dump)
  // baseId + 2,000,000 * dayOffset
  // dayOffset=0 is the "start day" used by the scheduler call.
  // ============================================================
  static const int _horizonStride = 2_000_000;

  static int _horizonId(int baseId, int dayOffset) =>
      baseId + (dayOffset * _horizonStride);

  // One global ID for the inactivity shutdown warning.
  // We always cancel+reschedule this same ID.
  static const int _inactivityWarningId = 1987654321;

  // How long after the late reminder this warning fires.
  static const Duration _inactivityAfterLateBuffer = Duration(minutes: 10);

  // How many days after the last check until warning.
  static const int _inactivityDays = 7;

  // Put near the top of NotificationService
  static const int _inactivityWarningBaseId = 2_147_000_001; // big + unique
  static const int _inactivityHorizonDays = 7;
  
  
  static Future<void> cancelInactivityShutdownWarning({
    int horizonDays = 7,
  }) async {
    await init();
    await cancelHorizon(baseId: _inactivityWarningId, horizonDays: horizonDays);
    debugPrint(
      'NOTIF: cancelInactivityShutdownWarning(base=$_inactivityWarningId days=$horizonDays)',
    );
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

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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
  // IMPORTANT: ONE-SHOT ONLY
  // ============================================================

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

  // ============================================================
  // Horizon primitives (THIS is what you should use everywhere)
  // ============================================================

  static DateTime _startOfTodayLocal() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

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

  /// Schedule a rolling horizon of one-shots.
  /// - startTomorrow=false => dayOffset=0 is today
  /// - startTomorrow=true  => dayOffset=0 is tomorrow
  static Future<void> _scheduleHorizon({
    required int baseId,
    required int horizonDays,
    required bool startTomorrow,
    required String title,
    required String body,
    required TimeOfDay time,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();

    final nowTz = tz.TZDateTime.now(tz.local);
    final startLocalDay = _startOfTodayLocal().add(
      Duration(days: startTomorrow ? 1 : 0),
    );

    for (int d = 0; d < horizonDays; d++) {
      final day = startLocalDay.add(Duration(days: d));
      final when = _atLocalDayTime(day, time);

      // Don’t schedule past times (ex: today's time already passed)
      if (when.isBefore(nowTz)) continue;

      final id = _horizonId(baseId, d);

      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: when,
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        title: title,
        body: body,
      );
    }
  }

  static Future<void> cancelHorizon({
    required int baseId,
    required int horizonDays,
  }) async {
    await init();
    for (int d = 0; d < horizonDays; d++) {
      await cancel(_horizonId(baseId, d));
    }
  }

  /// Reschedules the "Notifications will be turned off due to inactivity" warning.
  /// - Cancels the existing warning (fixed ID) and schedules a new one-shot.
  /// - Fires _inactivityDays days from today, at (lateTime + buffer).
  /// - Uses the *doseTime* that was just checked as the reference.
  static Future<void> rescheduleInactivityShutdownWarning({
    required TimeOfDay doseTime,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();
    await loadUserNotificationSettings();

    // If notifications are off, ensure this warning is dead too.
    if (_mode == 'off') {
      await cancel(_inactivityWarningId);
      return;
    }

    // lateTime = doseTime + user-configured lateAfter
    final lateTime = shiftTimeOfDay(doseTime, _lateAfter);

    // warningTime = lateTime + small buffer (so it definitely comes after late)
    final warningTime = shiftTimeOfDay(lateTime, _inactivityAfterLateBuffer);

    // target day = today + 7 days (local date)
    final today = _dayOnly(DateTime.now());
    final targetDay = today.add(const Duration(days: _inactivityDays));

    // Build the tz time on/after that day (it won't roll since targetDay is future)
    final when = _instanceOnOrAfter(targetDay, warningTime);

    // Cancel any existing watchdog and schedule a new one
    await cancel(_inactivityWarningId);

    await _scheduleOneShot(
      id: _inactivityWarningId,
      when: when,
      title: 'PillChecker',
      body:
          'Notifications will be turned off tomorrow due to inactivity. Check your pills off to start recieving notifications again!',
    );

    debugPrint(
      'INACTIVITY WARNING: rescheduled id=$_inactivityWarningId '
      'for ${when.toIso8601String()} (doseTime=${doseTime.hour}:${doseTime.minute})',
    );
  }

  // ============================================================
  // Public scheduling APIs used by your Sync code
  // ============================================================

  static Future<void> scheduleDailyDoseReminder({
    required int id, // baseId
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    int? totalDoses,
    tz.TZDateTime?
    firstFire, // ignored in horizon model (kept for compatibility)
    int horizonDays = _defaultHorizonDays,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();
    await loadUserNotificationSettings();

    if (_mode == 'off') return;

    final isSingleDose = (totalDoses != null && totalDoses <= 1);
    final body = isSingleDose
        ? "It's time to take $pillName!"
        : "It's time to take dose $doseNumber1Based of $pillName!";

    // Rebuild horizon starting TODAY
    await cancelHorizon(baseId: id, horizonDays: horizonDays);
    await _scheduleHorizon(
      baseId: id,
      horizonDays: horizonDays,
      startTomorrow: false,
      title: 'PillChecker',
      body: body,
      time: time,
    );
  }

  static Future<void> scheduleDailyDoseEarlyReminder({
    required int id, // baseId
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    required int totalDoses,
    tz.TZDateTime?
    firstFire, // ignored in horizon model (kept for compatibility)
    int horizonDays = _defaultHorizonDays,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();
    await loadUserNotificationSettings();

    if (_mode == 'off') return;
    if (_mode == 'basic') return;

    final earlyTime = shiftTimeOfDay(time, -_earlyLead);

    final body = (totalDoses <= 1)
        ? "Almost time to take $pillName!"
        : "Almost time to take dose $doseNumber1Based of $pillName!";

    await cancelHorizon(baseId: id, horizonDays: horizonDays);
    await _scheduleHorizon(
      baseId: id,
      horizonDays: horizonDays,
      startTomorrow: false,
      title: 'PillChecker',
      body: body,
      time: earlyTime,
    );
  }

  static Future<void> scheduleDailyDoseLateReminder({
    required int id, // baseId
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    required int totalDoses,
    tz.TZDateTime?
    firstFire, // ignored in horizon model (kept for compatibility)
    int horizonDays = _defaultHorizonDays,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();
    await loadUserNotificationSettings();

    if (_mode == 'off') return;
    if (_mode == 'basic') return;

    final lateTime = shiftTimeOfDay(time, _lateAfter);

    final body = (totalDoses <= 1)
        ? "You haven't checked $pillName yet! Check it off before it's too late!"
        : "You haven't checked dose $doseNumber1Based of $pillName yet! Check it off before it's too late!";

    await cancelHorizon(baseId: id, horizonDays: horizonDays);
    await _scheduleHorizon(
      baseId: id,
      horizonDays: horizonDays,
      startTomorrow: false,
      title: 'PillChecker',
      body: body,
      time: lateTime,
    );
  }

  // ============================================================
  // MUTE (HORIZON MODEL)
  // ✅ This is the “make it work after missed day” fix:
  // - cancel ALL offsets
  // - rebuild starting tomorrow (so main/late can’t fire after check)
  // ============================================================

  static Future<void> muteMainHorizonUntilTomorrow({
    required int baseId,
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    required int totalDoses,
    int horizonDays = _defaultHorizonDays,
  }) async {
    await init();
    await loadUserNotificationSettings();

    // Always kill whatever is pending for this baseId (today might be offset 1/2/etc after a missed day)
    await cancelHorizon(baseId: baseId, horizonDays: horizonDays);

    if (_mode == 'off') return;

    final body = (totalDoses <= 1)
        ? "It's time to take $pillName!"
        : "It's time to take dose $doseNumber1Based of $pillName!";

    await _scheduleHorizon(
      baseId: baseId,
      horizonDays: horizonDays,
      startTomorrow: true, // <-- KEY
      title: 'PillChecker',
      body: body,
      time: time,
    );
  }

  static Future<void> muteEarlyHorizonUntilTomorrow({
    required int baseId,
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    required int totalDoses,
    int horizonDays = _defaultHorizonDays,
  }) async {
    await init();
    await loadUserNotificationSettings();

    await cancelHorizon(baseId: baseId, horizonDays: horizonDays);

    if (_mode == 'off' || _mode == 'basic') return;

    final earlyTime = shiftTimeOfDay(time, -_earlyLead);

    final body = (totalDoses <= 1)
        ? "Almost time to take $pillName!"
        : "Almost time to take dose $doseNumber1Based of $pillName!";

    await _scheduleHorizon(
      baseId: baseId,
      horizonDays: horizonDays,
      startTomorrow: true, // <-- KEY
      title: 'PillChecker',
      body: body,
      time: earlyTime,
    );
  }

  static Future<void> muteLateHorizonUntilTomorrow({
    required int baseId,
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    required int totalDoses,
    int horizonDays = _defaultHorizonDays,
  }) async {
    await init();
    await loadUserNotificationSettings();

    await cancelHorizon(baseId: baseId, horizonDays: horizonDays);

    if (_mode == 'off' || _mode == 'basic') return;

    final lateTime = shiftTimeOfDay(time, _lateAfter);

    final body = (totalDoses <= 1)
        ? "You haven't checked $pillName yet! Check it off before it's too late!"
        : "You haven't checked dose $doseNumber1Based of $pillName yet! Check it off before it's too late!";

    await _scheduleHorizon(
      baseId: baseId,
      horizonDays: horizonDays,
      startTomorrow: true, // <-- KEY
      title: 'PillChecker',
      body: body,
      time: lateTime,
    );
  }

  // ============================================================
  // “From day” one-shots (kept exactly, still one-shot not horizon)
  // ============================================================

  static tz.TZDateTime _instanceOnOrAfter(DateTime day, TimeOfDay time) {
    final base = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    final asTz = tz.TZDateTime.from(base, tz.local);

    final now = tz.TZDateTime.now(tz.local);
    if (asTz.isBefore(now)) {
      return asTz.add(const Duration(days: 1));
    }
    return asTz;
  }

  static Future<void> scheduleDailyDoseReminderFrom({
    required int id,
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    int? totalDoses,
    required DateTime startDay, // yyyy-mm-dd local date
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();
    await loadUserNotificationSettings();

    if (_mode == 'off') return;

    final scheduled = _instanceOnOrAfter(startDay, time);

    final isSingleDose = (totalDoses != null && totalDoses <= 1);
    final body = isSingleDose
        ? "It's time to take $pillName!"
        : "It's time to take dose $doseNumber1Based of $pillName!";

    await _scheduleOneShot(
      id: id,
      when: scheduled,
      title: 'PillChecker',
      body: body,
    );
  }

  static Future<void> scheduleDailyDoseEarlyReminderFrom({
    required int id,
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    required int totalDoses,
    required DateTime startDay,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();
    await loadUserNotificationSettings();

    if (_mode == 'off') return;
    if (_mode == 'basic') return;

    final earlyTime = shiftTimeOfDay(time, -_earlyLead);
    final scheduled = _instanceOnOrAfter(startDay, earlyTime);

    final body = (totalDoses <= 1)
        ? "Almost time to take $pillName!"
        : "Almost time to take dose $doseNumber1Based of $pillName!";

    await _scheduleOneShot(
      id: id,
      when: scheduled,
      title: 'PillChecker',
      body: body,
    );
  }

  static Future<void> scheduleDailyDoseLateReminderFrom({
    required int id,
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    required int totalDoses,
    required DateTime startDay,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();
    await loadUserNotificationSettings();

    if (_mode == 'off') return;
    if (_mode == 'basic') return;

    final lateTime = shiftTimeOfDay(time, _lateAfter);
    final scheduled = _instanceOnOrAfter(startDay, lateTime);

    final body = (totalDoses <= 1)
        ? "You haven't checked $pillName yet! Check it off before it's too late!"
        : "You haven't checked dose $doseNumber1Based of $pillName yet! Check it off before it's too late!";

    await _scheduleOneShot(
      id: id,
      when: scheduled,
      title: 'PillChecker',
      body: body,
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
  // Single pill reminder (main) - kept (one-shot)
  // ============================================================

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

  static Future<void> scheduleDailyPillReminder({
    required int id,
    required String pillName,
    required TimeOfDay time,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();
    await loadUserNotificationSettings();

    if (_mode == 'off') return;

    final scheduled = _nextInstanceOfTime(time);

    debugPrint(
      'NOTIF: scheduling ONE-SHOT id=$id at ${scheduled.toIso8601String()}',
    );

    await _scheduleOneShot(
      id: id,
      when: scheduled,
      title: 'PillChecker',
      body: "It's time to take $pillName!",
    );
  }

  // ============================================================
  // MUTE (ONE-SHOT MODEL) - kept for legacy callers
  // ============================================================

  static tz.TZDateTime _tomorrowInstanceOfTime(TimeOfDay time) {
    final now = tz.TZDateTime.now(tz.local);
    final todayAt = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    return todayAt.add(const Duration(days: 1));
  }

  static Future<void> muteDailyMainUntilTomorrow({
    required int id,
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    required int totalDoses,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();
    await loadUserNotificationSettings();

    if (_mode == 'off') return;

    await cancel(id);

    final when = _tomorrowInstanceOfTime(time);
    final body = (totalDoses <= 1)
        ? "It's time to take $pillName!"
        : "It's time to take dose $doseNumber1Based of $pillName!";

    debugPrint(
      'MUTE->MAIN one-shot: id=$id -> tomorrow=${when.toIso8601String()}',
    );

    await _scheduleOneShot(
      id: id,
      when: when,
      title: 'PillChecker',
      body: body,
    );
  }

  static Future<void> muteDailyEarlyUntilTomorrow({
    required int id,
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    required int totalDoses,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();
    await loadUserNotificationSettings();

    if (_mode == 'off') return;
    if (_mode == 'basic') return;

    await cancel(id);

    final earlyTime = shiftTimeOfDay(time, -_earlyLead);
    final when = _tomorrowInstanceOfTime(earlyTime);

    final body = (totalDoses <= 1)
        ? "Almost time to take $pillName!"
        : "Almost time to take dose $doseNumber1Based of $pillName!";

    debugPrint(
      'MUTE->EARLY one-shot: id=$id -> tomorrow=${when.toIso8601String()}',
    );

    await _scheduleOneShot(
      id: id,
      when: when,
      title: 'PillChecker',
      body: body,
    );
  }

  static Future<void> muteDailyLateUntilTomorrow({
    required int id,
    required String pillName,
    required int doseNumber1Based,
    required TimeOfDay time,
    required int totalDoses,
  }) async {
    await init();
    await _requireExactAlarmsOnAndroid();
    await loadUserNotificationSettings();

    if (_mode == 'off') return;
    if (_mode == 'basic') return;

    await cancel(id);

    final lateTime = shiftTimeOfDay(time, _lateAfter);
    final when = _tomorrowInstanceOfTime(lateTime);

    final body = (totalDoses <= 1)
        ? "You haven't checked $pillName yet! Check it off before it's too late!"
        : "You haven't checked dose $doseNumber1Based of $pillName yet! Check it off before it's too late!";

    debugPrint(
      'MUTE->LATE one-shot: id=$id -> tomorrow=${when.toIso8601String()}',
    );

    await _scheduleOneShot(
      id: id,
      when: when,
      title: 'PillChecker',
      body: body,
    );
  }

  // ============================================================
  // Debug / cancel / misc helpers
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

  // ============================================================
  // Legacy one-shot testers (kept)
  // ============================================================

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
    final base = _nextDoseInstance(time);
    final when = base.subtract(Duration(minutes: minutesBefore));

    final body = (totalDoses <= 1)
        ? "Almost time to take $pillName!"
        : "Almost time to take dose $doseNumber1Based of $pillName!";

    debugPrint(
      'ONE-SHOT EARLY: id=$id pill=$pillName dose=$doseNumber1Based '
      'base=${base.toIso8601String()} minutesBefore=$minutesBefore '
      'scheduled=${when.toIso8601String()} now=${now.toIso8601String()}',
    );

    await _scheduleOneShot(
      id: id,
      when: when,
      title: 'PillChecker',
      body: body,
    );
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
    final base = _nextDoseInstance(time);
    final when = base.add(Duration(minutes: minutesAfter));

    final body = (totalDoses <= 1)
        ? "You haven't checked $pillName yet!"
        : "You haven't checked dose $doseNumber1Based of $pillName yet!";

    debugPrint(
      'ONE-SHOT LATE: id=$id pill=$pillName dose=$doseNumber1Based '
      'base=${base.toIso8601String()} minutesAfter=$minutesAfter '
      'scheduled=${when.toIso8601String()} now=${now.toIso8601String()}',
    );

    await _scheduleOneShot(
      id: id,
      when: when,
      title: 'PillChecker',
      body: body,
    );
  }
}
