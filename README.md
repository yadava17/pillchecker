# PillChecker

A cross-platform mobile medication management and tracking application built with Flutter.

## Overview

PillChecker helps users safely manage and track their medications by providing reminders, confirmation-based adherence tracking, pill information lookup, and history logs. The app is offline-first and designed to be easy to use for adults, elderly users, and caregivers.

## Features

### Core Features (MVP)

1. **Medication Management**
   - Add, edit, and delete medications
   - Fields include: medication name, dosage, strength, form, times per day, days of week, with/without food
   - Support multiple medications per user

2. **Scheduling & Reminders**
   - Schedule daily or weekly reminders for each medication
   - Local notifications (no cloud required)
   - Snooze option and quiet hours

3. **Confirmation-Based Adherence**
   - "Confirm Dose" button for each scheduled dose
   - Track Taken, Missed, or Overridden doses
   - Prevent double dosing by locking confirmed doses

4. **Override Screen**
   - If a dose is marked missed but the user knows they took it, allow them to override
   - Override screen requires user confirmation
   - Mark overridden doses clearly in history

5. **History & Tracking**
   - View daily, weekly, and monthly adherence history
   - Calendar or list view
   - Show streaks and adherence percentage

6. **Pill Information Lookup**
   - Fetch medication information using RxNorm API
   - Display medication name, strength, and basic safety notes
   - Cache fetched pill data locally

## Architecture

### Offline-First Architecture
- Uses SQLite (sqflite) as the primary local database
- App works fully offline
- API calls only happen when adding new medications
- Local database is the source of truth

### Technical Stack
- **Language**: Dart
- **Framework**: Flutter
- **Local Database**: SQLite (sqflite)
- **Notifications**: flutter_local_notifications
- **API**: RxNorm (public)
- **Architecture**: Service-based (MedicationService, ScheduleService, AdherenceService)

## Project Structure

```
lib/
├── models/
│   ├── medication.dart
│   ├── schedule.dart
│   ├── dose_log.dart
│   └── pill_info.dart
├── database/
│   └── database_helper.dart
├── services/
│   ├── medication_service.dart
│   ├── schedule_service.dart
│   ├── adherence_service.dart
│   ├── notification_service.dart
│   └── rxnorm_service.dart
├── screens/
│   ├── home_screen.dart
│   ├── medications_screen.dart
│   ├── add_medication_screen.dart
│   ├── history_screen.dart
│   └── settings_screen.dart
└── main.dart
```

## Getting Started

### Prerequisites
- Flutter SDK (>= 3.0.0)
- Dart SDK
- Android Studio / Xcode for mobile development

### Installation

1. Clone the repository
```bash
git clone <repository-url>
cd pill_checker
```

2. Install dependencies
```bash
flutter pub get
```

3. Run the app
```bash
flutter run
```

## Usage

### Adding a Medication
1. Navigate to the "Medications" tab
2. Tap the "+" button
3. Fill in the medication details
4. Set reminder times and days of week
5. Tap "Add Medication"

### Confirming a Dose
1. On the "Today" screen, find your scheduled dose
2. Tap "Confirm Dose" when you take the medication
3. The dose will be marked as taken

### Overriding a Missed Dose
1. If a dose is marked as missed but you actually took it
2. Tap "I Actually Took This" button
3. Confirm the override

### Viewing History
1. Navigate to the "History" tab
2. View your adherence stats and current streak
3. Select different dates to view past logs

## UI/UX Design

- Simple, clean, accessible design
- Large buttons and readable text (elderly-friendly)
- Clear status indicators with color coding:
  - Green: Taken
  - Blue: Overridden
  - Red: Missed
  - Orange: Skipped
  - Gray: Past due

## Database Schema

### medications
- id (INTEGER PRIMARY KEY)
- name (TEXT)
- dosage (TEXT)
- strength (TEXT)
- form (TEXT)
- times_per_day (INTEGER)
- days_of_week (TEXT)
- with_food (INTEGER)
- notes (TEXT)
- created_at (TEXT)
- is_active (INTEGER)

### schedules
- id (INTEGER PRIMARY KEY)
- medication_id (INTEGER)
- time_of_day (TEXT)
- is_enabled (INTEGER)

### dose_logs
- id (INTEGER PRIMARY KEY)
- medication_id (INTEGER)
- schedule_id (INTEGER)
- scheduled_time (TEXT)
- taken_time (TEXT)
- status (TEXT)
- notes (TEXT)
- is_override (INTEGER)
- created_at (TEXT)

### pill_info
- id (INTEGER PRIMARY KEY)
- medication_name (TEXT)
- rxcui (TEXT)
- generic_name (TEXT)
- brand_name (TEXT)
- description (TEXT)
- safety_notes (TEXT)
- cached_at (TEXT)

## API Integration

The app uses the RxNorm API (https://rxnav.nlm.nih.gov/REST) to fetch medication information:
- Medication name lookup
- Generic and brand name mapping
- Basic medication properties

## Future Enhancements

- Caregiver linking with read-only access
- Cloud sync (AWS / Firebase / Supabase)
- Scan pill bottle or QR code to auto-fill medication info
- A/B testing for reminder styles
- Export history as CSV or PDF
- Multi-language support
- Dark mode

## Development Constraints

This is a student project focusing on:
- Simplicity, reliability, and correctness
- Clean, modular code with service interfaces
- Minimal cloud infrastructure for MVP
- Strong software engineering principles

## License

This project is created for academic evaluation purposes.

## Support

For issues, questions, or contributions, please open an issue in the repository.
