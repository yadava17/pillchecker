enum DoseStatus {
  pending,
  taken,
  missed;

  static DoseStatus fromValue(String value) {
    return DoseStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => DoseStatus.pending,
    );
  }
}

class DoseEvent {
  const DoseEvent({
    this.id,
    required this.medId,
    required this.scheduleId,
    required this.scheduledAt,
    required this.status,
    this.confirmedAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int medId;
  final int scheduleId;
  final DateTime scheduledAt;
  final DoseStatus status;
  final DateTime? confirmedAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  DoseEvent copyWith({
    int? id,
    int? medId,
    int? scheduleId,
    DateTime? scheduledAt,
    DoseStatus? status,
    DateTime? confirmedAt,
    bool clearConfirmedAt = false,
    String? notes,
    bool clearNotes = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DoseEvent(
      id: id ?? this.id,
      medId: medId ?? this.medId,
      scheduleId: scheduleId ?? this.scheduleId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      status: status ?? this.status,
      confirmedAt: clearConfirmedAt ? null : (confirmedAt ?? this.confirmedAt),
      notes: clearNotes ? null : (notes ?? this.notes),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'med_id': medId,
      'schedule_id': scheduleId,
      'scheduled_at': scheduledAt.toIso8601String(),
      'status': status.name,
      'confirmed_at': confirmedAt?.toIso8601String(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory DoseEvent.fromMap(Map<String, Object?> map) {
    return DoseEvent(
      id: map['id'] as int?,
      medId: map['med_id'] as int,
      scheduleId: map['schedule_id'] as int,
      scheduledAt: DateTime.parse(map['scheduled_at'] as String),
      status: DoseStatus.fromValue(map['status'] as String),
      confirmedAt: map['confirmed_at'] == null
          ? null
          : DateTime.parse(map['confirmed_at'] as String),
      notes: map['notes'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
