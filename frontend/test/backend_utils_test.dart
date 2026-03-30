import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pillchecker/backend/utils/local_date_time.dart';

/// Fast checks (no device DB) — run: `flutter test test/backend_utils_test.dart`
void main() {
  group('local_date_time (backend utils)', () {
    test('plannedAtUtcIsoForSlot is stable for same local instant', () {
      final day = DateTime(2025, 3, 21);
      const t = TimeOfDay(hour: 8, minute: 30);
      final a = plannedAtUtcIsoForSlot(day, t);
      final b = plannedAtUtcIsoForSlot(day, t);
      expect(a, b);
      expect(a, isNotEmpty);
    });

    test('days_mask 127 includes every weekday Sun0..Sat6', () {
      const mask = 127;
      for (var d = 0; d < 7; d++) {
        final day = DateTime(2025, 3, 16 + d); // week containing Sun 16th
        expect(dayIncludedInMask(mask, day), isTrue, reason: 'dow $d');
      }
    });

    test('parse24h round-trips common times', () {
      expect(parse24h('08:00'), const TimeOfDay(hour: 8, minute: 0));
      expect(parse24h('14:30'), const TimeOfDay(hour: 14, minute: 30));
    });
  });
}
