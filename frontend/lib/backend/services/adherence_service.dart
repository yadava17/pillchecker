import 'package:sqflite/sqflite.dart';

import 'package:pillchecker/backend/database/app_database.dart';
import 'package:pillchecker/backend/models/dose_event_record.dart';
import 'package:pillchecker/backend/models/history_entry.dart';

/// Dose actions + history (SQLite).
class AdherenceService {
  AdherenceService({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  final AppDatabase _db;

  Future<Database> get _database => _db.database;

  Future<void> _insertLog(
    DatabaseExecutor db,
    int doseEventId,
    String action,
  ) async {
    await db.insert('adherence_logs', {
      'dose_event_id': doseEventId,
      'action': action,
      'logged_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Events for [medicationId] whose planned instant falls on [localDay] (local calendar).
  Future<List<DoseEventRecord>> getDoseEventsForMedicationOnLocalDay({
    required int medicationId,
    required DateTime localDay,
  }) async {
    final db = await _database;
    final start = DateTime(localDay.year, localDay.month, localDay.day);
    final end = start.add(const Duration(days: 1));
    final startUtc = start.toUtc().toIso8601String();
    final endUtc = end.toUtc().toIso8601String();

    final rows = await db.query(
      'dose_events',
      where: 'medication_id = ? AND planned_at >= ? AND planned_at < ?',
      whereArgs: [medicationId, startUtc, endUtc],
      orderBy: 'dose_index ASC',
    );
    return rows.map(DoseEventRecord.fromMap).toList();
  }

  /// Locate the row for this scheduled local instant (must match generation math).
  Future<DoseEventRecord?> findDoseEventForPlannedUtc({
    required int medicationId,
    required String plannedAtUtcIso,
  }) async {
    final db = await _database;
    final rows = await db.query(
      'dose_events',
      where: 'medication_id = ? AND planned_at = ?',
      whereArgs: [medicationId, plannedAtUtcIso],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return DoseEventRecord.fromMap(rows.first);
  }

  Future<void> confirmTaken(int doseEventId) async {
    final db = await _database;
    await db.transaction((txn) async {
      final cur = await txn.query(
        'dose_events',
        where: 'id = ?',
        whereArgs: [doseEventId],
        limit: 1,
      );
      if (cur.isEmpty) return;
      if ((cur.first['status'] as String) != 'planned') return;

      await txn.update(
        'dose_events',
        {
          'status': 'taken',
          'taken_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [doseEventId],
      );
      await _insertLog(txn, doseEventId, 'taken');
    });
  }

  Future<void> markMissed(int doseEventId) async {
    final db = await _database;
    await db.transaction((txn) async {
      final cur = await txn.query(
        'dose_events',
        where: 'id = ?',
        whereArgs: [doseEventId],
        limit: 1,
      );
      if (cur.isEmpty) return;
      if ((cur.first['status'] as String) != 'planned') return;

      await txn.update(
        'dose_events',
        {'status': 'missed'},
        where: 'id = ?',
        whereArgs: [doseEventId],
      );
      await _insertLog(txn, doseEventId, 'missed');
    });
  }

  /// Missed → taken + overridden + log override.
  Future<void> overrideDose(int doseEventId) async {
    final db = await _database;
    await db.transaction((txn) async {
      final cur = await txn.query(
        'dose_events',
        where: 'id = ?',
        whereArgs: [doseEventId],
        limit: 1,
      );
      if (cur.isEmpty) return;
      if ((cur.first['status'] as String) != 'missed') return;

      await txn.update(
        'dose_events',
        {
          'status': 'taken',
          'is_overridden': 1,
          'taken_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [doseEventId],
      );
      await _insertLog(txn, doseEventId, 'override');
    });
  }

  /// Auto-mark planned doses as missed after a grace period past planned local time.
  Future<void> autoMarkMissedPastPlanned({Duration grace = const Duration(hours: 2)}) async {
    final db = await _database;
    final rows = await db.query(
      'dose_events',
      where: "status = 'planned'",
    );
    final now = DateTime.now();
    for (final r in rows) {
      final planned = DateTime.parse(r['planned_at']! as String).toLocal();
      if (now.isAfter(planned.add(grace))) {
        await markMissed(r['id']! as int);
      }
    }
  }

  Future<List<HistoryEntry>> fetchHistory({int limit = 200}) async {
    final db = await _database;
    final rows = await db.rawQuery(
      '''
SELECT
  l.id AS log_id,
  l.action AS action,
  l.logged_at AS logged_at,
  e.id AS dose_event_id,
  e.planned_at AS planned_at,
  e.is_overridden AS is_overridden,
  m.name AS medication_name
FROM adherence_logs l
INNER JOIN dose_events e ON e.id = l.dose_event_id
INNER JOIN medications m ON m.id = e.medication_id
ORDER BY l.logged_at DESC
LIMIT ?
''',
      [limit],
    );

    return rows.map((raw) {
      final plannedUtc = DateTime.parse(raw['planned_at']! as String);
      final loggedUtc = DateTime.parse(raw['logged_at']! as String);
      final action = raw['action']! as String;
      final isOverridden = (raw['is_overridden'] as int) != 0;
      return HistoryEntry(
        doseEventId: raw['dose_event_id']! as int,
        medicationName: raw['medication_name']! as String,
        plannedAtLocal: plannedUtc.toLocal(),
        actionLabel: action,
        isOverridden: isOverridden,
        loggedAtLocal: loggedUtc.toLocal(),
      );
    }).toList();
  }

  /// First missed event on [localDay] for medication (for override UX).
  Future<DoseEventRecord?> firstMissedOnLocalDay({
    required int medicationId,
    required DateTime localDay,
  }) async {
    final events = await getDoseEventsForMedicationOnLocalDay(
      medicationId: medicationId,
      localDay: localDay,
    );
    for (final e in events) {
      if (e.status == 'missed') return e;
    }
    return null;
  }
}
