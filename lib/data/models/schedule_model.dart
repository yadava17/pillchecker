class ScheduleModel {
  const ScheduleModel({
    this.id,
    required this.medId,
    required this.timeOfDay,
    required this.frequencyPerDay,
    required this.startDate,
    this.endDate,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int medId;
  final String timeOfDay;
  final int frequencyPerDay;
  final DateTime startDate;
  final DateTime? endDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  ScheduleModel copyWith({
    int? id,
    int? medId,
    String? timeOfDay,
    int? frequencyPerDay,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ScheduleModel(
      id: id ?? this.id,
      medId: medId ?? this.medId,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      frequencyPerDay: frequencyPerDay ?? this.frequencyPerDay,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'med_id': medId,
      'time_of_day': timeOfDay,
      'frequency_per_day': frequencyPerDay,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ScheduleModel.fromMap(Map<String, Object?> map) {
    return ScheduleModel(
      id: map['id'] as int?,
      medId: map['med_id'] as int,
      timeOfDay: map['time_of_day'] as String,
      frequencyPerDay: map['frequency_per_day'] as int,
      startDate: DateTime.parse(map['start_date'] as String),
      endDate: map['end_date'] == null
          ? null
          : DateTime.parse(map['end_date'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
