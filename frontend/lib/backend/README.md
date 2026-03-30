# Backend (offline data layer)

SQLite + medication / schedule / adherence logic for PillChecker.

| Path | Purpose |
|------|---------|
| `database/` | `AppDatabase` — schema, migrations, singleton |
| `models/` | Row/display models (`MedicationRecord`, `DoseEventRecord`, `HistoryEntry`) |
| `services/` | `MedService`, `ScheduleService`, `AdherenceService`, prefs migration + mirror |
| `utils/` | Local day / `days_mask` / `plannedAt` UTC helpers |
| `backend.dart` | Barrel export (optional `import 'package:pillchecker/backend/backend.dart';`) |

**Not here:** `lib/services/notification_service.dart` (platform notifications, still uses SharedPreferences for settings).
