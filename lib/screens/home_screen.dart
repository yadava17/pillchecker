import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/schedule_service.dart';
import '../services/adherence_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScheduleService _scheduleService = ScheduleService();
  final AdherenceService _adherenceService = AdherenceService();
  List<ScheduledDose> _todaySchedule = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTodaySchedule();
  }

  Future<void> _loadTodaySchedule() async {
    setState(() => _isLoading = true);
    final schedule = await _scheduleService.getTodaySchedule();
    setState(() {
      _todaySchedule = schedule;
      _isLoading = false;
    });
  }

  Future<void> _confirmDose(ScheduledDose dose) async {
    await _adherenceService.confirmDose(
      dose.medication.id!,
      dose.schedule.id!,
      dose.scheduledTime,
    );
    await _loadTodaySchedule();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${dose.medication.name} marked as taken'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _skipDose(ScheduledDose dose) async {
    await _adherenceService.skipDose(
      dose.medication.id!,
      dose.schedule.id!,
      dose.scheduledTime,
      'Skipped by user',
    );
    await _loadTodaySchedule();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dose skipped'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _showOverrideDialog(ScheduledDose dose) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Override Missed Dose'),
        content: const Text(
          'Are you sure you already took this medication? This will mark it as taken.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _adherenceService.overrideMissedDose(
        dose.medication.id!,
        dose.schedule.id!,
        dose.scheduledTime,
        'Overridden by user',
      );
      await _loadTodaySchedule();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dose marked as taken (override)'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTodaySchedule,
              child: _todaySchedule.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.medication_outlined,
                            size: 80,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No medications scheduled for today',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add medications to get started',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _todaySchedule.length,
                      itemBuilder: (context, index) {
                        final dose = _todaySchedule[index];
                        return _buildDoseCard(dose);
                      },
                    ),
            ),
    );
  }

  Widget _buildDoseCard(ScheduledDose dose) {
    final timeFormat = DateFormat('h:mm a');
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (dose.isTaken) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      statusText = dose.doseLog?.isOverride == true ? 'Taken (Override)' : 'Taken';
    } else if (dose.isMissed) {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
      statusText = 'Missed';
    } else if (dose.isSkipped) {
      statusColor = Colors.orange;
      statusIcon = Icons.remove_circle;
      statusText = 'Skipped';
    } else if (dose.isPast) {
      statusColor = Colors.grey;
      statusIcon = Icons.access_time;
      statusText = 'Past due';
    } else {
      statusColor = Colors.blue;
      statusIcon = Icons.schedule;
      statusText = 'Scheduled';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  statusIcon,
                  color: statusColor,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dose.medication.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${dose.medication.dosage} ${dose.medication.strength} - ${dose.medication.form}',
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
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  timeFormat.format(dose.scheduledTime),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
              ],
            ),
            if (dose.medication.withFood) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.restaurant,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Take with food',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ],
            if (!dose.isTaken && !dose.isSkipped) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _confirmDose(dose),
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm Dose'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _skipDose(dose),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ],
            if (dose.isMissed) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showOverrideDialog(dose),
                  icon: const Icon(Icons.edit),
                  label: const Text('I Actually Took This'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
