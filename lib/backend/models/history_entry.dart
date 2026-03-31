/// Display model for history rows (not a raw DB table).
class HistoryEntry {
  const HistoryEntry({
    required this.doseEventId,
    required this.medicationName,
    required this.plannedAtLocal,
    required this.actionLabel,
    required this.isOverridden,
    this.loggedAtLocal,
  });

  final int doseEventId;
  final String medicationName;
  final DateTime plannedAtLocal;
  final String actionLabel;
  final bool isOverridden;
  final DateTime? loggedAtLocal;

  String get displayStatus {
    if (isOverridden && actionLabel == 'taken') {
      return 'Taken (Overridden)';
    }
    switch (actionLabel) {
      case 'taken':
        return 'Taken';
      case 'missed':
        return 'Missed';
      case 'override':
        return 'Taken (Overridden)';
      default:
        return actionLabel;
    }
  }
}
