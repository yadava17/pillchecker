import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:pillchecker/backend/services/med_service.dart';
import 'package:pillchecker/backend/services/schedule_service.dart';

/// One-time import from SharedPreferences when SQLite is empty.
class PrefsMigration {
  static const _doneKey = 'pillchecker_sqlite_prefs_migration_v1';

  static Future<void> runOnceIfNeeded({
    required MedService medService,
    required ScheduleService scheduleService,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_doneKey) == true) return;

    if (await medService.count() > 0) {
      await prefs.setBool(_doneKey, true);
      return;
    }

    const namesKey = 'pill_names';
    const doseKey = 'pill_dose_times_v2';
    const supplyEnKey = 'pill_supply_enabled_v1';
    const supplyLeftKey = 'pill_supply_left_v1';
    const supplyInitKey = 'pill_supply_init_v1';
    const nameLockedKey = 'pill_name_locked_v1';

    final names = prefs.getStringList(namesKey) ?? [];
    if (names.isEmpty) {
      await prefs.setBool(_doneKey, true);
      return;
    }

    List<List<String>> doseTimes = _decodeListOfStringLists(
      prefs.getString(doseKey),
    );
    while (doseTimes.length < names.length) {
      doseTimes.add(<String>['08:00']);
    }
    if (doseTimes.length > names.length) {
      doseTimes = doseTimes.sublist(0, names.length);
    }

    final supplyEn = _decodeBoolList(prefs.getString(supplyEnKey));
    final supplyLeft = _decodeIntList(prefs.getString(supplyLeftKey));
    final supplyInit = _decodeIntList(prefs.getString(supplyInitKey));
    final nameLocked = _decodeBoolList(prefs.getString(nameLockedKey));

    for (var i = 0; i < names.length; i++) {
      final times = List<String>.from(doseTimes[i]);

      final m = await medService.create(
        name: names[i],
        supplyEnabled: i < supplyEn.length ? supplyEn[i] : false,
        supplyLeft: i < supplyLeft.length ? supplyLeft[i] : 0,
        supplyInitial: i < supplyInit.length ? supplyInit[i] : 0,
        nameLocked: i < nameLocked.length ? nameLocked[i] : false,
        sortOrder: i,
      );

      await scheduleService.upsertSchedule(
        medicationId: m.id,
        times24hSorted: times,
      );
      await scheduleService.ensureDoseEventsForMedication(m.id);
    }

    await prefs.setBool(_doneKey, true);
  }

  static List<List<String>> _decodeListOfStringLists(String? raw) {
    if (raw == null || raw.isEmpty) return <List<String>>[];
    final decoded = jsonDecode(raw);
    return (decoded as List)
        .map((e) => (e as List).map((x) => x.toString()).toList())
        .toList();
  }

  static List<bool> _decodeBoolList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    return (decoded as List).map((e) => e == true).toList();
  }

  static List<int> _decodeIntList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    return (decoded as List).map((e) => (e as num).toInt()).toList();
  }
}
