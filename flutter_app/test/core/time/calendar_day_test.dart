import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/time/calendar_day.dart';

import 'dst_zones.dart';

/// The calendar-day rule, and the daylight-saving boundaries that are the
/// only place it differs from `Duration` arithmetic.
///
/// These run under whatever timezone the suite is started in. Under a zone
/// with no daylight saving (UTC, Asia/Baghdad) the DST groups find no
/// transitions and assert nothing — which is why the same file is also run
/// deliberately under DST zones:
///
///     TZ=Europe/Berlin    flutter test test/core/time/calendar_day_test.dart
///     TZ=America/New_York flutter test test/core/time/calendar_day_test.dart
///     TZ=Australia/Sydney flutter test test/core/time/calendar_day_test.dart
void main() {
  group('dateOnly', () {
    test('keeps only the calendar fields', () {
      final d = DateTime(2026, 9, 12, 23, 59, 59, 999, 999);
      expect(dateOnly(d), DateTime(2026, 9, 12));
      expect(dateOnly(dateOnly(d)), dateOnly(d));
    });
  });

  group('addDays', () {
    test('crosses month, year and leap-day ends', () {
      expect(addDays(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 1));
      expect(addDays(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
      expect(addDays(DateTime(2027, 1, 1), -1), DateTime(2026, 12, 31));
      expect(addDays(DateTime(2028, 2, 28), 1), DateTime(2028, 2, 29));
      expect(addDays(DateTime(2026, 2, 28), 1), DateTime(2026, 3, 1));
    });

    test('is exact over a long walk', () {
      var d = DateTime(2026, 1, 1);
      for (var i = 0; i < 400; i++) {
        d = addDays(d, 1);
      }
      expect(d, DateTime(2027, 2, 5));
      expect(addDays(DateTime(2026, 1, 1), 400), d);
    });

    test('a zero move is the identity on a normalized date', () {
      expect(addDays(DateTime(2026, 9, 12), 0), DateTime(2026, 9, 12));
    });
  });

  group('calendarDaysBetween', () {
    test('counts whole days in both directions', () {
      expect(
        calendarDaysBetween(DateTime(2026, 9, 12), DateTime(2026, 9, 19)),
        7,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 9, 19), DateTime(2026, 9, 12)),
        -7,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 9, 12), DateTime(2026, 9, 12)),
        0,
      );
    });

    test('ignores the time of day on either side', () {
      expect(
        calendarDaysBetween(
          DateTime(2026, 9, 12, 23, 59),
          DateTime(2026, 9, 13, 0, 1),
        ),
        1,
      );
    });

    test('round-trips with addDays for every offset in a year', () {
      final base = DateTime(2026, 1, 1);
      for (var n = -400; n <= 400; n++) {
        expect(calendarDaysBetween(base, addDays(base, n)), n,
            reason: 'offset $n');
      }
    });
  });

  group('daylight saving', () {
    final transitions = localDstTransitions();

    test('the zone under test is reported', () {
      // Not an assertion about the machine — a line in the test output that
      // says whether the groups below had anything to check.
      printOnFailure('local DST transitions found: ${transitions.length}');
      expect(transitions, isA<List<DateTime>>());
    });

    test('addDays stays at local midnight across every transition', () {
      for (final day in transitions) {
        for (final n in [-7, -1, 0, 1, 7]) {
          final moved = addDays(day, n);
          expect(moved.hour, 0, reason: '$day + $n lost midnight');
          expect(moved.minute, 0, reason: '$day + $n lost midnight');
          expect(dateOnly(moved), moved, reason: '$day + $n not normalized');
        }
      }
    }, skip: transitions.isEmpty ? 'no DST in this timezone' : null);

    test('Duration arithmetic is the thing that breaks', () {
      // The guard on the fix: on a transition day, a 24-hour `Duration` and a
      // calendar day are genuinely different answers. If this ever stops
      // being true the timezone database changed under us and the DST groups
      // above are no longer testing anything.
      final broken = [
        for (final day in transitions)
          if (day.add(const Duration(days: 1)) != addDays(day, 1)) day,
      ];
      expect(broken, isNotEmpty,
          reason: 'expected at least one transition where a 24-hour Duration '
              'does not land on the next calendar midnight');
    }, skip: transitions.isEmpty ? 'no DST in this timezone' : null);

    test('calendarDaysBetween counts seven across a transition week', () {
      for (final day in transitions) {
        final weekBefore = addDays(day, -3);
        final weekAfter = addDays(weekBefore, 7);
        expect(calendarDaysBetween(weekBefore, weekAfter), 7, reason: '$day');
        // The trap: local midnights 167 or 169 hours apart.
        expect(weekAfter.hour, 0, reason: '$day');
      }
    }, skip: transitions.isEmpty ? 'no DST in this timezone' : null);
  });
}
