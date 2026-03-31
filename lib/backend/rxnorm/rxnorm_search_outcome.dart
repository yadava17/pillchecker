import 'medication_summary.dart';

/// Result of a lookup — distinguishes fresh RxNav data from SQLite fallback.
class RxNormSearchOutcome {
  const RxNormSearchOutcome({
    required this.items,
    required this.servedFromCache,
    required this.hadNetworkError,
  });

  final List<MedicationSummary> items;
  final bool servedFromCache;

  /// True when the RxNav request failed (timeout, offline, parse error, etc.).
  final bool hadNetworkError;
}
