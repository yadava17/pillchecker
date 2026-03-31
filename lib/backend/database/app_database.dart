import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite singleton for PillChecker (offline).
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<bool> _tableHasColumn(
    Database db, {
    required String table,
    required String column,
  }) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    for (final r in rows) {
      if (r['name'] == column) return true;
    }
    return false;
  }

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<void> _ensureSchema(Database db) async {
    // Use IF NOT EXISTS so older DB files can be "fixed" without requiring
    // a full migration (staging/offline-first).
    // If the DB exists but has a mismatched schema, recreate everything.
    final doseEventsHasMedicationId = await _tableHasColumn(
      db,
      table: 'dose_events',
      column: 'medication_id',
    );
    if (!doseEventsHasMedicationId) {
      await db.execute('DROP TABLE IF EXISTS adherence_logs;');
      await db.execute('DROP TABLE IF EXISTS dose_events;');
      await db.execute('DROP TABLE IF EXISTS schedules;');
      await db.execute('DROP TABLE IF EXISTS medications;');
    }

    await db.execute('''
CREATE TABLE IF NOT EXISTS medications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  supply_enabled INTEGER NOT NULL DEFAULT 0,
  supply_left INTEGER NOT NULL DEFAULT 0,
  supply_initial INTEGER NOT NULL DEFAULT 0,
  name_locked INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS schedules (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  medication_id INTEGER NOT NULL,
  days_mask INTEGER NOT NULL DEFAULT 127,
  times_json TEXT NOT NULL,
  FOREIGN KEY (medication_id) REFERENCES medications (id) ON DELETE CASCADE
);
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS dose_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  medication_id INTEGER NOT NULL,
  schedule_id INTEGER NOT NULL,
  planned_at TEXT NOT NULL,
  dose_index INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'planned',
  is_overridden INTEGER NOT NULL DEFAULT 0,
  taken_at TEXT,
  FOREIGN KEY (medication_id) REFERENCES medications (id) ON DELETE CASCADE,
  FOREIGN KEY (schedule_id) REFERENCES schedules (id) ON DELETE CASCADE,
  UNIQUE (medication_id, planned_at)
);
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_dose_events_med_planned ON dose_events (medication_id, planned_at);',
    );

    await db.execute('''
CREATE TABLE IF NOT EXISTS adherence_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  dose_event_id INTEGER NOT NULL,
  action TEXT NOT NULL,
  logged_at TEXT NOT NULL,
  FOREIGN KEY (dose_event_id) REFERENCES dose_events (id) ON DELETE CASCADE
);
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_adherence_logs_dose ON adherence_logs (dose_event_id);',
    );

    await db.execute('''
CREATE TABLE IF NOT EXISTS rxnorm_search_cache (
  query_key TEXT PRIMARY KEY NOT NULL,
  results_json TEXT NOT NULL,
  cached_at TEXT NOT NULL
);
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS rxnorm_details_cache (
  rxcui TEXT PRIMARY KEY NOT NULL,
  details_json TEXT NOT NULL,
  cached_at TEXT NOT NULL
);
''');
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'pillchecker.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async => _ensureSchema(db),
      onOpen: (db) async => _ensureSchema(db),
    );
  }

  // ----------------------------
  // Debug / diagnostic helpers
  // ----------------------------
  // NOTE: these are intended for development / staging only. Do NOT
  // expose them in production UI without gating behind a dev flag.

  /// Returns the absolute path to the sqlite DB file the app will open.
  Future<String> debugDbPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'pillchecker.db');
  }

  /// Run a set of lightweight diagnostics and return a map with results.
  /// Useful to print from a dev-only screen or from `main()` while debugging.
  Future<Map<String, dynamic>> runDiagnostics() async {
    final db = await database;

    // integrity_check: returns ok when healthy
    String integrity = 'unknown';
    try {
      final rows = await db.rawQuery('PRAGMA integrity_check;');
      if (rows.isNotEmpty)
        integrity = rows.first.values.first?.toString() ?? 'no result';
    } catch (e) {
      integrity = 'error: $e';
    }

    // foreign key check (empty = good)
    List<Map<String, Object?>> fkProblems = <Map<String, Object?>>[];
    try {
      final fk = await db.rawQuery('PRAGMA foreign_key_check;');
      fkProblems = fk;
    } catch (_) {
      fkProblems = [];
    }

    // counts for important tables (safe if table missing -> return -1)
    Future<int> _count(String table) async {
      try {
        final r = await db.rawQuery('SELECT count(*) AS c FROM $table;');
        final v = r.first['c'];
        if (v is int) return v;
        if (v is int?) return v ?? -1;
        if (v is num) return v.toInt();
        return int.parse(v.toString());
      } catch (_) {
        return -1;
      }
    }

    final meds = await _count('medications');
    final schedules = await _count('schedules');
    final doses = await _count('dose_events');
    final logs = await _count('adherence_logs');

    return {
      'path': await debugDbPath(),
      'integrity': integrity,
      'foreign_key_problems': fkProblems,
      'counts': {
        'medications': meds,
        'schedules': schedules,
        'dose_events': doses,
        'adherence_logs': logs,
      },
    };
  }

  /// Test hook.
  Future<void> closeForTest() async {
    await _db?.close();
    _db = null;
  }
}
