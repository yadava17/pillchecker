import '../database/database_helper.dart';
import '../models/dose_log.dart';

class AdherenceService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<void> confirmDose(
    int medicationId,
    int scheduleId,
    DateTime scheduledTime,
  ) async {
    final existingLog = await _findDoseLog(
      medicationId,
      scheduleId,
      scheduledTime,
    );

    if (existingLog != null && existingLog.status == DoseStatus.taken) {
      return;
    }

    final doseLog = DoseLog(
      medicationId: medicationId,
      scheduleId: scheduleId,
      scheduledTime: scheduledTime,
      takenTime: DateTime.now(),
      status: DoseStatus.taken,
    );

    if (existingLog != null) {
      await _db.updateDoseLog(doseLog.copyWith(id: existingLog.id));
    } else {
      await _db.insertDoseLog(doseLog);
    }
  }

  Future<void> markDoseMissed(
    int medicationId,
    int scheduleId,
    DateTime scheduledTime,
  ) async {
    final existingLog = await _findDoseLog(
      medicationId,
      scheduleId,
      scheduledTime,
    );

    final doseLog = DoseLog(
      medicationId: medicationId,
      scheduleId: scheduleId,
      scheduledTime: scheduledTime,
      status: DoseStatus.missed,
    );

    if (existingLog != null) {
      await _db.updateDoseLog(doseLog.copyWith(id: existingLog.id));
    } else {
      await _db.insertDoseLog(doseLog);
    }
  }

  Future<void> overrideMissedDose(
    int medicationId,
    int scheduleId,
    DateTime scheduledTime,
    String? notes,
  ) async {
    final existingLog = await _findDoseLog(
      medicationId,
      scheduleId,
      scheduledTime,
    );

    if (existingLog == null) {
      throw Exception('Cannot override a dose that does not exist');
    }

    final updatedLog = existingLog.copyWith(
      status: DoseStatus.overridden,
      takenTime: DateTime.now(),
      isOverride: true,
      notes: notes,
    );

    await _db.updateDoseLog(updatedLog);
  }

  Future<void> skipDose(
    int medicationId,
    int scheduleId,
    DateTime scheduledTime,
    String? reason,
  ) async {
    final existingLog = await _findDoseLog(
      medicationId,
      scheduleId,
      scheduledTime,
    );

    final doseLog = DoseLog(
      medicationId: medicationId,
      scheduleId: scheduleId,
      scheduledTime: scheduledTime,
      status: DoseStatus.skipped,
      notes: reason,
    );

    if (existingLog != null) {
      await _db.updateDoseLog(doseLog.copyWith(id: existingLog.id));
    } else {
      await _db.insertDoseLog(doseLog);
    }
  }

  Future<DoseLog?> _findDoseLog(
    int medicationId,
    int scheduleId,
    DateTime scheduledTime,
  ) async {
    final startOfDay = DateTime(
      scheduledTime.year,
      scheduledTime.month,
      scheduledTime.day,
    );
    final logs = await _db.getDoseLogsForDate(startOfDay);

    for (final log in logs) {
      if (log.medicationId == medicationId &&
          log.scheduleId == scheduleId &&
          _isSameScheduledTime(log.scheduledTime, scheduledTime)) {
        return log;
      }
    }

    return null;
  }

  bool _isSameScheduledTime(DateTime time1, DateTime time2) {
    return time1.year == time2.year &&
        time1.month == time2.month &&
        time1.day == time2.day &&
        time1.hour == time2.hour &&
        time1.minute == time2.minute;
  }

  Future<List<DoseLog>> getDoseLogsForDate(DateTime date) async {
    return await _db.getDoseLogsForDate(date);
  }

  Future<List<DoseLog>> getDoseLogsForMedication(
    int medicationId, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return await _db.getDoseLogsForMedication(
      medicationId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<double> calculateAdherenceRate({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final logs = await _db.getDoseLogsForMedication(
      0,
      startDate: startDate,
      endDate: endDate,
    );

    if (logs.isEmpty) return 0.0;

    final takenCount = logs
        .where((log) =>
            log.status == DoseStatus.taken ||
            log.status == DoseStatus.overridden)
        .length;

    return (takenCount / logs.length) * 100;
  }

  Future<Map<String, dynamic>> getAdherenceStats({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final allLogs = <DoseLog>[];
    final medications = await _db.getAllMedications(activeOnly: true);

    for (final med in medications) {
      final logs = await _db.getDoseLogsForMedication(
        med.id!,
        startDate: startDate,
        endDate: endDate,
      );
      allLogs.addAll(logs);
    }

    final totalDoses = allLogs.length;
    final takenDoses = allLogs
        .where((log) =>
            log.status == DoseStatus.taken ||
            log.status == DoseStatus.overridden)
        .length;
    final missedDoses =
        allLogs.where((log) => log.status == DoseStatus.missed).length;
    final skippedDoses =
        allLogs.where((log) => log.status == DoseStatus.skipped).length;

    final adherenceRate =
        totalDoses > 0 ? (takenDoses / totalDoses) * 100 : 0.0;

    return {
      'totalDoses': totalDoses,
      'takenDoses': takenDoses,
      'missedDoses': missedDoses,
      'skippedDoses': skippedDoses,
      'adherenceRate': adherenceRate,
    };
  }

  Future<int> getCurrentStreak() async {
    final today = DateTime.now();
    int streak = 0;

    for (int i = 0; i < 365; i++) {
      final date = today.subtract(Duration(days: i));
      final logs = await getDoseLogsForDate(date);

      if (logs.isEmpty) break;

      final allTaken = logs.every(
        (log) =>
            log.status == DoseStatus.taken ||
            log.status == DoseStatus.overridden,
      );

      if (allTaken) {
        streak++;
      } else {
        break;
      }
    }

    return streak;
  }
}
