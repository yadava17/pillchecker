import 'package:pillchecker/data/models/dose_event.dart';
import 'package:pillchecker/data/models/medication.dart';
import 'package:pillchecker/data/models/schedule_model.dart';

class DoseEventDetails {
  const DoseEventDetails({
    required this.event,
    required this.medication,
    required this.schedule,
  });

  final DoseEvent event;
  final Medication medication;
  final ScheduleModel schedule;
}
