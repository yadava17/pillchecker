import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/medication.dart';
import '../models/schedule.dart';
import '../models/dose_log.dart';
import '../models/pill_info.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('pill_checker.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE medications (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        dosage TEXT NOT NULL,
        strength TEXT NOT NULL,
        form TEXT NOT NULL,
        times_per_day INTEGER NOT NULL,
        days_of_week TEXT NOT NULL,
        with_food INTEGER NOT NULL DEFAULT 0,
        notes TEXT,
        created_at TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        medication_id INTEGER NOT NULL,
        time_of_day TEXT NOT NULL,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (medication_id) REFERENCES medications (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE dose_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        medication_id INTEGER NOT NULL,
        schedule_id INTEGER NOT NULL,
        scheduled_time TEXT NOT NULL,
        taken_time TEXT,
        status TEXT NOT NULL,
        notes TEXT,
        is_override INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (medication_id) REFERENCES medications (id) ON DELETE CASCADE,
        FOREIGN KEY (schedule_id) REFERENCES schedules (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE pill_info (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        medication_name TEXT NOT NULL,
        rxcui TEXT NOT NULL,
        generic_name TEXT,
        brand_name TEXT,
        description TEXT,
        safety_notes TEXT,
        cached_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_dose_logs_medication_id ON dose_logs(medication_id)
    ''');

    await db.execute('''
      CREATE INDEX idx_dose_logs_scheduled_time ON dose_logs(scheduled_time)
    ''');

    await db.execute('''
      CREATE INDEX idx_schedules_medication_id ON schedules(medication_id)
    ''');
  }

  Future<int> insertMedication(Medication medication) async {
    final db = await database;
    return await db.insert('medications', medication.toMap());
  }

  Future<Medication?> getMedication(int id) async {
    final db = await database;
    final maps = await db.query(
      'medications',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return Medication.fromMap(maps.first);
  }

  Future<List<Medication>> getAllMedications({bool activeOnly = true}) async {
    final db = await database;
    final maps = await db.query(
      'medications',
      where: activeOnly ? 'is_active = ?' : null,
      whereArgs: activeOnly ? [1] : null,
      orderBy: 'name ASC',
    );

    return maps.map((map) => Medication.fromMap(map)).toList();
  }

  Future<int> updateMedication(Medication medication) async {
    final db = await database;
    return await db.update(
      'medications',
      medication.toMap(),
      where: 'id = ?',
      whereArgs: [medication.id],
    );
  }

  Future<int> deleteMedication(int id) async {
    final db = await database;
    return await db.update(
      'medications',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> insertSchedule(Schedule schedule) async {
    final db = await database;
    return await db.insert('schedules', schedule.toMap());
  }

  Future<List<Schedule>> getSchedulesForMedication(int medicationId) async {
    final db = await database;
    final maps = await db.query(
      'schedules',
      where: 'medication_id = ?',
      whereArgs: [medicationId],
      orderBy: 'time_of_day ASC',
    );

    return maps.map((map) => Schedule.fromMap(map)).toList();
  }

  Future<int> updateSchedule(Schedule schedule) async {
    final db = await database;
    return await db.update(
      'schedules',
      schedule.toMap(),
      where: 'id = ?',
      whereArgs: [schedule.id],
    );
  }

  Future<int> deleteSchedule(int id) async {
    final db = await database;
    return await db.delete(
      'schedules',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> insertDoseLog(DoseLog doseLog) async {
    final db = await database;
    return await db.insert('dose_logs', doseLog.toMap());
  }

  Future<DoseLog?> getDoseLog(int id) async {
    final db = await database;
    final maps = await db.query(
      'dose_logs',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return DoseLog.fromMap(maps.first);
  }

  Future<List<DoseLog>> getDoseLogsForDate(DateTime date) async {
    final db = await database;
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final maps = await db.query(
      'dose_logs',
      where: 'scheduled_time >= ? AND scheduled_time < ?',
      whereArgs: [
        startOfDay.toIso8601String(),
        endOfDay.toIso8601String(),
      ],
      orderBy: 'scheduled_time ASC',
    );

    return maps.map((map) => DoseLog.fromMap(map)).toList();
  }

  Future<List<DoseLog>> getDoseLogsForMedication(
    int medicationId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await database;
    String where = 'medication_id = ?';
    List<dynamic> whereArgs = [medicationId];

    if (startDate != null) {
      where += ' AND scheduled_time >= ?';
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      where += ' AND scheduled_time < ?';
      whereArgs.add(endDate.toIso8601String());
    }

    final maps = await db.query(
      'dose_logs',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'scheduled_time DESC',
    );

    return maps.map((map) => DoseLog.fromMap(map)).toList();
  }

  Future<int> updateDoseLog(DoseLog doseLog) async {
    final db = await database;
    return await db.update(
      'dose_logs',
      doseLog.toMap(),
      where: 'id = ?',
      whereArgs: [doseLog.id],
    );
  }

  Future<int> insertPillInfo(PillInfo pillInfo) async {
    final db = await database;
    return await db.insert('pill_info', pillInfo.toMap());
  }

  Future<PillInfo?> getPillInfo(String medicationName) async {
    final db = await database;
    final maps = await db.query(
      'pill_info',
      where: 'medication_name = ?',
      whereArgs: [medicationName],
      orderBy: 'cached_at DESC',
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return PillInfo.fromMap(maps.first);
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
