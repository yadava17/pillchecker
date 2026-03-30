# Validate PillChecker backend (SQLite)

## 1. Automated (no device)

From the `frontend/` folder:

```bash
flutter pub get
flutter analyze
flutter test test/backend_utils_test.dart
```

`backend_utils_test.dart` checks `planned_at` / `days_mask` helpers. Full SQLite is exercised on a device/emulator (see below).

## 2. Run the app (real DB)

**SQLite needs a real device or simulator** (not Chrome web).

```bash
cd frontend
flutter devices          # pick an Android emulator, iOS simulator, or device
flutter run -d <deviceId>
```

Examples:

```bash
flutter run -d android
flutter run -d ios
```

## 3. Manual QA checklist (end-to-end)

| Step | What to do | What confirms backend |
|------|------------|------------------------|
| 1 | Add a medication (name + dose times) and save | Rows in `medications` + `schedules` + generated `dose_events` |
| 2 | Home: tap **check** for the active dose | `dose_events.status` → `taken`, row in `adherence_logs` |
| 3 | Wait past grace or resume app | `autoMarkMissedPastPlanned` can mark `missed` |
| 4 | Tap **yellow warning** → Override | `taken`, `is_overridden=1`, log action `override` |
| 5 | **Settings → Adherence history** | List shows Taken / Missed / **Taken (Overridden)** |

## 4. Optional: inspect DB file (Android)

With USB debugging, after using the app:

```bash
adb shell "run-as com.example.pillchecker cat /data/data/com.example.pillchecker/app_flutter/pillchecker.db" | xxd | head
```

(Replace package name with your actual `applicationId` from `android/app/build.gradle.kts`.)

## 5. Troubleshooting

- **“Database locked” / crashes**: only one writer; avoid opening DB from isolates without a single lock.
- **Empty DB after install**: first launch runs `PrefsMigration` if prefs had pills; otherwise add a med from the UI.
- **Build fails**: run `flutter doctor -v` and fix Android SDK / Xcode / licenses.
