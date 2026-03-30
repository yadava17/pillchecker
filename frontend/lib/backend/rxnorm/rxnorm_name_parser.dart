/// Best-effort parsing of strength and dose form from RxNorm concept names.
class RxNormNameParser {
  /// Common patterns: "500 MG", "10 MG/ML", "81 MG", "0.5 MG"
  static final RegExp _strengthPattern = RegExp(
    r'\b\d+(?:\.\d+)?\s*(?:MG|MCG|G|ML|MEQ|UNIT|UNITS|%)\b(?:\s*/\s*(?:ML|G))?',
    caseSensitive: false,
  );

  /// Tablet, capsule, etc. when present in the name tail.
  static final RegExp _formPattern = RegExp(
    r'\b(tablet|tablets|capsule|capsules|caplet|caplets|solution|suspension|'
    r'syrup|injection|injectable|cream|ointment|gel|patch|spray|drops|'
    r'powder|lozenge|film|suppository|kit)\b',
    caseSensitive: false,
  );

  static String? extractStrength(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final m = _strengthPattern.firstMatch(name);
    return m != null ? m.group(0)?.trim() : null;
  }

  static String? extractDoseForm(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final m = _formPattern.firstMatch(name);
    if (m == null) return null;
    final raw = m.group(1)!.toLowerCase();
    if (raw.endsWith('s') && raw != 'drops') {
      return raw.substring(0, raw.length - 1); // tablet from tablets
    }
    return raw;
  }
}
