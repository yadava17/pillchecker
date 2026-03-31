class MedicationRecord {
  const MedicationRecord({
    required this.id,
    required this.name,
    required this.supplyEnabled,
    required this.supplyLeft,
    required this.supplyInitial,
    required this.nameLocked,
    required this.sortOrder,
    required this.createdAt,
  });

  final int id;
  final String name;
  final bool supplyEnabled;
  final int supplyLeft;
  final int supplyInitial;
  final bool nameLocked;
  final int sortOrder;
  final DateTime createdAt;

  static MedicationRecord fromMap(Map<String, Object?> m) {
    return MedicationRecord(
      id: m['id']! as int,
      name: m['name']! as String,
      supplyEnabled: (m['supply_enabled'] as int) != 0,
      supplyLeft: (m['supply_left'] as int?) ?? 0,
      supplyInitial: (m['supply_initial'] as int?) ?? 0,
      nameLocked: (m['name_locked'] as int) != 0,
      sortOrder: (m['sort_order'] as int?) ?? 0,
      createdAt: DateTime.parse(m['created_at']! as String),
    );
  }
}
