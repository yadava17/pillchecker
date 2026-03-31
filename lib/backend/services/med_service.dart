import 'package:sqflite/sqflite.dart';

import 'package:pillchecker/backend/database/app_database.dart';
import 'package:pillchecker/backend/models/medication_record.dart';

/// Medication CRUD (SQLite).
class MedService {
  MedService({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  final AppDatabase _db;

  Future<Database> get _database => _db.database;

  Future<List<MedicationRecord>> getAll() async {
    final db = await _database;
    final rows = await db.query(
      'medications',
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(MedicationRecord.fromMap).toList();
  }

  Future<MedicationRecord?> getById(int id) async {
    final db = await _database;
    final rows = await db.query(
      'medications',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MedicationRecord.fromMap(rows.first);
  }

  Future<MedicationRecord> create({
    required String name,
    required bool supplyEnabled,
    required int supplyLeft,
    required int supplyInitial,
    required bool nameLocked,
    required int sortOrder,
  }) async {
    final db = await _database;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await db.insert('medications', {
      'name': name,
      'supply_enabled': supplyEnabled ? 1 : 0,
      'supply_left': supplyLeft,
      'supply_initial': supplyInitial,
      'name_locked': nameLocked ? 1 : 0,
      'sort_order': sortOrder,
      'created_at': now,
    });
    return (await getById(id))!;
  }

  Future<void> update({
    required int id,
    String? name,
    bool? supplyEnabled,
    int? supplyLeft,
    int? supplyInitial,
    bool? nameLocked,
    int? sortOrder,
  }) async {
    final db = await _database;
    final map = <String, Object?>{};
    if (name != null) map['name'] = name;
    if (supplyEnabled != null) map['supply_enabled'] = supplyEnabled ? 1 : 0;
    if (supplyLeft != null) map['supply_left'] = supplyLeft;
    if (supplyInitial != null) map['supply_initial'] = supplyInitial;
    if (nameLocked != null) map['name_locked'] = nameLocked ? 1 : 0;
    if (sortOrder != null) map['sort_order'] = sortOrder;
    if (map.isEmpty) return;
    await db.update('medications', map, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> delete(int id) async {
    final db = await _database;
    await db.delete('medications', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> count() async {
    final db = await _database;
    final r = await db.rawQuery('SELECT COUNT(*) as c FROM medications');
    return (r.first['c'] as int?) ?? 0;
  }
}
