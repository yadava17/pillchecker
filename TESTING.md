# PillChecker Testing Guide

## Testing Strategy

PillChecker uses a multi-layered testing approach to ensure reliability and correctness:

1. **Unit Tests** - Test individual functions and classes
2. **Widget Tests** - Test UI components in isolation
3. **Integration Tests** - Test complete user workflows

## Running Tests

### All Tests
```bash
flutter test
```

### Specific Test File
```bash
flutter test test/models/medication_test.dart
```

### With Coverage
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

### Watch Mode
```bash
flutter test --watch
```

## Unit Tests

### Testing Models

```dart
// test/models/medication_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pill_checker/models/medication.dart';

void main() {
  group('Medication Model', () {
    test('should create medication from map', () {
      final map = {
        'id': 1,
        'name': 'Aspirin',
        'dosage': '1 pill',
        'strength': '500mg',
        'form': 'Tablet',
        'times_per_day': 2,
        'days_of_week': '1,2,3,4,5',
        'with_food': 1,
        'notes': 'Take with water',
        'created_at': '2024-01-01T00:00:00.000',
        'is_active': 1,
      };

      final medication = Medication.fromMap(map);

      expect(medication.id, 1);
      expect(medication.name, 'Aspirin');
      expect(medication.dosage, '1 pill');
      expect(medication.daysOfWeek, [1, 2, 3, 4, 5]);
      expect(medication.withFood, true);
    });

    test('should convert medication to map', () {
      final medication = Medication(
        id: 1,
        name: 'Aspirin',
        dosage: '1 pill',
        strength: '500mg',
        form: 'Tablet',
        timesPerDay: 2,
        daysOfWeek: [1, 2, 3, 4, 5],
        withFood: true,
      );

      final map = medication.toMap();

      expect(map['name'], 'Aspirin');
      expect(map['days_of_week'], '1,2,3,4,5');
      expect(map['with_food'], 1);
    });

    test('copyWith should create new instance with updated values', () {
      final original = Medication(
        name: 'Aspirin',
        dosage: '1 pill',
        strength: '500mg',
        form: 'Tablet',
        timesPerDay: 2,
        daysOfWeek: [1, 2, 3, 4, 5],
      );

      final updated = original.copyWith(dosage: '2 pills');

      expect(updated.dosage, '2 pills');
      expect(updated.name, 'Aspirin');
      expect(original.dosage, '1 pill');
    });
  });
}
```

### Testing Services

```dart
// test/services/adherence_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pill_checker/services/adherence_service.dart';
import 'package:pill_checker/models/dose_log.dart';

void main() {
  group('AdherenceService', () {
    late AdherenceService service;

    setUp(() {
      service = AdherenceService();
    });

    test('should confirm dose', () async {
      final now = DateTime.now();

      await service.confirmDose(1, 1, now);

      final logs = await service.getDoseLogsForDate(now);
      expect(logs.length, 1);
      expect(logs.first.status, DoseStatus.taken);
    });

    test('should mark dose as missed', () async {
      final now = DateTime.now();

      await service.markDoseMissed(1, 1, now);

      final logs = await service.getDoseLogsForDate(now);
      expect(logs.first.status, DoseStatus.missed);
    });

    test('should override missed dose', () async {
      final now = DateTime.now();

      await service.markDoseMissed(1, 1, now);
      await service.overrideMissedDose(1, 1, now, 'User correction');

      final logs = await service.getDoseLogsForDate(now);
      expect(logs.first.status, DoseStatus.overridden);
      expect(logs.first.isOverride, true);
    });

    test('should calculate adherence rate', () async {
      final startDate = DateTime(2024, 1, 1);
      final endDate = DateTime(2024, 1, 31);

      // Add some test data
      await service.confirmDose(1, 1, DateTime(2024, 1, 1, 9, 0));
      await service.confirmDose(1, 1, DateTime(2024, 1, 2, 9, 0));
      await service.markDoseMissed(1, 1, DateTime(2024, 1, 3, 9, 0));

      final stats = await service.getAdherenceStats(
        startDate: startDate,
        endDate: endDate,
      );

      expect(stats['totalDoses'], 3);
      expect(stats['takenDoses'], 2);
      expect(stats['adherenceRate'], closeTo(66.7, 0.1));
    });
  });
}
```

## Widget Tests

### Testing Screens

```dart
// test/screens/home_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pill_checker/screens/home_screen.dart';

void main() {
  testWidgets('HomeScreen should display empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );

    expect(find.text('No medications scheduled for today'), findsOneWidget);
  });

  testWidgets('HomeScreen should display medication cards', (tester) async {
    // Mock data setup would go here

    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );

    await tester.pump();

    expect(find.byType(Card), findsWidgets);
  });

  testWidgets('should confirm dose on button tap', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomeScreen(),
      ),
    );

    await tester.pump();

    final confirmButton = find.text('Confirm Dose');
    if (confirmButton.evaluate().isNotEmpty) {
      await tester.tap(confirmButton.first);
      await tester.pumpAndSettle();

      expect(find.text('marked as taken'), findsOneWidget);
    }
  });
}
```

### Testing Forms

```dart
// test/screens/add_medication_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pill_checker/screens/add_medication_screen.dart';

void main() {
  testWidgets('should validate required fields', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AddMedicationScreen(),
      ),
    );

    final saveButton = find.text('Add Medication');
    await tester.tap(saveButton);
    await tester.pump();

    expect(find.text('Please enter medication name'), findsOneWidget);
  });

  testWidgets('should fill form and submit', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AddMedicationScreen(),
      ),
    );

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Aspirin',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      '1 pill',
    );
    await tester.enterText(
      find.byType(TextFormField).at(2),
      '500mg',
    );

    await tester.tap(find.text('Add Medication'));
    await tester.pumpAndSettle();

    // Verify navigation or success message
  });
}
```

## Integration Tests

### Testing Complete Workflows

```dart
// integration_test/app_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pill_checker/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('end-to-end test', () {
    testWidgets('complete medication workflow', (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Navigate to Medications screen
      await tester.tap(find.text('Medications'));
      await tester.pumpAndSettle();

      // Tap add medication button
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Fill medication form
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Test Medication',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        '1 pill',
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        '100mg',
      );

      // Save medication
      await tester.tap(find.text('Add Medication'));
      await tester.pumpAndSettle();

      // Verify medication appears in list
      expect(find.text('Test Medication'), findsOneWidget);

      // Navigate to Home screen
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();

      // Verify medication appears in today's schedule
      expect(find.text('Test Medication'), findsWidgets);

      // Confirm dose
      await tester.tap(find.text('Confirm Dose').first);
      await tester.pumpAndSettle();

      // Verify confirmation
      expect(find.text('marked as taken'), findsOneWidget);
    });
  });
}
```

## Test Coverage Goals

### Minimum Coverage Targets
- **Models**: 100% (critical for data integrity)
- **Services**: 90% (core business logic)
- **Database**: 85% (data operations)
- **Screens**: 70% (UI logic)
- **Overall**: 80%

### Critical Test Areas

1. **Medication CRUD Operations**
   - Create medication with schedules
   - Update medication and schedules
   - Delete medication (soft delete)
   - Retrieve medications

2. **Adherence Tracking**
   - Confirm dose
   - Mark dose missed
   - Override missed dose
   - Skip dose
   - Calculate adherence stats

3. **Schedule Generation**
   - Generate daily schedule
   - Filter by day of week
   - Combine with dose logs
   - Handle edge cases

4. **Date/Time Handling**
   - Parse scheduled times
   - Compare dates correctly
   - Handle timezone changes
   - Calculate streaks

## Mocking

### Database Mocking

```dart
class MockDatabaseHelper implements DatabaseHelper {
  Map<int, Medication> _medications = {};
  int _nextId = 1;

  @override
  Future<int> insertMedication(Medication medication) async {
    _medications[_nextId] = medication.copyWith(id: _nextId);
    return _nextId++;
  }

  @override
  Future<Medication?> getMedication(int id) async {
    return _medications[id];
  }
}
```

### Service Mocking

```dart
class MockMedicationService implements MedicationService {
  final List<Medication> _medications = [];

  @override
  Future<int> addMedication(Medication medication, List<String> times) async {
    _medications.add(medication);
    return medication.id ?? 0;
  }
}
```

## Test Data Builders

```dart
class MedicationBuilder {
  int? id;
  String name = 'Test Med';
  String dosage = '1 pill';
  String strength = '500mg';
  String form = 'Tablet';
  int timesPerDay = 1;
  List<int> daysOfWeek = [1, 2, 3, 4, 5];
  bool withFood = false;

  MedicationBuilder withId(int id) {
    this.id = id;
    return this;
  }

  MedicationBuilder withName(String name) {
    this.name = name;
    return this;
  }

  Medication build() {
    return Medication(
      id: id,
      name: name,
      dosage: dosage,
      strength: strength,
      form: form,
      timesPerDay: timesPerDay,
      daysOfWeek: daysOfWeek,
      withFood: withFood,
    );
  }
}

// Usage
final medication = MedicationBuilder()
  .withId(1)
  .withName('Aspirin')
  .build();
```

## Continuous Integration

### GitHub Actions Example

```yaml
name: Flutter Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.10.0'
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test --coverage
      - uses: codecov/codecov-action@v2
        with:
          files: ./coverage/lcov.info
```

## Best Practices

1. **Test Naming**
   ```dart
   test('should [expected behavior] when [condition]', () {});
   ```

2. **Arrange-Act-Assert Pattern**
   ```dart
   test('example', () {
     // Arrange
     final service = MyService();

     // Act
     final result = service.doSomething();

     // Assert
     expect(result, expectedValue);
   });
   ```

3. **One Assertion per Test**
   - Focus each test on one specific behavior
   - Makes failures easier to diagnose

4. **Use Test Helpers**
   - Create helper functions for common setup
   - Use builders for test data

5. **Avoid Test Interdependence**
   - Each test should run independently
   - Use setUp() and tearDown() for isolation

6. **Test Edge Cases**
   - Empty lists
   - Null values
   - Boundary conditions
   - Error scenarios

## Debugging Tests

### Print Debugging
```dart
test('example', () {
  print('Current value: $value');
  debugPrint(widget.toString());
});
```

### Run Single Test
```bash
flutter test test/models/medication_test.dart --plain-name "should create medication"
```

### Visual Debugging
```bash
flutter test --update-goldens  # Update golden files
flutter test --verbose          # Verbose output
```

## Performance Testing

### Measure Database Operations
```dart
test('database performance', () async {
  final stopwatch = Stopwatch()..start();

  for (int i = 0; i < 1000; i++) {
    await db.insertMedication(testMedication);
  }

  stopwatch.stop();
  print('Inserted 1000 medications in ${stopwatch.elapsedMilliseconds}ms');
  expect(stopwatch.elapsedMilliseconds, lessThan(1000));
});
```

## Resources

- [Flutter Testing Documentation](https://flutter.dev/docs/testing)
- [Effective Dart: Testing](https://dart.dev/guides/language/effective-dart/testing)
- [Flutter Test Package](https://api.flutter.dev/flutter/flutter_test/flutter_test-library.html)
