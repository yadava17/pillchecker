class Medication {
  final int? id;
  final String name;
  final String dosage;
  final String strength;
  final String form;
  final int timesPerDay;
  final List<int> daysOfWeek;
  final bool withFood;
  final String? notes;
  final DateTime createdAt;
  final bool isActive;

  Medication({
    this.id,
    required this.name,
    required this.dosage,
    required this.strength,
    required this.form,
    required this.timesPerDay,
    required this.daysOfWeek,
    this.withFood = false,
    this.notes,
    DateTime? createdAt,
    this.isActive = true,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'dosage': dosage,
      'strength': strength,
      'form': form,
      'times_per_day': timesPerDay,
      'days_of_week': daysOfWeek.join(','),
      'with_food': withFood ? 1 : 0,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive ? 1 : 0,
    };
  }

  factory Medication.fromMap(Map<String, dynamic> map) {
    return Medication(
      id: map['id'],
      name: map['name'],
      dosage: map['dosage'],
      strength: map['strength'],
      form: map['form'],
      timesPerDay: map['times_per_day'],
      daysOfWeek: (map['days_of_week'] as String)
          .split(',')
          .map((e) => int.parse(e))
          .toList(),
      withFood: map['with_food'] == 1,
      notes: map['notes'],
      createdAt: DateTime.parse(map['created_at']),
      isActive: map['is_active'] == 1,
    );
  }

  Medication copyWith({
    int? id,
    String? name,
    String? dosage,
    String? strength,
    String? form,
    int? timesPerDay,
    List<int>? daysOfWeek,
    bool? withFood,
    String? notes,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return Medication(
      id: id ?? this.id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      strength: strength ?? this.strength,
      form: form ?? this.form,
      timesPerDay: timesPerDay ?? this.timesPerDay,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      withFood: withFood ?? this.withFood,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
