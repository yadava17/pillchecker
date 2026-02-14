import 'package:pillchecker/data/db/app_database.dart';
import 'package:pillchecker/data/models/medication.dart';

class MedicationRepository {
  MedicationRepository({AppDatabase? database})
    : _databaseProvider = database ?? AppDatabase.instance;

  final AppDatabase _databaseProvider;
  static const _table = 'meds';

  Future<int> create(Medication medication) async {
    final db = await _databaseProvider.database;
    final map = medication.toMap()..remove('id');
    return db.insert(_table, map);
  }

  Future<Medication?> getById(int id) async {
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
    return Medication.fromMap(rows.first);
  }

  Future<List<Medication>> getAll({bool activeOnly = false}) async {
    final db = await _databaseProvider.database;
    final rows = await db.query(
      _table,
      where: activeOnly ? 'is_active = 1' : null,
      orderBy: 'created_at DESC',
    );
    return rows.map(Medication.fromMap).toList();
  }

  Future<List<Medication>> getByIds(List<int> ids) async {
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
    return rows.map(Medication.fromMap).toList();
  }

  Future<bool> update(Medication medication) async {
    final id = medication.id;
    if (id == null) {
      throw ArgumentError('Cannot update medication without id');
    }

    final db = await _databaseProvider.database;
    final map = medication.toMap()..remove('id');
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
