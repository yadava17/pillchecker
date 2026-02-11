# PillChecker Architecture Documentation

## Overview

PillChecker follows a clean, layered architecture pattern with clear separation of concerns. The app is built using Flutter and follows offline-first principles.

## Architecture Layers

### 1. Data Layer

#### Models (`lib/models/`)
Pure Dart classes representing domain entities with no dependencies on Flutter framework.

- **medication.dart**: Represents a medication with all its properties
  - Fields: name, dosage, strength, form, times per day, days of week, food requirements, notes
  - Includes `toMap()` and `fromMap()` for database serialization
  - Immutable with `copyWith()` for updates

- **schedule.dart**: Represents a scheduled time for taking medication
  - Links to medication via foreign key
  - Stores time of day as string (HH:MM format)
  - Can be enabled/disabled

- **dose_log.dart**: Tracks individual dose events
  - Status enum: scheduled, taken, missed, overridden, skipped
  - Records scheduled time and actual taken time
  - Supports override functionality for user corrections
  - Tracks notes for each dose event

- **pill_info.dart**: Cached medication information from RxNorm API
  - Stores RxCUI identifier
  - Generic and brand names
  - Basic description and safety notes
  - Cache timestamp for freshness

#### Database (`lib/database/`)

- **database_helper.dart**: Singleton class managing SQLite database
  - Creates and manages database schema
  - Provides CRUD operations for all entities
  - Uses foreign key constraints for referential integrity
  - Includes indexes for performance optimization
  - Implements cascade deletes for data consistency

**Schema Design Principles:**
- Normalized database structure (3NF)
- Appropriate indexes on frequently queried columns
- Soft deletes for medications (is_active flag)
- Timestamp tracking for all entities
- Text-based storage for dates (ISO 8601 format)

### 2. Service Layer (`lib/services/`)

Business logic layer that coordinates between UI and data layers. Services are stateless and reusable.

#### MedicationService
Manages medication CRUD operations and their schedules.

**Key Responsibilities:**
- Add medication with associated schedules
- Update medication and regenerate schedules
- Retrieve medications (active or all)
- Soft delete medications
- Get medications with their schedules

**Design Pattern:** Service pattern with repository-like access to database

#### ScheduleService
Generates and manages daily medication schedules.

**Key Responsibilities:**
- Generate today's schedule based on active medications
- Filter schedules by day of week
- Combine medication, schedule, and dose log data
- Provide schedule for any date
- Get upcoming doses for reminders

**Key Class:** `ScheduledDose` - View model combining medication, schedule, and dose log status

#### AdherenceService
Tracks medication adherence and manages dose confirmations.

**Key Responsibilities:**
- Confirm doses as taken
- Mark doses as missed
- Handle override functionality for user corrections
- Skip doses with reason tracking
- Calculate adherence statistics
- Compute current streak
- Generate monthly adherence reports

**Business Rules:**
- Prevent double-dosing by checking existing logs
- Allow overrides only for missed doses
- Track override status separately
- Calculate adherence as (taken + overridden) / total

#### NotificationService
Manages local push notifications using flutter_local_notifications.

**Key Responsibilities:**
- Initialize notification system
- Request permissions (Android 13+, iOS)
- Schedule recurring notifications
- Cancel notifications when medications are deleted
- Handle notification taps
- Generate unique notification IDs

**Implementation Details:**
- Uses timezone for accurate scheduling
- Supports exact timing with `AndroidScheduleMode.exactAllowWhileIdle`
- Implements notification channels for Android
- Notification ID formula: `(medicationId * 1000) + scheduleId`

#### RxNormService
Integrates with RxNorm API for medication information lookup.

**Key Responsibilities:**
- Search medications by name
- Get medication properties (generic name, brand name, description)
- Provide spelling suggestions
- Cache results locally to reduce API calls

**API Endpoints Used:**
- `/rxcui.json` - Get RxCUI identifier
- `/rxcui/{rxcui}/properties.json` - Get medication properties
- `/spellingsuggestions.json` - Get spelling suggestions

**Offline Strategy:**
- Check local cache first
- Fetch from API only if not cached
- Store in local database for future use
- Graceful degradation if API unavailable

### 3. Presentation Layer (`lib/screens/`)

Flutter widgets implementing the user interface.

#### HomeScreen
Main dashboard showing today's medication schedule.

**Features:**
- Lists all doses for current day
- Color-coded status indicators
- Confirm dose button
- Skip dose functionality
- Override missed doses
- Pull-to-refresh
- Empty state messaging

**User Interactions:**
- Tap "Confirm Dose" → calls AdherenceService.confirmDose()
- Tap "Skip" → calls AdherenceService.skipDose()
- Tap "I Actually Took This" → shows confirmation dialog → calls AdherenceService.overrideMissedDose()

#### MedicationsScreen
Lists all active medications with management options.

**Features:**
- Card-based medication list
- Shows key information (dosage, schedule, food requirements)
- Delete functionality with confirmation
- Navigation to add/edit screen
- Empty state with call-to-action
- Floating action button for adding medications

**Design Pattern:** List-detail navigation pattern

#### AddMedicationScreen
Form for adding or editing medications.

**Features:**
- Text inputs for name, dosage, strength
- Dropdown for form (tablet, capsule, liquid, etc.)
- Times per day selector
- Time pickers for each dose
- Day of week selector (multi-select chips)
- Food requirement toggle
- Notes field
- Form validation
- Auto-generates schedule times based on times per day

**Validation Rules:**
- Required: name, dosage, strength
- At least one day must be selected
- At least one scheduled time required

**State Management:**
- Local state with setState
- Updates schedule times dynamically when times per day changes
- Loads existing data when editing

#### HistoryScreen
Shows adherence history and statistics.

**Features:**
- Monthly adherence statistics card
- Current streak display
- Date selector for viewing specific dates
- List of dose logs for selected date
- Color-coded status indicators
- Pull-to-refresh

**Statistics Shown:**
- Adherence percentage
- Total doses
- Taken doses
- Missed doses
- Current streak (consecutive days with 100% adherence)

#### SettingsScreen
App configuration and preferences.

**Features:**
- Enable/disable notifications
- Sound and vibration settings
- Quiet hours configuration
- About app information
- Version display

**Settings Storage:** Uses SharedPreferences for persistence

### 4. Application Entry Point

#### main.dart
App initialization and navigation setup.

**Initialization Sequence:**
1. `WidgetsFlutterBinding.ensureInitialized()`
2. Initialize timezone data
3. Initialize NotificationService
4. Launch app

**Navigation Structure:**
- `MaterialApp` with custom theme
- `MainNavigationScreen` with bottom navigation bar
- `IndexedStack` for maintaining state across tab switches

**Navigation Pattern:** Tab-based navigation with 4 main sections

## Design Patterns Used

### 1. Singleton Pattern
- `DatabaseHelper.instance`
- `NotificationService.instance`

**Rationale:** Ensures single database connection and notification manager throughout app lifecycle.

### 2. Service Pattern
All business logic encapsulated in service classes, separating concerns from UI.

### 3. Repository Pattern
`DatabaseHelper` acts as repository providing data access abstraction.

### 4. Data Transfer Object (DTO)
Models serve as DTOs between database and UI layers.

### 5. Factory Pattern
Models use factory constructors (`fromMap`) for object creation from database.

## Data Flow

### Adding a Medication
```
UI (AddMedicationScreen)
  → MedicationService.addMedication()
    → DatabaseHelper.insertMedication()
    → DatabaseHelper.insertSchedule() (for each time)
  → NotificationService.scheduleMedicationNotifications()
  → Navigate back to MedicationsScreen
```

### Confirming a Dose
```
UI (HomeScreen)
  → AdherenceService.confirmDose()
    → Check for existing log
    → Create/update DoseLog with status=taken
    → DatabaseHelper.insertDoseLog() or updateDoseLog()
  → Refresh UI
  → Show snackbar confirmation
```

### Loading Today's Schedule
```
UI (HomeScreen)
  → ScheduleService.getTodaySchedule()
    → Get current date
    → DatabaseHelper.getAllMedications(activeOnly: true)
    → Filter by day of week
    → DatabaseHelper.getSchedulesForMedication() (for each)
    → DatabaseHelper.getDoseLogsForDate()
    → Combine into ScheduledDose objects
  → Display in UI
```

## Offline-First Strategy

### Core Principles
1. **Local database is source of truth**
2. **App works without internet connection**
3. **API calls are optional enhancements**
4. **Cache external data locally**

### Implementation
- SQLite database for all critical data
- Local notifications (no push notification service)
- RxNorm API used only for medication info lookup
- Cached API responses in local database
- No user authentication required
- No cloud sync in MVP

### Benefits
- Works in areas with poor connectivity
- Fast performance (no network latency)
- Privacy (data stays on device)
- No server costs
- Simple deployment

## Security Considerations

### Data Privacy
- All data stored locally on device
- No data transmitted to external servers (except optional RxNorm lookups)
- No user authentication in MVP
- Device-level security (OS encryption)

### Input Validation
- Form validation on all user inputs
- SQL injection prevention (parameterized queries)
- Type safety through Dart's type system

### Notifications
- Medication names visible in notifications (privacy trade-off for usability)
- Can be configured in settings
- Quiet hours support

## Testing Strategy

### Unit Tests
- Model serialization/deserialization
- Service business logic
- Date/time calculations
- Adherence calculations

### Integration Tests
- Database operations
- Service interactions
- Navigation flow

### UI Tests
- Screen rendering
- User interactions
- Form validation
- Error handling

## Performance Optimizations

### Database
- Indexes on frequently queried columns
- Batch operations where possible
- Connection pooling (handled by sqflite)

### UI
- `IndexedStack` for tab navigation (preserves state)
- Lazy loading of data
- Pull-to-refresh for user-initiated updates
- Efficient list rendering with `ListView.builder`

### Notifications
- Efficient notification ID generation
- Batch scheduling of notifications
- Cancellation of unnecessary notifications

## Scalability Considerations

### Current Limitations
- Single user per device
- Local storage only
- No cloud backup
- Limited to device storage capacity

### Future Enhancements
- Multi-user support with user profiles
- Cloud sync capability
- Backup and restore
- Caregiver access mode
- Export data (CSV, PDF)

## Accessibility Features

### Design for Elderly Users
- Large, high-contrast buttons
- Clear, readable fonts (18+ pt for body text)
- Simple navigation (bottom nav bar)
- Consistent layout patterns
- Helpful empty states

### Accessibility Support
- Semantic labels for screen readers
- Touch targets ≥ 44x44 pt
- Color not sole indicator of status (icons + text)
- Support for system font sizes

## Error Handling

### Strategy
- Try-catch blocks in async operations
- User-friendly error messages
- Graceful degradation
- Snackbar notifications for user feedback

### Common Error Scenarios
- Database failures → show error, retry
- API failures → use cached data
- Notification permission denied → inform user
- Invalid form input → inline validation messages

## Development Best Practices

1. **Code Organization**: Clear separation by feature and layer
2. **Naming Conventions**: Descriptive, consistent naming
3. **Documentation**: Inline comments for complex logic
4. **Error Handling**: Comprehensive try-catch blocks
5. **Type Safety**: Strong typing throughout
6. **Immutability**: Models are immutable with copyWith
7. **Single Responsibility**: Each class has one clear purpose
8. **DRY Principle**: Reusable services and widgets

## Conclusion

PillChecker's architecture prioritizes simplicity, reliability, and maintainability. The offline-first approach ensures the app works reliably regardless of network conditions, while the clean separation of concerns makes the codebase easy to understand, test, and extend. This makes it an excellent demonstration of software engineering principles in a mobile application context.
