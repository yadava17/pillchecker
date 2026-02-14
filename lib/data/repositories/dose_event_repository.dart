import 'package:pillchecker/data/db/app_database.dart';
import 'package:pillchecker/data/models/dose_event.dart';
import 'package:sqflite/sqflite.dart';

class DoseEventRepository {
  DoseEventRepository({AppDatabase? database})
    : _databaseProvider = database ?? AppDatabase.instance;

  final AppDatabase _databaseProvider;
  static const _table = 'dose_events';

  Future<int> create(DoseEvent event) async {
    final db = await _databaseProvider.database;
    final map = event.toMap()..remove('id');
    return db.insert(_table, map);
  }

  Future<int> createIfAbsent(DoseEvent event) async {
    final db = await _databaseProvider.database;
    final map = event.toMap()..remove('id');
    return db.insert(_table, map, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<DoseEvent?> getById(int id) async {
    final db = await _databaseProvider.database;
    final rows = await db.query(
      _table,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return DoseEvent.fromMap(rows.first);
  }

  Future<List<DoseEvent>> getAll() async {
    final db = await _databaseProvider.database;
    final rows = await db.query(_table, orderBy: 'scheduled_at ASC');
    return rows.map(DoseEvent.fromMap).toList();
  }

  Future<List<DoseEvent>> getByDateRange(DateTime from, DateTime to) async {
    final db = await _databaseProvider.database;
    final rows = await db.query(
      _table,
      where: 'scheduled_at >= ? AND scheduled_at <= ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'scheduled_at ASC',
    );
    return rows.map(DoseEvent.fromMap).toList();
  }

  Future<List<DoseEvent>> getByMedicationId(int medId) async {
    final db = await _databaseProvider.database;
    final rows = await db.query(
      _table,
      where: 'med_id = ?',
      whereArgs: [medId],
      orderBy: 'scheduled_at ASC',
    );
    return rows.map(DoseEvent.fromMap).toList();
  }

  Future<bool> update(DoseEvent event) async {
    final id = event.id;
    if (id == null) {
      throw ArgumentError('Cannot update dose event without id');
    }

    final db = await _databaseProvider.database;
    final map = event.toMap()..remove('id');
    final count = await db.update(
      _table,
      map,
      where: 'id = ?',
      whereArgs: [id],
    );
    return count > 0;
  }

  Future<bool> delete(int id) async {
    final db = await _databaseProvider.database;
    final count = await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    return count > 0;
  }
}
