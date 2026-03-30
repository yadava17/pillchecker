import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:pillchecker/backend/database/app_database.dart';
import 'package:pillchecker/backend/utils/local_date_time.dart';

/// Schedules + idempotent dose_event generation for a rolling window.
class ScheduleService {
  ScheduleService({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  final AppDatabase _db;

  Future<Database> get _database => _db.database;

  static const int _defaultDaysMask = 127; // Sun–Sat

  /// One schedule row per medication (replace times + mask).
  Future<int> upsertSchedule({
    required int medicationId,
    required List<String> times24hSorted,
    int daysMask = _defaultDaysMask,
  }) async {
    final db = await _database;
    final existing = await db.query(
      'schedules',
      columns: ['id'],
      where: 'medication_id = ?',
      whereArgs: [medicationId],
      limit: 1,
    );

    final timesJson = jsonEncode(times24hSorted);

    if (existing.isEmpty) {
      return db.insert('schedules', {
        'medication_id': medicationId,
        'days_mask': daysMask,
        'times_json': timesJson,
      });
    }

    final sid = existing.first['id'] as int;
    await db.update(
      'schedules',
      {'days_mask': daysMask, 'times_json': timesJson},
      where: 'id = ?',
      whereArgs: [sid],
    );
    return sid;
  }

  Future<Map<String, Object?>?> getScheduleForMedication(int medicationId) async {
    final db = await _database;
    final rows = await db.query(
      'schedules',
      where: 'medication_id = ?',
      whereArgs: [medicationId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  /// Ensures dose rows exist for [daysAhead] calendar days starting from today (local).
  /// Skips duplicates via UNIQUE(medication_id, planned_at).
  Future<void> ensureDoseEventsForMedication(
    int medicationId, {
    int daysAhead = 8,
  }) async {
    final db = await _database;
    final sch = await getScheduleForMedication(medicationId);
    if (sch == null) return;

    final daysMask = sch['days_mask'] as int;
    final times = (jsonDecode(sch['times_json']! as String) as List)
        .map((e) => e.toString())
        .toList();

    final today = localDateOnly(DateTime.now());

    await db.transaction((txn) async {
      for (var d = 0; d < daysAhead; d++) {
        final day = today.add(Duration(days: d));
        if (!dayIncludedInMask(daysMask, day)) continue;

        for (var doseIndex = 0; doseIndex < times.length; doseIndex++) {
          final tod = parse24h(times[doseIndex]);
          final plannedIso = plannedAtUtcIsoForSlot(day, tod);

          await txn.rawInsert(
            '''
INSERT OR IGNORE INTO dose_events (
  medication_id, schedule_id, planned_at, dose_index, status, is_overridden
) VALUES (?, ?, ?, ?, 'planned', 0)
''',
            [medicationId, sch['id'], plannedIso, doseIndex],
          );
        }
      }
    });
  }

  Future<void> ensureDoseEventsForMedications(Iterable<int> ids) async {
    for (final id in ids) {
      await ensureDoseEventsForMedication(id);
    }
  }

  /// After schedule times change: remove future [planned] rows so we can regenerate.
  Future<void> deletePlannedFutureEvents(int medicationId) async {
    final db = await _database;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await db.delete(
      'dose_events',
      where: 'medication_id = ? AND status = ? AND planned_at >= ?',
      whereArgs: [medicationId, 'planned', nowIso],
    );
  }

  Future<void> regenerateAfterScheduleChange(int medicationId) async {
    await deletePlannedFutureEvents(medicationId);
    await ensureDoseEventsForMedication(medicationId);
  }
}
