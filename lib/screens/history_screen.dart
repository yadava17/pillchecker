import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/adherence_service.dart';
import '../services/medication_service.dart';
import '../models/dose_log.dart';
import '../models/medication.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final AdherenceService _adherenceService = AdherenceService();
  final MedicationService _medicationService = MedicationService();

  DateTime _selectedDate = DateTime.now();
  List<DoseLog> _doseLogs = [];
  Map<int, Medication> _medications = {};
  Map<String, dynamic>? _stats;
  int _currentStreak = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final medications = await _medicationService.getAllActiveMedications();
    final medsMap = <int, Medication>{};
    for (final med in medications) {
      medsMap[med.id!] = med;
    }

    final logs = await _adherenceService.getDoseLogsForDate(_selectedDate);

    final startOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
    final endOfMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
    final stats = await _adherenceService.getAdherenceStats(
      startDate: startOfMonth,
      endDate: endOfMonth,
    );

    final streak = await _adherenceService.getCurrentStreak();

    setState(() {
      _medications = medsMap;
      _doseLogs = logs;
      _stats = stats;
      _currentStreak = streak;
      _isLoading = false;
    });
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _selectDate,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStatsCard(),
                  const SizedBox(height: 16),
                  _buildStreakCard(),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('EEEE, MMMM d, y').format(_selectedDate),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!_isToday())
                        TextButton.icon(
                          onPressed: () {
                            setState(() => _selectedDate = DateTime.now());
                            _loadData();
                          },
                          icon: const Icon(Icons.today),
                          label: const Text('Today'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_doseLogs.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.history,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No dose logs for this date',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._doseLogs.map((log) => _buildDoseLogCard(log)),
                ],
              ),
            ),
    );
  }

  bool _isToday() {
    final now = DateTime.now();
    return _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
  }

  Widget _buildStatsCard() {
    if (_stats == null) return const SizedBox.shrink();

    final adherenceRate = _stats!['adherenceRate'] as double;
    final totalDoses = _stats!['totalDoses'] as int;
    final takenDoses = _stats!['takenDoses'] as int;
    final missedDoses = _stats!['missedDoses'] as int;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.insights, color: Colors.teal),
                SizedBox(width: 8),
                Text(
                  'This Month',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Adherence',
                  '${adherenceRate.toStringAsFixed(1)}%',
                  Colors.teal,
                ),
                _buildStatItem(
                  'Taken',
                  '$takenDoses/$totalDoses',
                  Colors.green,
                ),
                _buildStatItem(
                  'Missed',
                  '$missedDoses',
                  Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildStreakCard() {
    return Card(
      elevation: 2,
      color: Colors.teal[50],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.teal,
                borderRadius: BorderRadius.circular(25),
              ),
              child: const Icon(
                Icons.local_fire_department,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_currentStreak Day Streak',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentStreak > 0
                        ? 'Keep up the great work!'
                        : 'Start your streak today!',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoseLogCard(DoseLog log) {
    final medication = _medications[log.medicationId];
    if (medication == null) return const SizedBox.shrink();

    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (log.status) {
      case DoseStatus.taken:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Taken';
        break;
      case DoseStatus.overridden:
        statusColor = Colors.blue;
        statusIcon = Icons.check_circle;
        statusText = 'Taken (Override)';
        break;
      case DoseStatus.missed:
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'Missed';
        break;
      case DoseStatus.skipped:
        statusColor = Colors.orange;
        statusIcon = Icons.remove_circle;
        statusText = 'Skipped';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.schedule;
        statusText = 'Scheduled';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(statusIcon, color: statusColor, size: 32),
        title: Text(
          medication.name,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${medication.dosage} ${medication.strength}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 2),
            Text(
              'Scheduled: ${DateFormat('h:mm a').format(log.scheduledTime)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            if (log.takenTime != null)
              Text(
                'Taken: ${DateFormat('h:mm a').format(log.takenTime!)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            statusText,
            style: TextStyle(
              fontSize: 12,
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
