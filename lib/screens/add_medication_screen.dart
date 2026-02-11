import 'package:flutter/material.dart';
import '../models/medication.dart';
import '../services/medication_service.dart';
import '../services/rxnorm_service.dart';
import '../services/notification_service.dart';

class AddMedicationScreen extends StatefulWidget {
  final Medication? medication;

  const AddMedicationScreen({super.key, this.medication});

  @override
  State<AddMedicationScreen> createState() => _AddMedicationScreenState();
}

class _AddMedicationScreenState extends State<AddMedicationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _medicationService = MedicationService();
  final _rxNormService = RxNormService();
  final _notificationService = NotificationService.instance;

  late TextEditingController _nameController;
  late TextEditingController _dosageController;
  late TextEditingController _strengthController;
  late TextEditingController _notesController;

  String _form = 'Tablet';
  int _timesPerDay = 1;
  List<int> _selectedDays = [1, 2, 3, 4, 5, 6, 7];
  bool _withFood = false;
  List<TimeOfDay> _scheduleTimes = [const TimeOfDay(hour: 9, minute: 0)];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.medication?.name ?? '');
    _dosageController = TextEditingController(text: widget.medication?.dosage ?? '');
    _strengthController = TextEditingController(text: widget.medication?.strength ?? '');
    _notesController = TextEditingController(text: widget.medication?.notes ?? '');

    if (widget.medication != null) {
      _form = widget.medication!.form;
      _timesPerDay = widget.medication!.timesPerDay;
      _selectedDays = widget.medication!.daysOfWeek;
      _withFood = widget.medication!.withFood;
      _loadExistingSchedules();
    }
  }

  Future<void> _loadExistingSchedules() async {
    final schedules =
        await _medicationService.getSchedulesForMedication(widget.medication!.id!);
    setState(() {
      _scheduleTimes = schedules
          .map((s) {
            final parts = s.timeOfDay.split(':');
            return TimeOfDay(
              hour: int.parse(parts[0]),
              minute: int.parse(parts[1]),
            );
          })
          .toList();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _strengthController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _updateScheduleTimes() {
    if (_timesPerDay < _scheduleTimes.length) {
      _scheduleTimes = _scheduleTimes.sublist(0, _timesPerDay);
    } else if (_timesPerDay > _scheduleTimes.length) {
      final lastTime = _scheduleTimes.isNotEmpty
          ? _scheduleTimes.last
          : const TimeOfDay(hour: 9, minute: 0);
      for (int i = _scheduleTimes.length; i < _timesPerDay; i++) {
        _scheduleTimes.add(TimeOfDay(
          hour: (lastTime.hour + 4 * i) % 24,
          minute: lastTime.minute,
        ));
      }
    }
  }

  Future<void> _selectTime(int index) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _scheduleTimes[index],
    );
    if (picked != null) {
      setState(() {
        _scheduleTimes[index] = picked;
      });
    }
  }

  Future<void> _saveMedication() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one day'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final medication = Medication(
        id: widget.medication?.id,
        name: _nameController.text.trim(),
        dosage: _dosageController.text.trim(),
        strength: _strengthController.text.trim(),
        form: _form,
        timesPerDay: _timesPerDay,
        daysOfWeek: _selectedDays,
        withFood: _withFood,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      final scheduleTimesStr = _scheduleTimes
          .map((t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}')
          .toList();

      if (widget.medication == null) {
        final medicationId = await _medicationService.addMedication(
          medication,
          scheduleTimesStr,
        );

        final schedules = await _medicationService.getSchedulesForMedication(medicationId);
        await _notificationService.scheduleMedicationNotifications(
          medication.copyWith(id: medicationId),
          schedules,
        );
      } else {
        await _medicationService.updateMedication(
          medication,
          scheduleTimesStr,
        );

        final schedules = await _medicationService.getSchedulesForMedication(medication.id!);
        await _notificationService.cancelMedicationNotifications(
          medication.id!,
          schedules,
        );
        await _notificationService.scheduleMedicationNotifications(
          medication,
          schedules,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving medication: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.medication == null ? 'Add Medication' : 'Edit Medication'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Medication Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.medication),
                    ),
                    style: const TextStyle(fontSize: 18),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter medication name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _dosageController,
                          decoration: const InputDecoration(
                            labelText: 'Dosage',
                            border: OutlineInputBorder(),
                            hintText: 'e.g., 1 pill',
                          ),
                          style: const TextStyle(fontSize: 18),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _strengthController,
                          decoration: const InputDecoration(
                            labelText: 'Strength',
                            border: OutlineInputBorder(),
                            hintText: 'e.g., 500mg',
                          ),
                          style: const TextStyle(fontSize: 18),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Required';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _form,
                    decoration: const InputDecoration(
                      labelText: 'Form',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontSize: 18, color: Colors.black),
                    items: ['Tablet', 'Capsule', 'Liquid', 'Injection', 'Other']
                        .map((form) => DropdownMenuItem(
                              value: form,
                              child: Text(form),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() => _form = value!);
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Schedule',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Text('Times per day:', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 16),
                      DropdownButton<int>(
                        value: _timesPerDay,
                        style: const TextStyle(fontSize: 18, color: Colors.black),
                        items: [1, 2, 3, 4, 5, 6]
                            .map((num) => DropdownMenuItem(
                                  value: num,
                                  child: Text(num.toString()),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _timesPerDay = value!;
                            _updateScheduleTimes();
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Reminder Times:', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  ...List.generate(_timesPerDay, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: () => _selectTime(index),
                        icon: const Icon(Icons.access_time),
                        label: Text(
                          _scheduleTimes[index].format(context),
                          style: const TextStyle(fontSize: 18),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 16),
                  const Text('Days of Week:', style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildDayChip('Mon', 1),
                      _buildDayChip('Tue', 2),
                      _buildDayChip('Wed', 3),
                      _buildDayChip('Thu', 4),
                      _buildDayChip('Fri', 5),
                      _buildDayChip('Sat', 6),
                      _buildDayChip('Sun', 7),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Take with food', style: TextStyle(fontSize: 16)),
                    value: _withFood,
                    onChanged: (value) {
                      setState(() => _withFood = value);
                    },
                    activeThumbColor: Colors.teal,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (Optional)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 3,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saveMedication,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                    child: Text(widget.medication == null ? 'Add Medication' : 'Update Medication'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDayChip(String label, int day) {
    final isSelected = _selectedDays.contains(day);
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 16,
          color: isSelected ? Colors.white : Colors.black,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          if (selected) {
            _selectedDays.add(day);
            _selectedDays.sort();
          } else {
            _selectedDays.remove(day);
          }
        });
      },
      selectedColor: Colors.teal,
    );
  }
}
