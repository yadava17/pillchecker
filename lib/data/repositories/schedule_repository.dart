import 'package:pillchecker/data/db/app_database.dart';
import 'package:pillchecker/data/models/schedule_model.dart';

class ScheduleRepository {
  ScheduleRepository({AppDatabase? database})
    : _databaseProvider = database ?? AppDatabase.instance;

  final AppDatabase _databaseProvider;
  static const _table = 'schedules';

  Future<int> create(ScheduleModel schedule) async {
    final db = await _databaseProvider.database;
    final map = schedule.toMap()..remove('id');
    return db.insert(_table, map);
  }

  Future<ScheduleModel?> getById(int id) async {
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
    return ScheduleModel.fromMap(rows.first);
  }

  Future<List<ScheduleModel>> getAll() async {
    final db = await _databaseProvider.database;
    final rows = await db.query(_table, orderBy: 'created_at DESC');
    return rows.map(ScheduleModel.fromMap).toList();
  }

  Future<List<ScheduleModel>> getByMedicationId(int medId) async {
    final db = await _databaseProvider.database;
    final rows = await db.query(
      _table,
      where: 'med_id = ?',
      whereArgs: [medId],
      orderBy: 'created_at DESC',
    );
    return rows.map(ScheduleModel.fromMap).toList();
  }

  Future<List<ScheduleModel>> getByIds(List<int> ids) async {
    if (ids.isEmpty) {
      return [];
    }

    final db = await _databaseProvider.database;
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await db.query(
      _table,
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
    return rows.map(ScheduleModel.fromMap).toList();
  }

  Future<bool> update(ScheduleModel schedule) async {
    final id = schedule.id;
    if (id == null) {
      throw ArgumentError('Cannot update schedule without id');
    }

    final db = await _databaseProvider.database;
    final map = schedule.toMap()..remove('id');
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
