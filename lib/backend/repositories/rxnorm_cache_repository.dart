import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../rxnorm/medication_details.dart';
import '../rxnorm/medication_summary.dart';

/// Contract for RxNorm caching (SQLite, in-memory tests, or future stores).
abstract class RxNormMedicationCache {
  Future<List<MedicationSummary>?> getSearchResults(String query);

  Future<void> saveSearchResults(String query, List<MedicationSummary> items);

  Future<MedicationDetails?> getDetails(String rxcui);

  Future<void> saveDetails(MedicationDetails details);
}

/// Persists RxNorm search rows and detail payloads for offline reuse.
/// Strategy: always write on successful network; read on failure or offline.
class RxNormCacheRepository implements RxNormMedicationCache {
  RxNormCacheRepository({AppDatabase? db}) : _db = db ?? AppDatabase.instance;

  final AppDatabase _db;

  Future<Database> get _database => _db.database;

  String _searchKey(String query) => query.trim().toLowerCase();

  @override
  Future<List<MedicationSummary>?> getSearchResults(String query) async {
    final key = _searchKey(query);
    if (key.length < 2) return null;
    final db = await _database;
    final rows = await db.query(
      'rxnorm_search_cache',
      where: 'query_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final raw = rows.first['results_json'] as String?;
      if (raw == null || raw.isEmpty) return null;
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => MedicationSummary.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveSearchResults(String query, List<MedicationSummary> items) async {
    final key = _searchKey(query);
    if (key.length < 2) return;
    final db = await _database;
    final jsonStr = jsonEncode(items.map((e) => e.toJson()).toList());
    await db.insert(
      'rxnorm_search_cache',
      {
        'query_key': key,
        'results_json': jsonStr,
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<MedicationDetails?> getDetails(String rxcui) async {
    if (rxcui.trim().isEmpty) return null;
    final db = await _database;
    final rows = await db.query(
      'rxnorm_details_cache',
      where: 'rxcui = ?',
      whereArgs: [rxcui.trim()],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    try {
      final raw = rows.first['details_json'] as String?;
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final d = MedicationDetails.fromJson(m);
      return MedicationDetails(
        id: d.id,
        rxcui: d.rxcui,
        displayName: d.displayName,
        genericName: d.genericName,
        brandName: d.brandName,
        strength: d.strength,
        doseForm: d.doseForm,
        ingredients: d.ingredients,
        synonyms: d.synonyms,
        instructions: d.instructions,
        warnings: d.warnings,
        source: d.source,
        cachedAt: d.cachedAt,
        isFromCache: true,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> saveDetails(MedicationDetails details) async {
    final rxcui = details.rxcui.trim();
    if (rxcui.isEmpty) return;
    final db = await _database;
    final toStore = MedicationDetails(
      id: details.id,
      rxcui: details.rxcui,
      displayName: details.displayName,
      genericName: details.genericName,
      brandName: details.brandName,
      strength: details.strength,
      doseForm: details.doseForm,
      ingredients: details.ingredients,
      synonyms: details.synonyms,
      instructions: details.instructions,
      warnings: details.warnings,
      source: details.source,
      cachedAt: DateTime.now().toUtc(),
      isFromCache: false,
    );
    await db.insert(
      'rxnorm_details_cache',
      {
        'rxcui': rxcui,
        'details_json': jsonEncode(toStore.toJson()),
        'cached_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

/// In-memory cache for tests and lightweight tooling.
class MemoryRxNormMedicationCache implements RxNormMedicationCache {
  final Map<String, List<MedicationSummary>> _search = {};
  final Map<String, MedicationDetails> _details = {};

  String _searchKey(String query) => query.trim().toLowerCase();

  @override
  Future<List<MedicationSummary>?> getSearchResults(String query) async {
    final key = _searchKey(query);
    if (key.length < 2) return null;
    return _search[key];
  }

  @override
  Future<void> saveSearchResults(String query, List<MedicationSummary> items) async {
    final key = _searchKey(query);
    if (key.length < 2) return;
    _search[key] = List<MedicationSummary>.from(items);
  }

  @override
  Future<MedicationDetails?> getDetails(String rxcui) async {
    final id = rxcui.trim();
    if (id.isEmpty) return null;
    final d = _details[id];
    if (d == null) return null;
    return MedicationDetails(
      id: d.id,
      rxcui: d.rxcui,
      displayName: d.displayName,
      genericName: d.genericName,
      brandName: d.brandName,
      strength: d.strength,
      doseForm: d.doseForm,
      ingredients: d.ingredients,
      synonyms: d.synonyms,
      instructions: d.instructions,
      warnings: d.warnings,
      source: d.source,
      cachedAt: d.cachedAt,
      isFromCache: true,
    );
  }

  @override
  Future<void> saveDetails(MedicationDetails details) async {
    final id = details.rxcui.trim();
    if (id.isEmpty) return;
    _details[id] = details;
  }
}
