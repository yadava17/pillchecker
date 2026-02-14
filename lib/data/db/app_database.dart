import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const _databaseName = 'pillchecker.db';
  static const _databaseVersion = 1;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);

    _database = await openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
    );
    return _database!;
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE meds (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        dosage TEXT NOT NULL,
        notes TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        med_id INTEGER NOT NULL,
        time_of_day TEXT NOT NULL,
        frequency_per_day INTEGER NOT NULL DEFAULT 1,
        start_date TEXT NOT NULL,
        end_date TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (med_id) REFERENCES meds(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE dose_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        med_id INTEGER NOT NULL,
        schedule_id INTEGER NOT NULL,
        scheduled_at TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        confirmed_at TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (med_id) REFERENCES meds(id) ON DELETE CASCADE,
        FOREIGN KEY (schedule_id) REFERENCES schedules(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE adherence_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dose_event_id INTEGER NOT NULL,
        med_id INTEGER NOT NULL,
        action TEXT NOT NULL,
        action_at TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (dose_event_id) REFERENCES dose_events(id) ON DELETE CASCADE,
        FOREIGN KEY (med_id) REFERENCES meds(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_schedules_med_id ON schedules(med_id)');
    await db.execute(
      'CREATE INDEX idx_dose_events_med_scheduled ON dose_events(med_id, scheduled_at)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX idx_dose_events_schedule_time ON dose_events(schedule_id, scheduled_at)',
    );
    await db.execute(
      'CREATE INDEX idx_adherence_logs_med_action_at ON adherence_logs(med_id, action_at)',
    );
    await db.execute(
      'CREATE INDEX idx_adherence_logs_dose_event_id ON adherence_logs(dose_event_id)',
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
    }
  }
}
