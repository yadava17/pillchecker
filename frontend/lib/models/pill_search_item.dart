
class PillSearchItem {
  final String name;

  /// How many doses/day we want to pre-fill on the configure panel.
  final int suggestedTimesPerDay;

  /// Shown in the info panel — may include RxNorm-sourced plain-language text.
  final String info;

  /// RxNorm concept id when this row came from online lookup.
  final String? rxcui;

  /// Extra line in search results (strength / form / generic hint).
  final String? searchSubtitle;

  /// True when search results were loaded from SQLite (offline / API failure).
  final bool isFromCache;

  const PillSearchItem({
    required this.name,
    required this.suggestedTimesPerDay,
    required this.info,
    this.rxcui,
    this.searchSubtitle,
    this.isFromCache = false,
  });

  /// Local suggestions — not tied to RxNorm.
  bool get isRxNorm => rxcui != null && rxcui!.trim().isNotEmpty;
}
