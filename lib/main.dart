import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pillchecker/data/models/dose_event.dart';
import 'package:pillchecker/data/models/dose_event_details.dart';
import 'package:pillchecker/data/services/pill_checker_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PillCheckerApp());
}

class PillCheckerApp extends StatelessWidget {
  const PillCheckerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PillChecker Backend Test',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const BackendTestScreen(),
    );
  }
}

class BackendTestScreen extends StatefulWidget {
  const BackendTestScreen({super.key});

  @override
  State<BackendTestScreen> createState() => _BackendTestScreenState();
}

class _BackendTestScreenState extends State<BackendTestScreen> {
  final PillCheckerService _service = PillCheckerService();
  final TextEditingController _rxNormController = TextEditingController(
    text: 'Paracetamol',
  );

  List<String> _lines = <String>[];
  List<DoseEventDetails> _todayEvents = <DoseEventDetails>[];
  bool _busy = false;
  int? _selectedDoseEventId;
  int? _activeMedicationId;
  bool _medicationCreated = false;
  bool _eventsGenerated = false;
  bool _todayLoaded = false;

  @override
  void dispose() {
    _rxNormController.dispose();
    super.dispose();
  }

  void _appendLog(String message) {
    final now = DateTime.now().toIso8601String();
    setState(() {
      _lines = [..._lines, '$now  $message'];
    });
  }

  bool _require(bool condition, String failMessage) {
    if (!condition) {
      _appendLog('Flow blocked: $failMessage');
      return false;
    }
    return true;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
    });
    try {
      await action();
    } catch (error) {
      _appendLog('Error: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _addSampleMedication() async {
    final medId = await _service.addMedicationWithSchedule(
      name: 'Paracetamol',
      dosage: '500mg',
      notes: 'After food',
      scheduleTimeOfDay: '08:00',
      frequencyPerDay: 3,
      startDate: DateTime.now(),
    );

    setState(() {
      _activeMedicationId = medId;
      _medicationCreated = true;
      _eventsGenerated = false;
      _todayLoaded = false;
      _selectedDoseEventId = null;
      _todayEvents = <DoseEventDetails>[];
    });
    _appendLog('Step 1 complete: medication created (medId=$medId).');
    _appendLog(
      'Schedule created and initial events stored in SQLite (offline-first).',
    );
    _appendLog('Next step: click "Generate Today Events".');
  }

  Future<void> _generateTodayEvents() async {
    if (!_require(_medicationCreated, 'Run "Add Med + Schedule" first.')) {
      return;
    }

    final before = (await _service.getTodayDoseEvents()).length;
    final generatedTotal = await _service.generateDoseEventsForNext7Days(
      medicationId: _activeMedicationId,
    );
    final after = (await _service.getTodayDoseEvents()).length;
    final generatedToday = after - before;

    setState(() {
      _eventsGenerated = true;
      _todayLoaded = false;
      _todayEvents = <DoseEventDetails>[];
      _selectedDoseEventId = null;
    });

    _appendLog('Step 2 complete: generation requested for active medication.');
    _appendLog('Dose events generated (next 7 days): $generatedTotal');
    _appendLog('Dose events generated today: $generatedToday');
    _appendLog('Today event count now: $after');
  }

  Future<void> _loadToday() async {
    if (!_require(_eventsGenerated, 'Run "Generate Today Events" first.')) {
      return;
    }

    final events = await _service.getTodayDoseEvents();
    setState(() {
      _todayEvents = events;
      _todayLoaded = true;
      if (_selectedDoseEventId != null &&
          !_todayEvents.any((e) => e.event.id == _selectedDoseEventId)) {
        _selectedDoseEventId = null;
      }
    });

    _appendLog('Step 3 complete: today events loaded (${events.length}).');
    for (final event in events) {
      _appendLog(
        'Event id=${event.event.id} | ${event.medication.name} '
        '${event.medication.dosage} | status=${event.event.status.name} '
        '| scheduled=${event.event.scheduledAt.toIso8601String()}',
      );
    }
  }

  Future<void> _confirmSelectedDose() async {
    if (!_require(
      _todayLoaded,
      'Run "Load Today Events" before confirming dose.',
    )) {
      return;
    }
    final doseEventId = _selectedDoseEventId;
    if (!_require(
      doseEventId != null,
      'Select a dose event from the list first.',
    )) {
      return;
    }

    await _service.confirmDoseStatus(
      doseEventId!,
      status: DoseStatus.taken,
      note: 'Confirmed from backend test UI',
    );
    _appendLog(
        'Step 5 action: confirmDose for selected doseEventId=$doseEventId');
    await _refreshTodayEventsAfterMutation();
  }

  Future<void> _markSelectedMissed() async {
    if (!_require(
        _todayLoaded, 'Run "Load Today Events" before marking missed.')) {
      return;
    }
    final doseEventId = _selectedDoseEventId;
    if (!_require(
      doseEventId != null,
      'Select a dose event from the list first.',
    )) {
      return;
    }

    await _service.markMissed(
      doseEventId!,
      note: 'Marked missed from backend test UI',
    );
    _appendLog(
        'Step 5 action: markMissed for selected doseEventId=$doseEventId');
    await _refreshTodayEventsAfterMutation();
  }

  Future<void> _overrideSelectedDose() async {
    if (!_require(
      _todayLoaded,
      'Run "Load Today Events" before overriding missed dose.',
    )) {
      return;
    }
    final doseEventId = _selectedDoseEventId;
    if (!_require(
      doseEventId != null,
      'Select a dose event from the list first.',
    )) {
      return;
    }

    await _service.overrideMissed(
      doseEventId!,
      note: 'Override missed from backend test UI',
    );
    _appendLog(
      'Step 5 action: overrideDose for selected doseEventId=$doseEventId',
    );
    await _refreshTodayEventsAfterMutation();
  }

  Future<void> _refreshTodayEventsAfterMutation() async {
    final updated = await _service.getTodayDoseEvents();
    setState(() {
      _todayEvents = updated;
      if (_selectedDoseEventId != null &&
          !_todayEvents
              .any((event) => event.event.id == _selectedDoseEventId)) {
        _selectedDoseEventId = null;
      }
    });

    final selectedEvent = _todayEvents
        .where((event) => event.event.id == _selectedDoseEventId)
        .firstOrNull;
    if (selectedEvent != null) {
      _appendLog(
        'Selected event updated: id=$_selectedDoseEventId '
        'status=${selectedEvent.event.status.name}',
      );
    }
  }

  Future<void> _loadHistory() async {
    if (!_require(
        _todayLoaded, 'Run "Load Today Events" before loading history.')) {
      return;
    }

    final logs = await _service.getHistoryLogs(limit: 50);
    _appendLog('Step 6 complete: adherence logs count=${logs.length}');
    for (final log in logs) {
      _appendLog(
        'History: action=${log.action.name} | event=${log.doseEventId} '
        '| med=${log.medId} | at=${log.actionAt.toIso8601String()}',
      );
    }
  }

  Future<void> _runRequiredTestingFlow() async {
    _appendLog('=== Required backend test flow started ===');
    await _addSampleMedication();
    await _generateTodayEvents();
    await _loadToday();

    final firstEventId =
        _todayEvents.isNotEmpty ? _todayEvents.first.event.id : null;
    if (firstEventId == null) {
      _appendLog('Flow stopped: no selectable dose event found for today.');
      return;
    }

    _selectDoseEvent(firstEventId);
    await _confirmSelectedDose();

    await _loadToday();
    final secondEventId =
        _findAnotherEventId(excluding: firstEventId) ?? firstEventId;
    _selectDoseEvent(secondEventId);
    await _markSelectedMissed();
    await _overrideSelectedDose();
    await _loadHistory();
    _appendLog('=== Required backend test flow completed ===');
  }

  int? _findAnotherEventId({required int excluding}) {
    for (final event in _todayEvents) {
      final id = event.event.id;
      if (id != null && id != excluding) {
        return id;
      }
    }
    return null;
  }

  Future<void> _searchRxNormByName() async {
    final query = _rxNormController.text.trim();
    if (query.isEmpty) {
      _appendLog('RxNorm test skipped: medication name is empty.');
      return;
    }

    final uri = Uri.https('rxnav.nlm.nih.gov', '/REST/drugs.json', {
      'name': query,
    });

    final client = HttpClient();
    try {
      _appendLog('RxNorm test request for "$query"...');
      final request = await client.getUrl(uri);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        _appendLog('RxNorm request failed with HTTP ${response.statusCode}.');
        return;
      }

      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final matches = _extractRxNormMatches(decoded);
      if (matches.isEmpty) {
        _appendLog('RxNorm matches: none for "$query".');
        return;
      }

      _appendLog('RxNorm matches for "$query": ${matches.length}');
      for (final match in matches.take(10)) {
        _appendLog('RxNorm => RxCUI=${match.rxcui}, Name=${match.name}');
      }
    } catch (error) {
      _appendLog('RxNorm test error: $error');
    } finally {
      client.close(force: true);
    }
  }

  List<_RxNormResult> _extractRxNormMatches(Map<String, dynamic> payload) {
    final group = payload['drugGroup'];
    if (group is! Map<String, dynamic>) {
      return <_RxNormResult>[];
    }

    final conceptGroups = group['conceptGroup'];
    if (conceptGroups is! List) {
      return <_RxNormResult>[];
    }

    final seenRxCuis = <String>{};
    final results = <_RxNormResult>[];

    for (final groupItem in conceptGroups) {
      if (groupItem is! Map) {
        continue;
      }
      final conceptProperties = groupItem['conceptProperties'];
      if (conceptProperties is! List) {
        continue;
      }

      for (final concept in conceptProperties) {
        if (concept is! Map) {
          continue;
        }
        final rxcui = '${concept['rxcui'] ?? ''}'.trim();
        final name = '${concept['name'] ?? ''}'.trim();
        if (rxcui.isEmpty || name.isEmpty || seenRxCuis.contains(rxcui)) {
          continue;
        }
        seenRxCuis.add(rxcui);
        results.add(_RxNormResult(rxcui: rxcui, name: name));
      }
    }

    return results;
  }

  void _selectDoseEvent(int? doseEventId) {
    setState(() {
      _selectedDoseEventId = doseEventId;
    });
    _appendLog('Step 4 complete: selected doseEventId=$_selectedDoseEventId');
  }

  String _eventSubtitle(DoseEventDetails event) {
    return 'id=${event.event.id} | status=${event.event.status.name} | '
        'time=${event.event.scheduledAt.hour.toString().padLeft(2, '0')}:'
        '${event.event.scheduledAt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final selectedLabel = _selectedDoseEventId?.toString() ?? 'none';

    return Scaffold(
      appBar: AppBar(title: const Text('PillChecker Backend Test UI')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy ? null : () => _run(_addSampleMedication),
                  child: const Text('Add Med + Schedule'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _run(_generateTodayEvents),
                  child: const Text('Generate Today Events'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _run(_loadToday),
                  child: const Text('Load Today Events'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _run(_confirmSelectedDose),
                  child: const Text('Confirm Taken'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _run(_markSelectedMissed),
                  child: const Text('Mark Missed'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _run(_overrideSelectedDose),
                  child: const Text('Override Missed'),
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _run(_loadHistory),
                  child: const Text('Load History'),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _run(_runRequiredTestingFlow),
                  child: const Text('Run Required Flow'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Selected doseEventId: $selectedLabel'),
            const SizedBox(height: 8),
            ExpansionTile(
              title: const Text('Other Feature: RxNorm API Test (Optional)'),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _rxNormController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'RxNorm medication name',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _busy ? null : () => _run(_searchRxNormByName),
                      child: const Text('Test RxNorm'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Required steps: Add -> Generate -> Load -> Select -> Confirm/Missed/Override -> History',
              ),
            ),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Today Dose Events (${_todayEvents.length})'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _todayEvents.length,
                itemBuilder: (context, index) {
                  final item = _todayEvents[index];
                  final eventId = item.event.id;
                  final isSelected =
                      eventId != null && eventId == _selectedDoseEventId;
                  return Card(
                    child: ListTile(
                      enabled: eventId != null,
                      onTap: eventId == null
                          ? null
                          : () => _selectDoseEvent(eventId),
                      title: Text(
                        '${item.medication.name} ${item.medication.dosage}',
                      ),
                      subtitle: Text(_eventSubtitle(item)),
                      trailing: Icon(
                        isSelected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const Align(
                alignment: Alignment.centerLeft, child: Text('Debug Log')),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _lines.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(_lines[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RxNormResult {
  const _RxNormResult({required this.rxcui, required this.name});

  final String rxcui;
  final String name;
}
