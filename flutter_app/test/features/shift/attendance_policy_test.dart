import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/shift/domain/attendance_policy.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';

/// The one-hour ordinary attendance edit window and the mode it resolves to.
///
/// The boundary is carried verbatim from the legacy program's own decision
/// (`medical_team/lib/features/detachments/data/attendance_lock.dart`,
/// `attendanceGracePeriod`) — shift end time plus exactly one hour — and
/// reaffirmed in `LEGACY-EXTRACTION-REPORT.md` (D-16) and `CAPABILITIES.md`.
/// These tests pin the same boundary semantics the legacy suite pins, plus
/// the two-capability mode resolution this app adds on top of it.

void main() {
  Shift dayShift({DateTime? date, int start = 8 * 60, int end = 14 * 60}) =>
      Shift(
        id: 's1',
        detachmentId: 'd1',
        date: date ?? DateTime(2026, 7, 9),
        centerName: 'c',
        startMinutes: start,
        endMinutes: end,
        needed: 1,
        attendees: const [],
      );

  group('AttendanceWindow boundary', () {
    test('open during the shift', () {
      final w = AttendanceWindow.of(dayShift(), now: DateTime(2026, 7, 9, 10));
      expect(w.isOpen, isTrue);
    });

    test('open right after the shift ends, inside the grace hour', () {
      final w =
          AttendanceWindow.of(dayShift(), now: DateTime(2026, 7, 9, 14, 30));
      expect(w.isOpen, isTrue);
    });

    test('open one minute before the grace hour elapses', () {
      final w =
          AttendanceWindow.of(dayShift(), now: DateTime(2026, 7, 9, 14, 59));
      expect(w.isOpen, isTrue);
    });

    test('closed exactly when the grace hour elapses', () {
      final w = AttendanceWindow.of(dayShift(), now: DateTime(2026, 7, 9, 15));
      expect(w.isOpen, isFalse);
    });

    test('closed well after the grace hour', () {
      final w = AttendanceWindow.of(dayShift(), now: DateTime(2026, 7, 10));
      expect(w.isOpen, isFalse);
    });

    test('lockTime is end time plus exactly one hour', () {
      final w = AttendanceWindow.of(dayShift(), now: DateTime(2026, 7, 9, 10));
      expect(w.lockTime, DateTime(2026, 7, 9, 15));
      expect(attendanceEditGracePeriod, const Duration(hours: 1));
    });

    test('remaining counts down to zero at the boundary, then stays zero', () {
      final open =
          AttendanceWindow.of(dayShift(), now: DateTime(2026, 7, 9, 14, 45));
      expect(open.remaining(DateTime(2026, 7, 9, 14, 45)),
          const Duration(minutes: 15));

      final closed =
          AttendanceWindow.of(dayShift(), now: DateTime(2026, 7, 9, 15));
      expect(closed.remaining(DateTime(2026, 7, 9, 15)), Duration.zero);
      expect(closed.remaining(DateTime(2026, 7, 10)), Duration.zero);
    });

    test(
        'a future shift is open even though the clock time already passed today',
        () {
      final w = AttendanceWindow.of(
        dayShift(date: DateTime(2026, 8, 20)),
        now: DateTime(2026, 7, 9, 23),
      );
      expect(w.isOpen, isTrue);
    });
  });

  group('AttendanceWindow overnight shifts', () {
    test('an end before the start rolls to the next day, via Shift.end', () {
      // 22:00 -> 06:00 next day, so the lock lands at 07:00 on the 10th —
      // reusing `Shift.end`'s own overnight normalization rather than
      // reimplementing it in the policy.
      final shift = dayShift(start: 22 * 60, end: 6 * 60);
      final w = AttendanceWindow.of(shift, now: DateTime(2026, 7, 9, 23));
      expect(w.lockTime, DateTime(2026, 7, 10, 7));
      expect(w.isOpen, isTrue);
    });

    test('an overnight shift is still open in the early morning', () {
      final shift = dayShift(start: 22 * 60, end: 6 * 60);
      final w = AttendanceWindow.of(shift, now: DateTime(2026, 7, 10, 6, 30));
      expect(w.isOpen, isTrue);
    });

    test('an overnight shift closes after its next-day grace hour', () {
      final shift = dayShift(start: 22 * 60, end: 6 * 60);
      final w = AttendanceWindow.of(shift, now: DateTime(2026, 7, 10, 7, 1));
      expect(w.isOpen, isFalse);
    });
  });

  group('resolveAttendanceEditMode', () {
    AttendanceWindow openWindow() => AttendanceWindow.of(
          dayShift(),
          now: DateTime(2026, 7, 9, 10),
        );
    AttendanceWindow closedWindow() => AttendanceWindow.of(
          dayShift(),
          now: DateTime(2026, 7, 10),
        );

    test('ordinary while open, with the record capability', () {
      expect(
        resolveAttendanceEditMode(
            window: openWindow(), canRecord: true, canOverride: false),
        AttendanceEditMode.ordinary,
      );
    });

    test(
        'a Main Admin uses the same ordinary path while open, not a separate one',
        () {
      expect(
        resolveAttendanceEditMode(
            window: openWindow(), canRecord: false, canOverride: true),
        AttendanceEditMode.ordinary,
      );
    });

    test('neither capability while open is still read-only', () {
      expect(
        resolveAttendanceEditMode(
            window: openWindow(), canRecord: false, canOverride: false),
        AttendanceEditMode.readOnly,
      );
    });

    test('an ordinary-only session is read-only once the window closes', () {
      expect(
        resolveAttendanceEditMode(
            window: closedWindow(), canRecord: true, canOverride: false),
        AttendanceEditMode.readOnly,
      );
    });

    test(
        'override authority continues after the window closes, but only as a correction',
        () {
      expect(
        resolveAttendanceEditMode(
            window: closedWindow(), canRecord: false, canOverride: true),
        AttendanceEditMode.correctionOnly,
      );
    });

    test(
        'a Main Admin (both capabilities) also falls to correction-only once closed',
        () {
      expect(
        resolveAttendanceEditMode(
            window: closedWindow(), canRecord: true, canOverride: true),
        AttendanceEditMode.correctionOnly,
      );
    });

    test('neither capability once closed is read-only', () {
      expect(
        resolveAttendanceEditMode(
            window: closedWindow(), canRecord: false, canOverride: false),
        AttendanceEditMode.readOnly,
      );
    });
  });

  group('injectable clock', () {
    test('the same shift resolves differently only because `now` differs', () {
      final shift = dayShift();
      final beforeLock =
          AttendanceWindow.of(shift, now: DateTime(2026, 7, 9, 14, 59));
      final afterLock =
          AttendanceWindow.of(shift, now: DateTime(2026, 7, 9, 15));
      expect(beforeLock.isOpen, isTrue);
      expect(afterLock.isOpen, isFalse);
      // No `DateTime.now()` anywhere above — every boundary in this file is
      // driven entirely by the `now` argument, which is what makes the whole
      // suite deterministic regardless of the wall clock it runs under.
    });
  });
}
