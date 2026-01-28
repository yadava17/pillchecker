import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static const String _channelId = 'pill_reminders';
  static const String _channelName = 'Pill Reminders';
  static const String _channelDesc = 'Daily pill reminder notifications';

  static Future<void> init() async {
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

    _initialized = true;
  }

  static Future<void> requestPermissions() async {
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

  static NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
  }

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

  static Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id: id);
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
