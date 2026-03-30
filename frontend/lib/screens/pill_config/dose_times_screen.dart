import 'package:flutter/material.dart';
import '../../models/pill_config.dart';

class DoseTimesScreen extends StatefulWidget {
  const DoseTimesScreen({
    super.key,
    required this.pillName,
    required this.timesPerDay,
  });

  final String pillName;
  final int timesPerDay;

  @override
  State<DoseTimesScreen> createState() => _DoseTimesScreenState();
}

class _DoseTimesScreenState extends State<DoseTimesScreen> {
  int _newNotifId() =>
      DateTime.now().microsecondsSinceEpoch.remainder(2000000000);
  late List<TimeOfDay?> times; // one per dose

  @override
  void initState() {
    super.initState();
    times = List<TimeOfDay?>.filled(widget.timesPerDay, null);
  }

  String _format(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Future<void> _pickTime(int i) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: times[i] ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) setState(() => times[i] = picked);
  }

  bool get _anySet => times.any((t) => t != null);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dose Times')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.pillName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),

            Expanded(
              child: ListView.separated(
                itemCount: widget.timesPerDay,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final t = times[i];
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    tileColor: Colors.black12,
                    title: Text('Dose ${i + 1}'),
                    subtitle: Text(t == null ? 'No time set' : _format(t)),
                    trailing: t == null
                        ? const Icon(Icons.schedule)
                        : IconButton(
                            tooltip: 'Skip this dose',
                            icon: const Icon(Icons.cancel),
                            onPressed: () => setState(() => times[i] = null),
                          ),
                    onTap: () => _pickTime(i),
                    onLongPress: () {
                      // Clear this slot to treat it as skipped.
                      setState(() => times[i] = null);
                    },
                  );
                },
              ),
            ),

            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _anySet
                    ? () {
                        final enabled = <TimeOfDay>[
                          for (final t in times)
                            if (t != null) t,
                        ];

                        if (enabled.isEmpty) return;

                        final config = PillConfig(
                          name: widget.pillName,
                          timesPerDay: enabled.length,
                          doseTimes24h: enabled.map(_format).toList(),
                        );
                        Navigator.pop(context, config);
                      }
                    : null,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
