const String kDemoPillSecretSearch = 'Presentation demo pill';

const String kDemoPillName = 'Demo Pill';

const String kDemoPillOldName = 'PillChecker Demo Pill';

const String kDemoPillInfo =
    'Presentation-only demo pill. This hidden pill is used to demonstrate '
    'compressed reminder timing and two-dose adherence flow during a live demo.';

bool isDemoPillName(String name) {
  final n = name.trim().toLowerCase();
  return n == kDemoPillName.toLowerCase() ||
      n == kDemoPillOldName.toLowerCase();
}
