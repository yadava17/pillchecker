import 'package:flutter/material.dart';

/// Local calendar day (date only) from [DateTime].
DateTime localDateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

/// Dart weekday: Mon=1..Sun=7. PillChecker uses Sun=0..Sat=6.
int weekdaySun0(DateTime localDay) => localDay.weekday % 7;

/// [daysMask] bit i = Sun+i (Sun=bit0).
bool dayIncludedInMask(int daysMask, DateTime localDay) {
  final bit = weekdaySun0(localDay);
  return (daysMask & (1 << bit)) != 0;
}

int timeOfDayToMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

/// Preserves the user-entered dose order and assigns a day rollover whenever
/// a later configured dose is earlier on the clock than the previous one.
///
/// Example:
/// [6:00 PM, 12:30 AM] -> [0, 1]
List<int> doseDayOffsets(List<TimeOfDay> orderedTimes) {
  if (orderedTimes.isEmpty) return const <int>[];

  final offsets = <int>[];
  var currentOffset = 0;
  int? previousMinutes;

  for (final t in orderedTimes) {
    final mins = timeOfDayToMinutes(t);
    if (previousMinutes != null && mins < previousMinutes) {
      currentOffset += 1;
    }
    offsets.add(currentOffset);
    previousMinutes = mins;
  }

  return offsets;
}

DateTime plannedAtLocalForOrderedDose(
  DateTime cycleDay,
  List<TimeOfDay> orderedTimes,
  int doseIndex,
) {
  final offsets = doseDayOffsets(orderedTimes);
  final tod = orderedTimes[doseIndex];
  final day = cycleDay.add(Duration(days: offsets[doseIndex]));

  return DateTime(
    day.year,
    day.month,
    day.day,
    tod.hour,
    tod.minute,
  );
}

String plannedAtUtcIsoForOrderedDose(
  DateTime cycleDay,
  List<TimeOfDay> orderedTimes,
  int doseIndex,
) {
  return plannedAtLocalForOrderedDose(
    cycleDay,
    orderedTimes,
    doseIndex,
  ).toUtc().toIso8601String();
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