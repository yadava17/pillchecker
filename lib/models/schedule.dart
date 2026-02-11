class Schedule {
  final int? id;
  final int medicationId;
  final String timeOfDay;
  final bool isEnabled;

  Schedule({
    this.id,
    required this.medicationId,
    required this.timeOfDay,
    this.isEnabled = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'medication_id': medicationId,
      'time_of_day': timeOfDay,
      'is_enabled': isEnabled ? 1 : 0,
    };
  }

  factory Schedule.fromMap(Map<String, dynamic> map) {
    return Schedule(
      id: map['id'],
      medicationId: map['medication_id'],
      timeOfDay: map['time_of_day'],
      isEnabled: map['is_enabled'] == 1,
    );
  }

  Schedule copyWith({
    int? id,
    int? medicationId,
    String? timeOfDay,
    bool? isEnabled,
  }) {
    return Schedule(
      id: id ?? this.id,
      medicationId: medicationId ?? this.medicationId,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}
