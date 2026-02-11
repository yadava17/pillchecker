import '../database/database_helper.dart';
import '../models/medication.dart';
import '../models/schedule.dart';

class MedicationService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<int> addMedication(
    Medication medication,
    List<String> scheduleTimes,
  ) async {
    final medicationId = await _db.insertMedication(medication);

    for (final time in scheduleTimes) {
      final schedule = Schedule(
        medicationId: medicationId,
        timeOfDay: time,
      );
      await _db.insertSchedule(schedule);
    }

    return medicationId;
  }

  Future<Medication?> getMedication(int id) async {
    return await _db.getMedication(id);
  }

  Future<List<Medication>> getAllActiveMedications() async {
    return await _db.getAllMedications(activeOnly: true);
  }

  Future<List<Medication>> getAllMedications() async {
    return await _db.getAllMedications(activeOnly: false);
  }

  Future<void> updateMedication(
    Medication medication,
    List<String> scheduleTimes,
  ) async {
    await _db.updateMedication(medication);

    final existingSchedules =
        await _db.getSchedulesForMedication(medication.id!);

    for (final schedule in existingSchedules) {
      await _db.deleteSchedule(schedule.id!);
    }

    for (final time in scheduleTimes) {
      final schedule = Schedule(
        medicationId: medication.id!,
        timeOfDay: time,
      );
      await _db.insertSchedule(schedule);
    }
  }

  Future<void> deleteMedication(int id) async {
    await _db.deleteMedication(id);
  }

  Future<List<Schedule>> getSchedulesForMedication(int medicationId) async {
    return await _db.getSchedulesForMedication(medicationId);
  }

  Future<Map<Medication, List<Schedule>>> getAllMedicationsWithSchedules() async {
    final medications = await getAllActiveMedications();
    final result = <Medication, List<Schedule>>{};

    for (final medication in medications) {
      final schedules = await getSchedulesForMedication(medication.id!);
      result[medication] = schedules;
    }

    return result;
  }
}
