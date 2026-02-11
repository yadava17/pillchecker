class PillInfo {
  final int? id;
  final String medicationName;
  final String rxcui;
  final String? genericName;
  final String? brandName;
  final String? description;
  final String? safetyNotes;
  final DateTime cachedAt;

  PillInfo({
    this.id,
    required this.medicationName,
    required this.rxcui,
    this.genericName,
    this.brandName,
    this.description,
    this.safetyNotes,
    DateTime? cachedAt,
  }) : cachedAt = cachedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'medication_name': medicationName,
      'rxcui': rxcui,
      'generic_name': genericName,
      'brand_name': brandName,
      'description': description,
      'safety_notes': safetyNotes,
      'cached_at': cachedAt.toIso8601String(),
    };
  }

  factory PillInfo.fromMap(Map<String, dynamic> map) {
    return PillInfo(
      id: map['id'],
      medicationName: map['medication_name'],
      rxcui: map['rxcui'],
      genericName: map['generic_name'],
      brandName: map['brand_name'],
      description: map['description'],
      safetyNotes: map['safety_notes'],
      cachedAt: DateTime.parse(map['cached_at']),
    );
  }
}
