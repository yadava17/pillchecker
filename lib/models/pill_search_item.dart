
class PillSearchItem {
  final String name;

  /// How many doses/day we want to pre-fill on the configure panel.
  final int suggestedTimesPerDay;

  /// Placeholder “info” text (later this becomes RxNorm-driven).
  final String info;

  const PillSearchItem({
    required this.name,
    required this.suggestedTimesPerDay,
    required this.info,
  });
}