/// Row from [dose_events] joined with optional display fields.
class DoseEventRecord {
  const DoseEventRecord({
    required this.id,
    required this.medicationId,
    required this.scheduleId,
    required this.plannedAtUtc,
    required this.doseIndex,
    required this.status,
    required this.isOverridden,
    this.takenAtUtc,
    this.medicationName,
  });

  final int id;
  final int medicationId;
  final int scheduleId;
  final DateTime plannedAtUtc;
  final int doseIndex;
  /// planned | taken | missed
  final String status;
  final bool isOverridden;
  final DateTime? takenAtUtc;
  final String? medicationName;

  static DoseEventRecord fromMap(Map<String, Object?> m) {
    return DoseEventRecord(
      id: m['id']! as int,
      medicationId: m['medication_id']! as int,
      scheduleId: m['schedule_id']! as int,
      plannedAtUtc: DateTime.parse(m['planned_at']! as String),
      doseIndex: m['dose_index']! as int,
      status: m['status']! as String,
      isOverridden: (m['is_overridden'] as int) != 0,
      takenAtUtc: m['taken_at'] != null
          ? DateTime.parse(m['taken_at']! as String)
          : null,
      medicationName: m['medication_name'] as String?,
    );
  }
}
