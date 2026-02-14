import 'dart:math';

import 'package:pillchecker/data/models/adherence_log.dart';
import 'package:pillchecker/data/models/dose_event.dart';
import 'package:pillchecker/data/models/dose_event_details.dart';
import 'package:pillchecker/data/models/medication.dart';
import 'package:pillchecker/data/models/schedule_model.dart';
import 'package:pillchecker/data/repositories/adherence_log_repository.dart';
import 'package:pillchecker/data/repositories/dose_event_repository.dart';
import 'package:pillchecker/data/repositories/medication_repository.dart';
import 'package:pillchecker/data/repositories/schedule_repository.dart';

class PillCheckerService {
  PillCheckerService({
    MedicationRepository? medicationRepository,
    ScheduleRepository? scheduleRepository,
    DoseEventRepository? doseEventRepository,
    AdherenceLogRepository? adherenceLogRepository,
  }) : _medicationRepository = medicationRepository ?? MedicationRepository(),
       _scheduleRepository = scheduleRepository ?? ScheduleRepository(),
       _doseEventRepository = doseEventRepository ?? DoseEventRepository(),
       _adherenceLogRepository =
           adherenceLogRepository ?? AdherenceLogRepository();

  final MedicationRepository _medicationRepository;
  final ScheduleRepository _scheduleRepository;
  final DoseEventRepository _doseEventRepository;
  final AdherenceLogRepository _adherenceLogRepository;

  DateTime? _todayCacheDate;
  List<DoseEventDetails>? _todayCache;
  int? _historyCacheLimit;
  List<AdherenceLog>? _historyCache;

  Future<int> addMedicationWithSchedule({
    required String name,
    required String dosage,
    String? notes,
    required String scheduleTimeOfDay,
    int frequencyPerDay = 1,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final now = DateTime.now();
    final medication = Medication(
      name: name,
      dosage: dosage,
      notes: notes,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    final medId = await _medicationRepository.create(medication);

    final schedule = ScheduleModel(
      medId: medId,
      timeOfDay: _normalizeTimeOfDay(scheduleTimeOfDay),
      frequencyPerDay: max(1, frequencyPerDay),
      startDate: _startOfDay(startDate ?? now),
      endDate: endDate == null ? null : _startOfDay(endDate),
      createdAt: now,
      updatedAt: now,
    );

    final scheduleId = await _scheduleRepository.create(schedule);
    await _generateDoseEventsForSchedule(schedule.copyWith(id: scheduleId), 7);
    _invalidateCaches();
    return medId;
  }

  Future<int> generateDoseEventsForNext7Days({int? medicationId}) async {
    final schedules = medicationId == null
        ? await _scheduleRepository.getAll()
        : await _scheduleRepository.getByMedicationId(medicationId);

    var createdCount = 0;
    for (final schedule in schedules) {
      createdCount += await _generateDoseEventsForSchedule(schedule, 7);
    }

    if (createdCount > 0) {
      _invalidateCaches();
    }
    return createdCount;
  }

  Future<void> confirmDoseStatus(
    int doseEventId, {
    DoseStatus status = DoseStatus.taken,
    String? note,
  }) async {
    final existing = await _doseEventRepository.getById(doseEventId);
    if (existing == null) {
      throw StateError('Dose event $doseEventId was not found');
    }

    final now = DateTime.now();
    final updated = existing.copyWith(
      status: status,
      confirmedAt: now,
      notes: note,
      updatedAt: now,
    );

    await _doseEventRepository.update(updated);
    await _adherenceLogRepository.create(
      AdherenceLog(
        doseEventId: updated.id!,
        medId: updated.medId,
        action: _actionForStatus(status),
        actionAt: now,
        note: note,
        createdAt: now,
      ),
    );
    _invalidateCaches();
  }

  Future<void> markMissed(int doseEventId, {String? note}) async {
    await confirmDoseStatus(doseEventId, status: DoseStatus.missed, note: note);
  }

  Future<void> overrideMissed(int doseEventId, {String? note}) async {
    final existing = await _doseEventRepository.getById(doseEventId);
    if (existing == null) {
      throw StateError('Dose event $doseEventId was not found');
    }
    if (existing.status != DoseStatus.missed) {
      throw StateError('Dose event $doseEventId is not marked as missed');
    }

    final now = DateTime.now();
    final updated = existing.copyWith(
      status: DoseStatus.taken,
      confirmedAt: now,
      notes: note ?? existing.notes,
      updatedAt: now,
    );

    await _doseEventRepository.update(updated);
    await _adherenceLogRepository.create(
      AdherenceLog(
        doseEventId: updated.id!,
        medId: updated.medId,
        action: AdherenceAction.overrideMissed,
        actionAt: now,
        note: note,
        createdAt: now,
      ),
    );
    _invalidateCaches();
  }

  Future<List<DoseEventDetails>> getTodayDoseEvents() async {
    final today = _startOfDay(DateTime.now());
    if (_todayCacheDate == today && _todayCache != null) {
      return List.unmodifiable(_todayCache!);
    }

    final start = today;
    final end = today
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));
    final events = await _doseEventRepository.getByDateRange(start, end);

    final medicationIds = events.map((event) => event.medId).toSet().toList();
    final scheduleIds = events
        .map((event) => event.scheduleId)
        .toSet()
        .toList();

    final medications = await _medicationRepository.getByIds(medicationIds);
    final schedules = await _scheduleRepository.getByIds(scheduleIds);
    final medicationById = {
      for (final medication in medications)
        if (medication.id != null) medication.id!: medication,
    };
    final scheduleById = {
      for (final schedule in schedules)
        if (schedule.id != null) schedule.id!: schedule,
    };

    final details =
        events
            .where(
              (event) =>
                  medicationById.containsKey(event.medId) &&
                  scheduleById.containsKey(event.scheduleId),
            )
            .map(
              (event) => DoseEventDetails(
                event: event,
                medication: medicationById[event.medId]!,
                schedule: scheduleById[event.scheduleId]!,
              ),
            )
            .toList()
          ..sort((a, b) => a.event.scheduledAt.compareTo(b.event.scheduledAt));

    _todayCacheDate = today;
    _todayCache = details;
    return List.unmodifiable(details);
  }

  Future<List<AdherenceLog>> getHistoryLogs({int limit = 100}) async {
    if (_historyCache != null && _historyCacheLimit == limit) {
      return List.unmodifiable(_historyCache!);
    }

    final logs = await _adherenceLogRepository.getAll(limit: limit);
    _historyCache = logs;
    _historyCacheLimit = limit;
    return List.unmodifiable(logs);
  }

  Future<int> _generateDoseEventsForSchedule(
    ScheduleModel schedule,
    int days,
  ) async {
    final scheduleId = schedule.id;
    if (scheduleId == null) {
      throw ArgumentError('Schedule id is required for event generation');
    }

    final today = _startOfDay(DateTime.now());
    final startDate = _startOfDay(schedule.startDate);
    final endDate = schedule.endDate == null
        ? null
        : _startOfDay(schedule.endDate!);

    var createdCount = 0;
    for (var dayOffset = 0; dayOffset < days; dayOffset++) {
      final day = today.add(Duration(days: dayOffset));
      if (day.isBefore(startDate)) {
        continue;
      }
      if (endDate != null && day.isAfter(endDate)) {
        continue;
      }

      final doseTimes = _buildDoseTimesForDay(
        day: day,
        timeOfDay: schedule.timeOfDay,
        frequencyPerDay: schedule.frequencyPerDay,
      );

      for (final scheduledAt in doseTimes) {
        final now = DateTime.now();
        final inserted = await _doseEventRepository.createIfAbsent(
          DoseEvent(
            medId: schedule.medId,
            scheduleId: scheduleId,
            scheduledAt: scheduledAt,
            status: DoseStatus.pending,
            createdAt: now,
            updatedAt: now,
          ),
        );
        if (inserted > 0) {
          createdCount++;
        }
      }
    }
    return createdCount;
  }

  List<DateTime> _buildDoseTimesForDay({
    required DateTime day,
    required String timeOfDay,
    required int frequencyPerDay,
  }) {
    final normalizedFrequency = max(1, frequencyPerDay);
    final parts = _normalizeTimeOfDay(timeOfDay).split(':');
    final baseHour = int.parse(parts[0]);
    final baseMinute = int.parse(parts[1]);
    final baseMinuteOfDay = (baseHour * 60) + baseMinute;

    if (normalizedFrequency == 1) {
      return [DateTime(day.year, day.month, day.day, baseHour, baseMinute)];
    }

    final remainingMinutesInDay = max(1, (24 * 60) - baseMinuteOfDay);
    final intervalMinutes = max(
      1,
      (remainingMinutesInDay / normalizedFrequency).floor(),
    );

    final events = <DateTime>[];
    for (var i = 0; i < normalizedFrequency; i++) {
      final minuteOfDay = baseMinuteOfDay + (i * intervalMinutes);
      if (minuteOfDay >= 24 * 60) {
        break;
      }
      events.add(
        DateTime(
          day.year,
          day.month,
          day.day,
          minuteOfDay ~/ 60,
          minuteOfDay % 60,
        ),
      );
    }
    return events;
  }

  String _normalizeTimeOfDay(String input) {
    final parts = input.trim().split(':');
    if (parts.length != 2) {
      throw const FormatException('timeOfDay must be in HH:mm format');
    }

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) {
      throw const FormatException('timeOfDay must contain valid numbers');
    }
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw const FormatException('timeOfDay must be a valid 24h time');
    }

    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  AdherenceAction _actionForStatus(DoseStatus status) {
    switch (status) {
      case DoseStatus.taken:
        return AdherenceAction.taken;
      case DoseStatus.missed:
        return AdherenceAction.missed;
      case DoseStatus.pending:
        return AdherenceAction.taken;
    }
  }

  void _invalidateCaches() {
    _todayCacheDate = null;
    _todayCache = null;
    _historyCache = null;
    _historyCacheLimit = null;
  }
}
