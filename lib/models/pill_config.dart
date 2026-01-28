class PillConfig {
  final String name;
  final int timesPerDay;
  final List<String> doseTimes24h; // store as "HH:mm" strings for now

  const PillConfig({
    required this.name,
    required this.timesPerDay,
    required this.doseTimes24h,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'timesPerDay': timesPerDay,
        'doseTimes24h': doseTimes24h,
      };

  static PillConfig fromJson(Map<String, dynamic> json) => PillConfig(
        name: json['name'] as String,
        timesPerDay: json['timesPerDay'] as int,
        doseTimes24h: List<String>.from(json['doseTimes24h'] as List),
      );
}
