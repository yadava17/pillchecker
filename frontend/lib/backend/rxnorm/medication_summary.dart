/// User-facing search result row (mapped from RxNav, not raw JSON).
class MedicationSummary {
  const MedicationSummary({
    required this.id,
    required this.rxcui,
    required this.displayName,
    this.genericName,
    this.brandName,
    this.strength,
    this.doseForm,
    this.subtitle,
    this.termType,
  });

  /// Same as [rxcui] for RxNorm-backed rows.
  final String id;
  final String rxcui;
  final String displayName;
  final String? genericName;
  final String? brandName;
  final String? strength;
  final String? doseForm;
  /// Second line under title, e.g. "Acetaminophen 500 mg • tablet"
  final String? subtitle;
  /// Raw RxNav tty (internal / debugging); avoid showing in UI when possible.
  final String? termType;

  Map<String, dynamic> toJson() => {
        'id': id,
        'rxcui': rxcui,
        'displayName': displayName,
        'genericName': genericName,
        'brandName': brandName,
        'strength': strength,
        'doseForm': doseForm,
        'subtitle': subtitle,
        'termType': termType,
      };

  factory MedicationSummary.fromJson(Map<String, dynamic> m) {
    return MedicationSummary(
      id: m['id'] as String? ?? m['rxcui'] as String,
      rxcui: m['rxcui'] as String,
      displayName: m['displayName'] as String,
      genericName: m['genericName'] as String?,
      brandName: m['brandName'] as String?,
      strength: m['strength'] as String?,
      doseForm: m['doseForm'] as String?,
      subtitle: m['subtitle'] as String?,
      termType: m['termType'] as String?,
    );
  }
}
