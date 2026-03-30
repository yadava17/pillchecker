import 'package:flutter/material.dart';

/// Local calendar day (date only) from [DateTime].
DateTime localDateOnly(DateTime dt) =>
    DateTime(dt.year, dt.month, dt.day);

/// Dart weekday: Mon=1..Sun=7. PillChecker uses Sun=0..Sat=6.
int weekdaySun0(DateTime localDay) => localDay.weekday % 7;

/// [daysMask] bit i = Sun+i (Sun=bit0).
bool dayIncludedInMask(int daysMask, DateTime localDay) {
  final bit = weekdaySun0(localDay);
  return (daysMask & (1 << bit)) != 0;
}

/// Stable UTC string for a scheduled local instant on [localDay] at [time].
String plannedAtUtcIsoForSlot(DateTime localDay, TimeOfDay time) {
  final local = DateTime(
    localDay.year,
    localDay.month,
    localDay.day,
    time.hour,
    time.minute,
  );
  return local.toUtc().toIso8601String();
}

/// Parse "HH:mm" 24h to [TimeOfDay].
TimeOfDay parse24h(String hhmm) {
  final p = hhmm.split(':');
  return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
}
