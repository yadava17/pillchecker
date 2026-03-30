import '../repositories/rxnorm_cache_repository.dart';
import '../rxnorm/medication_details.dart';
import '../rxnorm/medication_summary.dart';
import '../rxnorm/rxnav_api_client.dart';
import '../rxnorm/rxnorm_details_mapper.dart';
import '../rxnorm/rxnorm_response_mapper.dart';
import '../rxnorm/rxnorm_search_outcome.dart';

/// High-level RxNorm/RxNav access with SQLite caching and safe fallbacks.
/// Network errors propagate from [RxNavApiClient] so this layer can return stale rows.
class RxNormMedicationService {
  RxNormMedicationService({
    RxNavApiClient? apiClient,
    RxNormMedicationCache? cache,
  })  : _api = apiClient ?? RxNavApiClient(),
        _cache = cache ?? RxNormCacheRepository();

  final RxNavApiClient _api;
  final RxNormMedicationCache _cache;

  /// Online-first search; on failure returns last cached results for the query.
  Future<RxNormSearchOutcome> searchMedications(String query) async {
    final q = query.trim();
    if (q.length < 2) {
      return const RxNormSearchOutcome(
        items: [],
        servedFromCache: false,
        hadNetworkError: false,
      );
    }

    List<MedicationSummary> merged = [];
    try {
      final drugs = await _api.drugsByName(q);
      merged = RxNormResponseMapper.parseDrugsResponse(drugs, q);

      if (merged.length < 12) {
        final approx = await _api.approximateTerm(q);
        final extra =
            RxNormResponseMapper.parseApproximateCandidates(approx, q);
        final seen = merged.map((e) => e.rxcui).toSet();
        for (final e in extra) {
          if (!seen.contains(e.rxcui)) {
            merged.add(e);
            seen.add(e.rxcui);
          }
        }
        merged = RxNormResponseMapper.dedupeAndSort(merged, q);
      }

      if (merged.isNotEmpty) {
        await _cache.saveSearchResults(q, merged);
      }
      return RxNormSearchOutcome(
        items: merged.take(30).toList(),
        servedFromCache: false,
        hadNetworkError: false,
      );
    } on Object {
      final stale = await _cache.getSearchResults(q);
      return RxNormSearchOutcome(
        items: stale ?? [],
        servedFromCache: stale != null,
        hadNetworkError: true,
      );
    }
  }

  /// Cached details first for instant UI; refreshes from network when possible.
  Future<MedicationDetails?> getMedicationDetails(
    String rxcui, {
    String? fallbackName,
  }) async {
    final id = rxcui.trim();
    if (id.isEmpty) return null;

    final cached = await _cache.getDetails(id);
    try {
      final allProperties = await _api.allProperties(id);
      final relatedBrand = await _api.related(id, tty: 'BN');
      final relatedIngredient = await _api.related(id, tty: 'IN');

      final details = RxNormDetailsMapper.merge(
        rxcui: id,
        allProperties: allProperties,
        relatedBrand: relatedBrand,
        relatedIngredient: relatedIngredient,
        fallbackDisplayName: fallbackName,
        isFromCache: false,
      );

      await _cache.saveDetails(details);
      return details;
    } on Object {
      return cached;
    }
  }

  Future<MedicationDetails?> getCachedMedication(String rxcui) =>
      _cache.getDetails(rxcui.trim());

  Future<void> cacheMedicationDetails(MedicationDetails details) =>
      _cache.saveDetails(details);

  void dispose() => _api.dispose();
}
