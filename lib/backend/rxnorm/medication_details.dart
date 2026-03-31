/// Enriched medication record for details UI + add flow.
/// RxNorm gives identity; patient education may be filled later (MedlinePlus, DailyMed).
class MedicationDetails {
  const MedicationDetails({
    required this.id,
    required this.rxcui,
    required this.displayName,
    this.genericName,
    this.brandName,
    this.strength,
    this.doseForm,
    this.ingredients = const [],
    this.synonyms = const [],
    this.instructions,
    this.warnings,
    this.source = 'RxNorm / RxNav (NLM)',
    this.cachedAt,
    this.isFromCache = false,
  });

  final String id;
  final String rxcui;
  final String displayName;
  final String? genericName;
  final String? brandName;
  final String? strength;
  final String? doseForm;
  final List<String> ingredients;
  final List<String> synonyms;

  /// Reserved for future MedlinePlus / label APIs — often null from RxNorm alone.
  final String? instructions;
  final String? warnings;
  final String source;
  final DateTime? cachedAt;
  final bool isFromCache;

  /// Paragraph for PillChecker info panel (plain language).
  String get userFriendlyInfoText {
    final buf = StringBuffer();
    buf.writeln('Source: $source');
    if (genericName != null && genericName!.trim().isNotEmpty) {
      buf.writeln('Generic: ${genericName!.trim()}');
    }
    if (brandName != null && brandName!.trim().isNotEmpty) {
      buf.writeln('Brand: ${brandName!.trim()}');
    }
    final s = strength?.trim();
    final f = doseForm?.trim();
    if ((s != null && s.isNotEmpty) || (f != null && f.isNotEmpty)) {
      buf.writeln(
        'Strength / form: ${s ?? 'Not available'} • ${f ?? 'Not available'}',
      );
    }
    if (ingredients.isNotEmpty) {
      buf.writeln('Active ingredient(s): ${ingredients.join(', ')}');
    }
    buf.writeln(
      'RxNorm ID (clinical): $rxcui — used to keep your list accurate.',
    );
    buf.writeln(
      'This screen does not replace your pharmacist or label instructions.',
    );
    return buf.toString().trim();
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'rxcui': rxcui,
    'displayName': displayName,
    'genericName': genericName,
    'brandName': brandName,
    'strength': strength,
    'doseForm': doseForm,
    'ingredients': ingredients,
    'synonyms': synonyms,
    'instructions': instructions,
    'warnings': warnings,
    'source': source,
    'cachedAt': cachedAt?.toUtc().toIso8601String(),
    'isFromCache': isFromCache,
  };

  factory MedicationDetails.fromJson(Map<String, dynamic> m) {
    return MedicationDetails(
      id: m['id'] as String? ?? m['rxcui'] as String,
      rxcui: m['rxcui'] as String,
      displayName: m['displayName'] as String,
      genericName: m['genericName'] as String?,
      brandName: m['brandName'] as String?,
      strength: m['strength'] as String?,
      doseForm: m['doseForm'] as String?,
      ingredients:
          (m['ingredients'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      synonyms:
          (m['synonyms'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      instructions: m['instructions'] as String?,
      warnings: m['warnings'] as String?,
      source: m['source'] as String? ?? 'RxNorm / RxNav (NLM)',
      cachedAt: m['cachedAt'] != null
          ? DateTime.tryParse(m['cachedAt'] as String)
          : null,
      isFromCache: m['isFromCache'] as bool? ?? false,
    );
  }
}
