import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/shift/data/mock_shift_repository.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/team/data/mock_team_repository.dart';
import 'package:mtm/features/team/domain/team_models.dart';

/// The scheduling rules that are easy to get subtly wrong and impossible to
/// notice by looking: week boundaries, the midnight crossing, and the two
/// bulk operations.

T _ok<T>(Result<T> r) => r.when(
      success: (data, {stale = false}) => data,
      failure: (m, code) => fail('expected success, got failure: $m ($code)'),
      offline: (_) => fail('expected success, got offline'),
    );

String? _code<T>(Result<T> r) => r.when(
      success: (_, {stale = false}) => null,
      failure: (_, code) => code,
      offline: (_) => 'offline',
    );

// Frozen at the very start of "this week" — before any seeded shift in that
// week has even started, let alone reached its one-hour attendance window —
// so every mutation test below stays inside the ordinary window regardless
// of which real day/time the suite happens to run on. Production passes no
// clock and gets the real one; see `attendance_policy_test.dart` for the
// window's own boundary tests.
MockShiftRepository _repo() => MockShiftRepository(
      MockTeamRepository(),
      clock: () => startOfWeek(DateTime.now()),
    );

const _d = 'd_dam_central';

void main() {
  group('week boundaries', () {
    test('startOfWeek lands on the Saturday on or before any date', () {
      for (int i = 0; i < 14; i++) {
        final day = DateTime(2026, 9, 1).add(Duration(days: i));
        final start = startOfWeek(day);
        expect(start.weekday, DateTime.saturday);
        expect(day.difference(start).inDays, inInclusiveRange(0, 6));
      }
    });

    test('a week read returns only that week, ordered by day then time',
        () async {
      final repo = _repo();
      final week = startOfWeek(DateTime.now());
      final shifts = _ok(await repo.listForWeek(_d, week));

      expect(shifts, isNotEmpty);
      for (final s in shifts) {
        expect(s.detachmentId, _d);
        expect(s.date.isBefore(week), isFalse);
        expect(s.date.isBefore(week.add(const Duration(days: 7))), isTrue);
      }
      for (int i = 1; i < shifts.length; i++) {
        final previous = shifts[i - 1];
        final current = shifts[i];
        expect(
          previous.date.isBefore(current.date) ||
              (previous.date == current.date &&
                  previous.startMinutes <= current.startMinutes),
          isTrue,
        );
      }
    });

    test('another detachment sees a different week', () async {
      final repo = _repo();
      final week = startOfWeek(DateTime.now());
      final mine = _ok(await repo.listForWeek(_d, week));
      final theirs = _ok(await repo.listForWeek('d_homs', week));
      expect(theirs.every((s) => s.detachmentId == 'd_homs'), isTrue);
      expect(mine.length == theirs.length, isFalse);
    });
  });

  group('the midnight crossing', () {
    test('a night shift ends on the following day', () {
      final shift = Shift(
        id: 'x',
        detachmentId: _d,
        date: DateTime(2026, 9, 5),
        centerName: 'c',
        startMinutes: 20 * 60,
        endMinutes: 2 * 60,
        needed: 4,
        attendees: const [],
      );
      expect(shift.crossesMidnight, isTrue);
      expect(shift.end.day, 6);
      expect(shift.end.difference(shift.start).inHours, 6);
    });

    test('overlap is decided on real times, across the date line', () {
      Shift at(int day, int start, int end) => Shift(
            id: '$day-$start',
            detachmentId: _d,
            date: DateTime(2026, 9, day),
            centerName: 'c',
            startMinutes: start * 60,
            endMinutes: end * 60,
            needed: 1,
            attendees: const [],
          );
      // 20:00→02:00 on the 5th runs into 00:00→06:00 on the 6th.
      expect(at(5, 20, 2).overlaps(at(6, 0, 6)), isTrue);
      // …but not into 08:00→14:00 on the 6th.
      expect(at(5, 20, 2).overlaps(at(6, 8, 14)), isFalse);
      // Back-to-back shifts do not overlap.
      expect(at(5, 8, 14).overlaps(at(5, 14, 20)), isFalse);
    });
  });

  group('assignment', () {
    test('a double booking is refused with a conflict', () async {
      final repo = _repo();
      final week = startOfWeek(DateTime.now());
      final saturday = _ok(await repo.listForWeek(_d, week))
          .where((s) => s.date == week)
          .toList();
      expect(saturday.length, greaterThanOrEqualTo(2),
          reason: 'the seed needs two shifts on one day to test a clash');

      // Two shifts on the same day; the seeded morning and evening do not
      // overlap, so build the clash explicitly.
      final first = saturday.first;
      final clashing = _ok(await repo.create(
        detachmentId: _d,
        date: week,
        centerName: 'مركز الاختبار',
        startMinutes: first.startMinutes + 60,
        endMinutes: first.endMinutes,
        needed: 3,
      ));

      final member = _ok(await repo.candidatesFor(first.id))
          .firstWhere((c) => !c.busy)
          .member;
      expect(_code(await repo.assignVolunteer(first.id, member.id)), isNull);
      expect(_code(await repo.assignVolunteer(clashing.id, member.id)),
          'conflict');
    });

    test('a member of another detachment is not found here', () async {
      final repo = _repo();
      final week = startOfWeek(DateTime.now());
      final shift = _ok(await repo.listForWeek(_d, week)).first;
      // m14 is on the Homs roster.
      expect(_code(await repo.assignVolunteer(shift.id, 'm14')), 'not_found');
    });

    test('quick fill closes the gap with free members only', () async {
      final repo = _repo();
      final week = startOfWeek(DateTime.now());
      final shift = _ok(await repo.listForWeek(_d, week))
          .firstWhere((s) => s.hasCoverageGap);

      final added = _ok(await repo.quickFill(shift.id));
      final after = _ok(await repo.byId(shift.id));

      expect(added, greaterThan(0));
      expect(after.assigned, shift.assigned + added);
      expect(after.assigned, lessThanOrEqualTo(after.needed));
      // Nobody was put on two overlapping shifts.
      final sameDay = _ok(await repo.listForWeek(_d, week))
          .where((s) => s.id != after.id && s.overlaps(after));
      for (final other in sameDay) {
        for (final a in after.attendees) {
          expect(other.attendees.any((x) => x.id == a.id), isFalse);
        }
      }
    });

    test('attendance is recorded against the assignment', () async {
      final repo = _repo();
      final week = startOfWeek(DateTime.now());
      final shift = _ok(await repo.listForWeek(_d, week))
          .firstWhere((s) => s.attendees.isNotEmpty);
      final member = shift.attendees.first;

      final updated = _ok(await repo.markAttendance(
          shift.id, member.id, AttendanceState.checkedIn));
      expect(
        updated.attendees.firstWhere((a) => a.id == member.id).attendance,
        AttendanceState.checkedIn,
      );

      final removed = _ok(await repo.unassignVolunteer(shift.id, member.id));
      expect(removed.attendees.any((a) => a.id == member.id), isFalse);
    });
  });

  group('bulk week operations', () {
    test('copying a week brings the shifts and leaves the people', () async {
      final repo = _repo();
      final thisWeek = startOfWeek(DateTime.now());
      final next = thisWeek.add(const Duration(days: 7));

      expect(_ok(await repo.listForWeek(_d, next)), isEmpty);
      final added = _ok(await repo.copyWeek(
        detachmentId: _d,
        fromWeekStart: thisWeek,
        toWeekStart: next,
      ));

      final source = _ok(await repo.listForWeek(_d, thisWeek));
      final copied = _ok(await repo.listForWeek(_d, next));
      expect(added, source.length);
      expect(copied.length, source.length);
      expect(copied.every((s) => s.attendees.isEmpty), isTrue);
      expect(
        copied.map((s) => s.startMinutes).toList(),
        source.map((s) => s.startMinutes).toList(),
      );

      // Running it twice does not duplicate the week.
      expect(
        _ok(await repo.copyWeek(
            detachmentId: _d, fromWeekStart: thisWeek, toWeekStart: next)),
        0,
      );
    });

    test('stopping a template leaves the shifts it already made', () async {
      final repo = _repo();
      final thisWeek = startOfWeek(DateTime.now());
      final before = _ok(await repo.listForWeek(_d, thisWeek)).length;
      final template = _ok(await repo.templates(_d)).first;

      _ok(await repo.stopTemplate(template.id));

      expect(_ok(await repo.templates(_d)).any((t) => t.id == template.id),
          isFalse);
      expect(_ok(await repo.listForWeek(_d, thisWeek)).length, before);
    });
  });

  group('shift lifecycle', () {
    test('picking repeat days files a template; a one-off does not', () async {
      final repo = _repo();
      final before = _ok(await repo.templates(_d)).length;
      final day = startOfWeek(DateTime.now()).add(const Duration(days: 3));

      _ok(await repo.create(
        detachmentId: _d,
        date: day,
        centerName: 'مركز الاختبار',
        startMinutes: 6 * 60,
        endMinutes: 9 * 60,
        needed: 2,
      ));
      expect(_ok(await repo.templates(_d)).length, before);

      final repeating = _ok(await repo.create(
        detachmentId: _d,
        date: day,
        centerName: 'مركز الاختبار',
        startMinutes: 9 * 60,
        endMinutes: 12 * 60,
        needed: 2,
        repeatOn: [
          day.add(const Duration(days: 1)),
          day.add(const Duration(days: 2)),
        ],
      ));
      expect(_ok(await repo.templates(_d)).length, before + 1);
      expect(repeating.templateId, isNotNull);

      // One shift per chosen day, all pointing at the new template.
      final made = _ok(await repo.shiftsForTemplate(repeating.templateId!));
      expect(made.map((s) => s.date).toSet(), {
        day,
        day.add(const Duration(days: 1)),
        day.add(const Duration(days: 2)),
      });
      expect(made.every((s) => s.templateId == repeating.templateId), isTrue);
    });

    test('a zero-length shift and an empty need are refused', () async {
      final repo = _repo();
      final day = startOfWeek(DateTime.now());
      expect(
        _code(await repo.create(
          detachmentId: _d,
          date: day,
          centerName: 'c',
          startMinutes: 480,
          endMinutes: 480,
          needed: 2,
        )),
        'validation',
      );
      expect(
        _code(await repo.create(
          detachmentId: _d,
          date: day,
          centerName: 'c',
          startMinutes: 480,
          endMinutes: 600,
          needed: 0,
        )),
        'validation',
      );
    });

    test('deleting removes the shift', () async {
      final repo = _repo();
      final week = startOfWeek(DateTime.now());
      final shift = _ok(await repo.listForWeek(_d, week)).first;
      _ok(await repo.delete(shift.id));
      expect(_code(await repo.byId(shift.id)), 'not_found');
    });
  });
}
