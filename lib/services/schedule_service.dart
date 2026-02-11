import '../models/medication.dart';
import '../models/schedule.dart';
import '../models/dose_log.dart';
import '../database/database_helper.dart';

class ScheduledDose {
  final Medication medication;
  final Schedule schedule;
  final DateTime scheduledTime;
  final DoseLog? doseLog;

  ScheduledDose({
    required this.medication,
    required this.schedule,
    required this.scheduledTime,
    this.doseLog,
  });

  bool get isTaken =>
      doseLog?.status == DoseStatus.taken ||
      doseLog?.status == DoseStatus.overridden;

  bool get isMissed => doseLog?.status == DoseStatus.missed;

  bool get isSkipped => doseLog?.status == DoseStatus.skipped;

  bool get isScheduled => doseLog == null || doseLog?.status == DoseStatus.scheduled;

  bool get isPast => DateTime.now().isAfter(scheduledTime);
}

class ScheduleService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<ScheduledDose>> getTodaySchedule() async {
    final today = DateTime.now();
    return await getScheduleForDate(today);
  }

  Future<List<ScheduledDose>> getScheduleForDate(DateTime date) async {
    final medications = await _db.getAllMedications(activeOnly: true);
    final scheduledDoses = <ScheduledDose>[];
    final dayOfWeek = date.weekday;

    for (final medication in medications) {
      if (!medication.daysOfWeek.contains(dayOfWeek)) {
        continue;
      }

      final schedules = await _db.getSchedulesForMedication(medication.id!);

      for (final schedule in schedules) {
        if (!schedule.isEnabled) continue;

        final scheduledTime = _parseScheduledTime(date, schedule.timeOfDay);
        final doseLog = await _findDoseLog(
          medication.id!,
          schedule.id!,
          scheduledTime,
        );

        scheduledDoses.add(ScheduledDose(
          medication: medication,
          schedule: schedule,
          scheduledTime: scheduledTime,
          doseLog: doseLog,
        ));
      }
    }

    scheduledDoses.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

    return scheduledDoses;
  }

  Future<List<ScheduledDose>> getUpcomingDoses({int hours = 24}) async {
    final now = DateTime.now();
    final endTime = now.add(Duration(hours: hours));

    final allDoses = <ScheduledDose>[];

    for (int i = 0; i <= hours ~/ 24; i++) {
      final date = now.add(Duration(days: i));
      final doses = await getScheduleForDate(date);
      allDoses.addAll(doses);
    }

    return allDoses
        .where((dose) =>
            dose.scheduledTime.isAfter(now) &&
            dose.scheduledTime.isBefore(endTime) &&
            !dose.isTaken)
        .toList();
  }

  DateTime _parseScheduledTime(DateTime date, String timeOfDay) {
    final parts = timeOfDay.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    return DateTime(date.year, date.month, date.day, hour, minute);
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
}
