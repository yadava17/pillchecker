# PillChecker

Offline-first Flutter MVP for medication adherence tracking using local SQLite (`sqflite`).

This project is focused on backend/data-layer validation before full frontend integration.

## What This App Proves

- Local medication management (`meds`)
- Medication schedules (`schedules`)
- Generated dose events (`dose_events`)
- Adherence tracking (`adherence_logs`)
- Status flows: `taken`, `missed`, `overrideMissed`
- Local-only persistence with no cloud backend dependency

## Tech Stack

- Flutter (Dart)
- `sqflite` for local database
- `path` for DB path handling

## Dependencies

Defined in `pubspec.yaml`:

- `sqflite`
- `path`
- `flutter_test` (dev)
- `flutter_lints` (dev)

## Project Structure

```text
lib/
  data/
    db/
      app_database.dart
    models/
      medication.dart
      schedule_model.dart
      dose_event.dart
      dose_event_details.dart
      adherence_log.dart
    repositories/
      medication_repository.dart
      schedule_repository.dart
      dose_event_repository.dart
      adherence_log_repository.dart
    services/
      pill_checker_service.dart
  main.dart
```

## Database Schema

Database file: `pillchecker.db`

Tables:

1. `meds`
- `id`
- `name`
- `dosage`
- `notes`
- `is_active`
- `created_at`
- `updated_at`

2. `schedules`
- `id`
- `med_id` (FK -> `meds.id`)
- `time_of_day` (HH:mm)
- `frequency_per_day`
- `start_date`
- `end_date`
- `created_at`
- `updated_at`

3. `dose_events`
- `id`
- `med_id` (FK -> `meds.id`)
- `schedule_id` (FK -> `schedules.id`)
- `scheduled_at`
- `status` (`pending`, `taken`, `missed`)
- `confirmed_at`
- `notes`
- `created_at`
- `updated_at`

4. `adherence_logs`
- `id`
- `dose_event_id` (FK -> `dose_events.id`)
- `med_id` (FK -> `meds.id`)
- `action` (`taken`, `missed`, `overrideMissed`)
- `action_at`
- `note`
- `created_at`

## Backend Flow (Service Story)

Main orchestration is in `PillCheckerService`:

1. `addMedicationWithSchedule(...)`
- Inserts medication
- Inserts schedule
- Immediately generates upcoming dose events

2. `generateDoseEventsForNext7Days(...)`
- Generates events for the next 7 days
- Deduplicates using unique index: `(schedule_id, scheduled_at)`

3. Dose status updates
- `confirmDoseStatus(...)`
- `markMissed(...)`
- `overrideMissed(...)`
- Every status mutation writes to `adherence_logs`

4. Read APIs
- `getTodayDoseEvents()`
- `getHistoryLogs(limit: ...)`

5. Local caching
- In-memory cache for today events and history logs
- Cache invalidated on write operations

## Test UI (`main.dart`)

The UI is intentionally simple and backend-focused.

### Required Validation Flow

Use either:

- `Run Required Flow` (one-click sequence), or
- Manual sequence:
1. `Add Med + Schedule`
2. `Generate Today Events`
3. `Load Today Events`
4. Select a `doseEventId` from list
5. `Confirm Taken` / `Mark Missed` / `Override Missed`
6. `Load History`

### Optional Feature

- `Other Feature: RxNorm API Test (Optional)`
- Logs RxCUI + drug names to debug log panel
- This is external API testing only, not core offline backend logic

## Run Instructions

From project root:

```bash
flutter pub get
flutter run -d macos
```

For Android:

```bash
flutter run -d <android-device-id>
```

## Reset Local Data (Fresh Start)

If you want a clean DB:

```bash
rm -f ~/Library/Containers/com.example.pillchecker/Data/Documents/pillchecker.db*
```

Then relaunch app.

## Troubleshooting

1. RxNorm `SocketException: Operation not permitted` on macOS
- Ensure macOS entitlements include:
  - `com.apple.security.network.client = true`
- Already configured in:
  - `macos/Runner/DebugProfile.entitlements`
  - `macos/Runner/Release.entitlements`

2. RxNorm works on debug but not Android release/profile
- Ensure `INTERNET` permission exists in:
  - `android/app/src/main/AndroidManifest.xml`

3. Buttons appear blocked in test flow
- Read debug log panel; it shows exact required next step.

## Current Scope / MVP Notes

- No Firebase / no cloud backend
- No auth/user profiles
- Single-device local persistence
- Focus is correctness of backend logic before production UI

## Suggested Next Improvements

1. Add transaction handling in service for multi-step writes.
2. Add DB migration (`onUpgrade`) strategy.
3. Add unit tests for service/repository flows.
4. Add scheduler job for auto-marking overdue doses as missed.
