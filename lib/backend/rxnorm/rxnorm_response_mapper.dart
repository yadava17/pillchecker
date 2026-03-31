import 'medication_summary.dart';
import 'rxnorm_name_parser.dart';

/// Maps raw RxNav JSON into [MedicationSummary] and dedupes by rxcui.
class RxNormResponseMapper {
  /// tty priority: more useful for end users first (branded/clinical SCD/SBD).
  static const List<String> ttyPriority = [
    'SBD', // branded drug
    'BPCK', // branded pack
    'SCD', // clinical drug
    'GPCK', // generic pack
    'BN', // brand name
    'IN', // ingredient
    'PIN', // precise ingredient
    'MIN', // multi-ingredient
    'SY', // synonym
  ];

  static int ttyRank(String? tty) {
    if (tty == null || tty.isEmpty) return 99;
    final i = ttyPriority.indexOf(tty);
    return i >= 0 ? i : 50;
  }

  static List<MedicationSummary> parseDrugsResponse(
    Map<String, dynamic>? json,
    String query,
  ) {
    if (json == null) return [];
    final list = <MedicationSummary>[];
    final drugGroup = json['drugGroup'];
    if (drugGroup is! Map) return [];
    walkConceptGroups(Map<String, dynamic>.from(drugGroup), list);
    return dedupeAndSort(list, query);
  }

  static void walkConceptGroups(Map<String, dynamic> drugGroup, List<MedicationSummary> out) {
    final groups = drugGroup['conceptGroup'];
    if (groups is! List) return;
    for (final g in groups) {
      if (g is! Map) continue;
      final props = g['conceptProperties'];
      if (props is! List) continue;
      for (final p in props) {
        if (p is! Map) continue;
        final rxcui = p['rxcui']?.toString();
        final name = p['name']?.toString();
        final tty = p['tty']?.toString();
        if (rxcui == null || rxcui.isEmpty || name == null || name.isEmpty) {
          continue;
        }
        final strength = RxNormNameParser.extractStrength(name);
        final doseForm = RxNormNameParser.extractDoseForm(name);
        out.add(
          MedicationSummary(
            id: rxcui,
            rxcui: rxcui,
            displayName: _displayTitle(name, tty),
            genericName: _maybeGeneric(name, tty),
            brandName: _maybeBrand(name, tty),
            strength: strength,
            doseForm: doseForm,
            subtitle: _subtitle(name, tty, strength, doseForm),
            termType: tty,
          ),
        );
      }
    }
  }

  /// Approximate term candidate list: { candidate: [ { rxcui, name, ... } ] }
  static List<MedicationSummary> parseApproximateCandidates(
    Map<String, dynamic>? json,
    String query,
  ) {
    if (json == null) return [];
    final list = <MedicationSummary>[];
    final cand = json['approximateGroup']?['candidate'];
    if (cand is! List) return [];
    for (final c in cand) {
      if (c is! Map) continue;
      final rxcui = c['rxcui']?.toString();
      final name = c['name']?.toString();
      if (rxcui == null || name == null || name.isEmpty) continue;
      final strength = RxNormNameParser.extractStrength(name);
      final doseForm = RxNormNameParser.extractDoseForm(name);
      list.add(
        MedicationSummary(
          id: rxcui,
          rxcui: rxcui,
          displayName: name,
          subtitle: _subtitle(name, null, strength, doseForm),
          strength: strength,
          doseForm: doseForm,
        ),
      );
    }
    return dedupeAndSort(list, query);
  }

  static List<MedicationSummary> dedupeAndSort(
    List<MedicationSummary> items,
    String query,
  ) {
    final byRxcui = <String, MedicationSummary>{};
    for (final m in items) {
      final existing = byRxcui[m.rxcui];
      if (existing == null) {
        byRxcui[m.rxcui] = m;
        continue;
      }
      if (ttyRank(m.termType) < ttyRank(existing.termType)) {
        byRxcui[m.rxcui] = m;
      }
    }
    final q = query.toLowerCase().trim();
    final result = byRxcui.values.toList();
    result.sort((a, b) {
      final sa = _score(a.displayName, q);
      final sb = _score(b.displayName, q);
      if (sa != sb) return sb.compareTo(sa);
      return ttyRank(a.termType).compareTo(ttyRank(b.termType));
    });
    return result;
  }

  static int _score(String name, String q) {
    if (q.isEmpty) return 0;
    final n = name.toLowerCase();
    if (n == q) return 100;
    if (n.startsWith(q)) return 80;
    if (n.contains(q)) return 60;
    return 0;
  }

  static String _displayTitle(String name, String? tty) {
    return name;
  }

  static String? _maybeGeneric(String name, String? tty) {
    if (tty == 'IN' || tty == 'PIN' || tty == 'SCD' || tty == 'GPCK') {
      return name;
    }
    return null;
  }

  static String? _maybeBrand(String name, String? tty) {
    if (tty == 'BN' || tty == 'SBD' || tty == 'BPCK') return name;
    return null;
  }

  static String? _subtitle(
    String name,
    String? tty,
    String? strength,
    String? doseForm,
  ) {
    final parts = <String>[];
    final g = _maybeGeneric(name, tty);
    final b = _maybeBrand(name, tty);
    if (g != null && b != null && g != b) {
      parts.add(g);
    } else if (g != null && (tty == 'SCD' || tty == 'SBD')) {
      parts.add(g);
    }
    if (strength != null) parts.add(strength);
    if (doseForm != null) parts.add(doseForm);
    if (parts.isEmpty) {
      return strength != null || doseForm != null
          ? [if (strength != null) strength, if (doseForm != null) doseForm]
              .join(' • ')
          : null;
    }
    return parts.join(' • ');
  }
}
