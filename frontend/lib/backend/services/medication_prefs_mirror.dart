import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Keeps legacy SharedPreferences keys in sync so [NotificationService] keeps working.
class MedicationPrefsMirror {
  static Future<void> write({
    required List<String> pillNames,
    required List<String> pillTimesFirst,
    required List<List<String>> pillDoseTimes,
    required List<bool> pillSupplyEnabled,
    required List<int> pillSupplyLeft,
    required List<int> pillSupplyInitial,
    required List<bool> pillSupplyLowSent,
    required List<bool> pillNameLocked,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList('pill_names', pillNames);
    await prefs.setStringList('pill_times', pillTimesFirst);
    await prefs.setString('pill_dose_times_v2', jsonEncode(pillDoseTimes));

    await prefs.setString(
      'pill_supply_enabled_v1',
      jsonEncode(pillSupplyEnabled),
    );
    await prefs.setString('pill_supply_left_v1', jsonEncode(pillSupplyLeft));
    await prefs.setString('pill_supply_init_v1', jsonEncode(pillSupplyInitial));
    await prefs.setString(
      'pill_supply_low_sent_v1',
      jsonEncode(pillSupplyLowSent),
    );
    await prefs.setString('pill_name_locked_v1', jsonEncode(pillNameLocked));
  }
}
