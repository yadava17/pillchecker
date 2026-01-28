import 'package:flutter/material.dart';
import '../../models/pill_config.dart';
import 'dose_times_screen.dart';

class PillConfigScreen extends StatefulWidget {
  const PillConfigScreen({super.key, required this.pillName});

  final String pillName;

  @override
  State<PillConfigScreen> createState() => _PillConfigScreenState();
}

class _PillConfigScreenState extends State<PillConfigScreen> {
  int timesPerDay = 1;
  TimeOfDay? singleDoseTime; // used only when timesPerDay == 1

  Future<void> _pickSingleTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: singleDoseTime ?? const TimeOfDay(hour: 8, minute: 0),
    );
    if (picked != null) setState(() => singleDoseTime = picked);
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    // Minimal UI for now; we can style it to match your storyboard later.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configure Pill'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.pillName,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            // Placeholder for “info”
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.black12,
              ),
              child: const Text('Placeholder: pill info (RxNorm later)'),
            ),

            const SizedBox(height: 16),

            // Times per day selector
            Row(
              children: [
                const Text('Times per day:  '),
                DropdownButton<int>(
                  value: timesPerDay,
                  items: List.generate(6, (i) => i + 1)
                      .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      timesPerDay = v;
                      // reset single time if they switch away
                      if (timesPerDay != 1) singleDoseTime = null;
                    });
                  },
                ),
              ],
            ),

            const SizedBox(height: 16),

            // If 1x/day: show single time picker on this screen
            if (timesPerDay == 1)
              Row(
                children: [
                  ElevatedButton(
                    onPressed: _pickSingleTime,
                    child: const Text('Pick dose time'),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    singleDoseTime == null
                        ? 'No time set'
                        : _formatTimeOfDay(singleDoseTime!),
                  ),
                ],
              ),

            const Spacer(),

            // Bottom action button(s)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                // RULE YOU WANTED:
                // - If timesPerDay > 1, you cannot “Add” here.
                // - You must hit Next.
                onPressed: () async {
                  if (timesPerDay == 1) {
                    if (singleDoseTime == null) return;

                    final config = PillConfig(
                      name: widget.pillName,
                      timesPerDay: 1,
                      doseTimes24h: [_formatTimeOfDay(singleDoseTime!)],
                    );

                    Navigator.pop(context, config);
                    return;
                  }

                  // timesPerDay > 1 -> go to dose screen
                  final config = await Navigator.push<PillConfig>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DoseTimesScreen(
                        pillName: widget.pillName,
                        timesPerDay: timesPerDay,
                      ),
                    ),
                  );

                  if (!mounted) return;
                  if (config != null) Navigator.pop(context, config);
                },
                child: Text(timesPerDay == 1 ? 'Add' : 'Next'),
              ),
            ),

            const SizedBox(height: 10),

            // Optional cancel
            SizedBox(
              width: double.infinity,
              height: 45,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
