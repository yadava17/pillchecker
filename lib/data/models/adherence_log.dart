enum AdherenceAction {
  taken,
  missed,
  overrideMissed;

  static AdherenceAction fromValue(String value) {
    return AdherenceAction.values.firstWhere(
      (action) => action.name == value,
      orElse: () => AdherenceAction.taken,
    );
  }
}

class AdherenceLog {
  const AdherenceLog({
    this.id,
    required this.doseEventId,
    required this.medId,
    required this.action,
    required this.actionAt,
    this.note,
    required this.createdAt,
  });

  final int? id;
  final int doseEventId;
  final int medId;
  final AdherenceAction action;
  final DateTime actionAt;
  final String? note;
  final DateTime createdAt;

  AdherenceLog copyWith({
    int? id,
    int? doseEventId,
    int? medId,
    AdherenceAction? action,
    DateTime? actionAt,
    String? note,
    bool clearNote = false,
    DateTime? createdAt,
  }) {
    return AdherenceLog(
      id: id ?? this.id,
      doseEventId: doseEventId ?? this.doseEventId,
      medId: medId ?? this.medId,
      action: action ?? this.action,
      actionAt: actionAt ?? this.actionAt,
      note: clearNote ? null : (note ?? this.note),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'dose_event_id': doseEventId,
      'med_id': medId,
      'action': action.name,
      'action_at': actionAt.toIso8601String(),
      'note': note,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AdherenceLog.fromMap(Map<String, Object?> map) {
    return AdherenceLog(
      id: map['id'] as int?,
      doseEventId: map['dose_event_id'] as int,
      medId: map['med_id'] as int,
      action: AdherenceAction.fromValue(map['action'] as String),
      actionAt: DateTime.parse(map['action_at'] as String),
      note: map['note'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
