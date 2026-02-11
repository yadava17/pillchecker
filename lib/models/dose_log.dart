enum DoseStatus {
  scheduled,
  taken,
  missed,
  overridden,
  skipped,
}

class DoseLog {
  final int? id;
  final int medicationId;
  final int scheduleId;
  final DateTime scheduledTime;
  final DateTime? takenTime;
  final DoseStatus status;
  final String? notes;
  final bool isOverride;
  final DateTime createdAt;

  DoseLog({
    this.id,
    required this.medicationId,
    required this.scheduleId,
    required this.scheduledTime,
    this.takenTime,
    required this.status,
    this.notes,
    this.isOverride = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'medication_id': medicationId,
      'schedule_id': scheduleId,
      'scheduled_time': scheduledTime.toIso8601String(),
      'taken_time': takenTime?.toIso8601String(),
      'status': status.name,
      'notes': notes,
      'is_override': isOverride ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory DoseLog.fromMap(Map<String, dynamic> map) {
    return DoseLog(
      id: map['id'],
      medicationId: map['medication_id'],
      scheduleId: map['schedule_id'],
      scheduledTime: DateTime.parse(map['scheduled_time']),
      takenTime:
          map['taken_time'] != null ? DateTime.parse(map['taken_time']) : null,
      status: DoseStatus.values.firstWhere((e) => e.name == map['status']),
      notes: map['notes'],
      isOverride: map['is_override'] == 1,
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  DoseLog copyWith({
    int? id,
    int? medicationId,
    int? scheduleId,
    DateTime? scheduledTime,
    DateTime? takenTime,
    DoseStatus? status,
    String? notes,
    bool? isOverride,
    DateTime? createdAt,
  }) {
    return DoseLog(
      id: id ?? this.id,
      medicationId: medicationId ?? this.medicationId,
      scheduleId: scheduleId ?? this.scheduleId,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      takenTime: takenTime ?? this.takenTime,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      isOverride: isOverride ?? this.isOverride,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
