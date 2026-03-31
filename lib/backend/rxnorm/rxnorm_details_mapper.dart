import 'medication_details.dart';
import 'rxnorm_name_parser.dart';

/// Builds [MedicationDetails] from RxNav JSON blobs (allProperties, related).
class RxNormDetailsMapper {
  RxNormDetailsMapper._();

  static MedicationDetails merge({
    required String rxcui,
    Map<String, dynamic>? allProperties,
    Map<String, dynamic>? relatedBrand,
    Map<String, dynamic>? relatedIngredient,
    String? fallbackDisplayName,
    bool isFromCache = false,
    DateTime? cachedAt,
  }) {
    final props = _flattenProperties(allProperties);
    final displayName = _firstNonEmpty([
          props['RXNAV_STR'],
          props['RxNorm Name'],
          fallbackDisplayName,
        ]) ??
        fallbackDisplayName ??
        'Medication';

    final strength = _firstNonEmpty([
      props['STRENGTH'],
      props['AVAILABLE_STRENGTH'],
      RxNormNameParser.extractStrength(displayName),
    ]);
    final doseForm = _firstNonEmpty([
      props['DF'],
      props['DDF'],
      RxNormNameParser.extractDoseForm(displayName),
    ]);

    final brands = _conceptNames(relatedBrand, 'BN');
    final ingredients = _conceptNames(relatedIngredient, 'IN');
    final ingredientList = ingredients.isNotEmpty
        ? ingredients
        : _splitIngredients(props['IN'] ?? props['INGREDIENT']);

    final synonymProps = _synonymsFromProperties(allProperties);
    final synonyms = <String>{
      ...synonymProps,
      ...brands.take(8),
    }.toList();

    final genericName = _pickGeneric(
      ttyHint: props['TTY'],
      displayName: displayName,
      ingredients: ingredientList,
    );
    final brandName = brands.isNotEmpty ? brands.first : null;

    return MedicationDetails(
      id: rxcui,
      rxcui: rxcui,
      displayName: displayName.trim(),
      genericName: genericName,
      brandName: brandName,
      strength: strength,
      doseForm: doseForm,
      ingredients: ingredientList,
      synonyms: synonyms,
      instructions: null,
      warnings: null,
      cachedAt: cachedAt,
      isFromCache: isFromCache,
    );
  }

  static String? _pickGeneric({
    String? ttyHint,
    required String displayName,
    required List<String> ingredients,
  }) {
    if (ingredients.length == 1) return ingredients.first;
    if (ingredients.length > 1) return ingredients.join(', ');
    final t = ttyHint?.toUpperCase();
    if (t == 'IN' || t == 'SCD') return displayName;
    return null;
  }

  static Map<String, String> _flattenProperties(Map<String, dynamic>? json) {
    final out = <String, String>{};
    if (json == null) return out;
    final pc = json['propConceptGroup']?['propConcept'];
    final list = pc == null
        ? const <dynamic>[]
        : (pc is List ? pc : [pc]);
    for (final p in list) {
      if (p is! Map) continue;
      final name = p['propName']?.toString();
      final value = p['propValue']?.toString();
      if (name != null &&
          value != null &&
          name.isNotEmpty &&
          value.isNotEmpty) {
        out[name] = value;
      }
    }
    return out;
  }

  static List<String> _synonymsFromProperties(Map<String, dynamic>? json) {
    final out = <String>[];
    if (json == null) return out;
    final pc = json['propConceptGroup']?['propConcept'];
    final list = pc == null
        ? const <dynamic>[]
        : (pc is List ? pc : [pc]);
    for (final p in list) {
      if (p is! Map) continue;
      final name = p['propName']?.toString() ?? '';
      final value = p['propValue']?.toString();
      if (value == null || value.isEmpty) continue;
      if (name.contains('Synonym') ||
          name == 'Tallman Synonym' ||
          name == 'Prescribable Synonym') {
        out.add(value);
      }
    }
    return out;
  }

  static List<String> _conceptNames(Map<String, dynamic>? related, String tty) {
    if (related == null) return [];
    final names = <String>{};
    final rg = related['relatedGroup'];
    if (rg is! Map) return [];
    final cg = rg['conceptGroup'];
    if (cg is! List) return [];
    for (final g in cg) {
      if (g is! Map) continue;
      final t = g['tty']?.toString();
      if (t != tty) continue;
      final props = g['conceptProperties'];
      if (props is! List) continue;
      for (final p in props) {
        if (p is Map) {
          final n = p['name']?.toString();
          if (n != null && n.isNotEmpty) names.add(n);
        }
      }
    }
    return names.toList();
  }

  static List<String> _splitIngredients(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    return raw
        .split(RegExp(r'[/;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      final t = c?.trim();
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
  }
}
