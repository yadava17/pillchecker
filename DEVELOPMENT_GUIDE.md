# PillChecker Development Guide

## Getting Started

### Prerequisites

1. **Flutter SDK**
   ```bash
   # Check Flutter installation
   flutter doctor
   ```
   Required version: 3.0.0 or higher

2. **Development Environment**
   - Android Studio (for Android development)
   - Xcode (for iOS development, macOS only)
   - VS Code with Flutter extension (optional)

3. **Device/Emulator**
   - Android device with USB debugging enabled, or
   - Android emulator (API level 21+), or
   - iOS device with developer certificate, or
   - iOS Simulator

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd pill_checker
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Verify setup**
   ```bash
   flutter doctor -v
   ```

4. **Run the app**
   ```bash
   # List available devices
   flutter devices

   # Run on specific device
   flutter run -d <device-id>

   # Run in debug mode (default)
   flutter run

   # Run in release mode
   flutter run --release
   ```

## Project Structure

```
pill_checker/
├── lib/
│   ├── models/              # Data models
│   ├── database/            # Database layer
│   ├── services/            # Business logic
│   ├── screens/             # UI screens
│   └── main.dart            # App entry point
├── android/                 # Android-specific code
├── ios/                     # iOS-specific code
├── pubspec.yaml             # Dependencies
└── README.md                # Project overview
```

## Development Workflow

### 1. Adding a New Feature

#### Step 1: Define the Model (if needed)
```dart
// lib/models/new_feature.dart
class NewFeature {
  final int? id;
  final String name;

  NewFeature({this.id, required this.name});

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name};
  }

  factory NewFeature.fromMap(Map<String, dynamic> map) {
    return NewFeature(
      id: map['id'],
      name: map['name'],
    );
  }
}
```

#### Step 2: Update Database Schema
```dart
// lib/database/database_helper.dart
Future<void> _createDB(Database db, int version) async {
  // Add new table
  await db.execute('''
    CREATE TABLE new_feature (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL
    )
  ''');
}
```

**Note:** For existing apps, use database migration:
```dart
Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    await db.execute('ALTER TABLE ...');
  }
}
```

#### Step 3: Create Service
```dart
// lib/services/new_feature_service.dart
class NewFeatureService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<int> addFeature(NewFeature feature) async {
    return await _db.insert('new_feature', feature.toMap());
  }
}
```

#### Step 4: Build UI Screen
```dart
// lib/screens/new_feature_screen.dart
class NewFeatureScreen extends StatefulWidget {
  @override
  State<NewFeatureScreen> createState() => _NewFeatureScreenState();
}
```

#### Step 5: Add Navigation
```dart
// lib/main.dart
// Add to navigation destinations
```

### 2. Testing

#### Running Tests
```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/models/medication_test.dart

# Run with coverage
flutter test --coverage
```

#### Writing Tests
```dart
// test/services/medication_service_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MedicationService', () {
    test('should add medication', () async {
      // Arrange
      final service = MedicationService();
      final medication = Medication(...);

      // Act
      final id = await service.addMedication(medication, []);

      // Assert
      expect(id, isPositive);
    });
  });
}
```

### 3. Debugging

#### Debug Mode
```bash
# Run with DevTools
flutter run --observatory-port=9200

# Hot reload: press 'r' in terminal
# Hot restart: press 'R' in terminal
# Quit: press 'q' in terminal
```

#### Common Issues

**Issue: Database locked**
```dart
// Solution: Ensure only one database instance
final db = DatabaseHelper.instance;
```

**Issue: Notifications not showing**
```bash
# Check permissions in Android Manifest
# Request permissions at runtime
```

**Issue: Date parsing errors**
```dart
// Use ISO 8601 format consistently
DateTime.now().toIso8601String()
DateTime.parse(isoString)
```

### 4. Building for Release

#### Android APK
```bash
# Build APK
flutter build apk --release

# Build App Bundle (for Play Store)
flutter build appbundle --release

# Output location:
# build/app/outputs/flutter-apk/app-release.apk
```

#### iOS IPA
```bash
# Build iOS app
flutter build ios --release

# Open in Xcode for signing and distribution
open ios/Runner.xcworkspace
```

### 5. Database Management

#### Viewing Database
```bash
# Using Android Studio Device File Explorer
# Location: /data/data/com.example.pill_checker/databases/pill_checker.db

# Or use adb
adb pull /data/data/com.example.pill_checker/databases/pill_checker.db
sqlite3 pill_checker.db
```

#### Database Migrations
```dart
// Increment version number
static const int _databaseVersion = 2;

// Add migration logic
Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    // Add new column
    await db.execute('ALTER TABLE medications ADD COLUMN new_field TEXT');
  }
}
```

#### Resetting Database
```dart
// For development only
await DatabaseHelper.instance.close();
await deleteDatabase(path);
```

## Code Style Guidelines

### Dart Conventions
```dart
// Classes: PascalCase
class MedicationService {}

// Variables and methods: camelCase
String medicationName;
void addMedication() {}

// Constants: lowerCamelCase or UPPER_CASE
const defaultDosage = '1 pill';
const int MAX_MEDICATIONS = 50;

// Private members: prefix with _
String _privateField;
void _privateMethod() {}
```

### Flutter Best Practices

1. **Use const constructors**
   ```dart
   const Text('Hello'); // Good
   Text('Hello');       // Less efficient
   ```

2. **Extract widgets**
   ```dart
   // Good: Reusable, testable
   Widget _buildCard() => Card(...);

   // Avoid: Deeply nested widgets
   ```

3. **Null safety**
   ```dart
   String? nullableString;
   String nonNullableString = nullableString ?? 'default';
   ```

4. **Async/await**
   ```dart
   Future<void> loadData() async {
     try {
       final data = await service.getData();
       setState(() => _data = data);
     } catch (e) {
       // Handle error
     }
   }
   ```

## Performance Tips

### 1. ListView Optimization
```dart
// Use ListView.builder for large lists
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, index) {
    return ItemWidget(items[index]);
  },
)
```

### 2. Image Optimization
```dart
// Use cached_network_image for network images
// Use Image.asset for local images
// Specify width/height to avoid layout shifts
```

### 3. State Management
```dart
// Use setState for local state
// Consider Provider/Riverpod for complex state
```

### 4. Database Queries
```dart
// Use indexes for frequently queried columns
// Limit query results when possible
// Use batch operations for multiple inserts
```

## Troubleshooting

### Build Errors

**Gradle build failed**
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter run
```

**Pod install failed (iOS)**
```bash
cd ios
pod deintegrate
pod install
cd ..
flutter run
```

### Runtime Errors

**MissingPluginException**
```bash
# Hot restart the app
# Or rebuild completely
flutter clean
flutter run
```

**setState called after dispose**
```dart
// Check if mounted before setState
if (mounted) {
  setState(() {});
}
```

## API Integration

### RxNorm API Usage

**Base URL:** `https://rxnav.nlm.nih.gov/REST`

**No API key required**

**Example Request:**
```dart
final url = Uri.parse(
  'https://rxnav.nlm.nih.gov/REST/rxcui.json?name=aspirin'
);
final response = await http.get(url);
```

**Rate Limiting:** No explicit limit, but be respectful

**Error Handling:**
```dart
try {
  final response = await http.get(url);
  if (response.statusCode == 200) {
    // Success
  } else {
    // Handle HTTP error
  }
} catch (e) {
  // Handle network error
  // Fall back to cached data
}
```

## Deployment

### Android

1. **Generate signing key**
   ```bash
   keytool -genkey -v -keystore ~/key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias key
   ```

2. **Configure signing in android/app/build.gradle**
   ```gradle
   signingConfigs {
       release {
           keyAlias 'key'
           keyPassword 'password'
           storeFile file('../key.jks')
           storePassword 'password'
       }
   }
   ```

3. **Build release APK**
   ```bash
   flutter build apk --release
   ```

### iOS

1. **Configure signing in Xcode**
2. **Build for release**
   ```bash
   flutter build ios --release
   ```
3. **Archive and upload via Xcode**

## Resources

### Official Documentation
- [Flutter Documentation](https://flutter.dev/docs)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)
- [sqflite Package](https://pub.dev/packages/sqflite)
- [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)

### Useful Tools
- [Flutter DevTools](https://flutter.dev/docs/development/tools/devtools/overview)
- [Dart Analyzer](https://dart.dev/tools/dart-analyze)
- [VS Code Flutter Extension](https://marketplace.visualstudio.com/items?itemName=Dart-Code.flutter)

### Community
- [Flutter Community on Reddit](https://www.reddit.com/r/FlutterDev/)
- [Flutter Discord](https://discord.gg/flutter)
- [Stack Overflow - Flutter](https://stackoverflow.com/questions/tagged/flutter)

## Contributing

### Pull Request Process
1. Fork the repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

### Code Review Checklist
- [ ] Code follows style guidelines
- [ ] Tests added for new features
- [ ] Documentation updated
- [ ] No breaking changes
- [ ] App builds without errors
- [ ] Tested on both Android and iOS

## License

This project is for academic purposes.
