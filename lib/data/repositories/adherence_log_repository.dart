import 'package:pillchecker/data/db/app_database.dart';
import 'package:pillchecker/data/models/adherence_log.dart';

class AdherenceLogRepository {
  AdherenceLogRepository({AppDatabase? database})
      : _databaseProvider = database ?? AppDatabase.instance;

  final AppDatabase _databaseProvider;
  static const _table = 'adherence_logs';

  Future<int> create(AdherenceLog log) async {
    final db = await _databaseProvider.database;
    final map = log.toMap()..remove('id');
    return db.insert(_table, map);
  }

  Future<AdherenceLog?> getById(int id) async {
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
    return AdherenceLog.fromMap(rows.first);
  }

  Future<List<AdherenceLog>> getAll({int? limit}) async {
    final db = await _databaseProvider.database;
    final rows = await db.query(
      _table,
      orderBy: 'action_at DESC',
      limit: limit,
    );
    return rows.map(AdherenceLog.fromMap).toList();
  }

  Future<List<AdherenceLog>> getByDoseEventId(int doseEventId) async {
    final db = await _databaseProvider.database;
    final rows = await db.query(
      _table,
      where: 'dose_event_id = ?',
      whereArgs: [doseEventId],
      orderBy: 'action_at DESC',
    );
    return rows.map(AdherenceLog.fromMap).toList();
  }

  Future<bool> update(AdherenceLog log) async {
    final id = log.id;
    if (id == null) {
      throw ArgumentError('Cannot update adherence log without id');
    }

    final db = await _databaseProvider.database;
    final map = log.toMap()..remove('id');
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
