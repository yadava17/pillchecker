# Backend (offline data layer)

SQLite + medication / schedule / adherence logic for PillChecker.

**Repository path (GitHub):** this app lives under `frontend/`, so the backend code is at **`frontend/lib/backend/`** — not `lib/backend` at the repo root.

| Path | Purpose |
|------|---------|
| `data/` | Bundled offline medication name suggestions for search |
| `database/` | `AppDatabase` — schema, migrations, singleton |
| `models/` | Row/display models (`MedicationRecord`, `DoseEventRecord`, `HistoryEntry`) |
| `repositories/` | RxNorm SQLite cache |
| `rxnorm/` | RxNav API client, mappers, medication details/summary |
| `services/` | `MedService`, `ScheduleService`, `AdherenceService`, RxNorm + prefs migration + mirror |
| `utils/` | Local day / `days_mask` / `plannedAt` UTC helpers |
| `backend.dart` | Barrel export (optional `import 'package:pillchecker/backend/backend.dart';`) |

**Not here:** `lib/services/notification_service.dart` (platform notifications, still uses SharedPreferences for settings).
