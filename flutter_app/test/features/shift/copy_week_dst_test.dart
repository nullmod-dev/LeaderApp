import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/shift/data/mock_shift_repository.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/team/data/mock_team_repository.dart';

import '../../core/time/dst_zones.dart';

/// `copyWeek` across a daylight-saving boundary.
///
/// The bug this guards: `copyWeek` mapped each source shift onto
/// `to.add(Duration(days: s.date.difference(from).inDays))`. Both halves are
/// absolute-time arithmetic on values that are calendar dates.
///
///  * `difference(...).inDays` truncates, so in a *source* week containing a
///    spring-forward day two different source days report the same offset and
///    collapse onto one target day — one day of the week is silently lost.
///  * `to.add(Duration(days: n))` in a *target* week containing a transition
///    lands at 23:00 the previous day or 01:00 the next one. That value is no
///    longer a normalized date, so `_exists` stops recognising it (copying
///    twice duplicates the week) and every `s.date == day` read in the app —
///    `listForWeek`, the day strip, the report builder — misses it.
///
/// Run under a DST zone as well as the host's:
///
///     TZ=Europe/Berlin    flutter test test/features/shift/copy_week_dst_test.dart
///     TZ=America/New_York flutter test test/features/shift/copy_week_dst_test.dart
///     TZ=Australia/Sydney flutter test test/features/shift/copy_week_dst_test.dart
T _ok<T>(Result<T> r) => r.when(
      success: (data, {stale = false}) => data,
      failure: (m, code) => fail('expected success, got failure: $m ($code)'),
      offline: (_) => fail('expected success, got offline'),
    );

/// A detachment id no fixture seeds shifts for, so a week under test holds
/// exactly what the test put in it.
const _d = 'd_dst_probe';

MockShiftRepository _repo(DateTime now) => MockShiftRepository(
      MockTeamRepository(),
      clock: () => now,
    );

/// Seeds one shift on each of the seven days of [weekStart], at a start time
/// that differs per day so a collapse is visible as a missing start time
/// rather than only as a missing row.
Future<void> _seedWeek(MockShiftRepository repo, DateTime weekStart) async {
  for (var i = 0; i < 7; i++) {
    _ok(await repo.create(
      detachmentId: _d,
      date: addDays(weekStart, i),
      centerName: 'مركز ${i + 1}',
      startMinutes: 8 * 60 + i * 10,
      endMinutes: 14 * 60 + i * 10,
      needed: 2,
    ));
  }
}

/// Asserts everything `copyWeek` promises, for a copy from [from] to [to].
Future<void> _assertCopy(
  MockShiftRepository repo, {
  required DateTime from,
  required DateTime to,
}) async {
  final source = _ok(await repo.listForWeek(_d, from));
  expect(source, hasLength(7), reason: 'source week did not seed');

  final added = _ok(await repo.copyWeek(
    detachmentId: _d,
    fromWeekStart: from,
    toWeekStart: to,
  ));
  expect(added, 7, reason: 'every source day must produce a copy');

  final copied = _ok(await repo.listForWeek(_d, to));
  expect(copied, hasLength(7), reason: 'the copied week must be readable');

  // Every copied date is a normalized calendar date — the invariant the rest
  // of the repository compares on.
  for (final shift in copied) {
    expect(shift.date, dateOnly(shift.date),
        reason: '${shift.date} is not local midnight');
  }

  // Seven distinct days: nothing collapsed.
  expect(copied.map((s) => s.date).toSet(), hasLength(7));

  // The intended calendar-day offset is preserved, day for day.
  for (var i = 0; i < 7; i++) {
    final sourceDay = source[i];
    final copiedDay = copied[i];
    expect(
      calendarDaysBetween(to, copiedDay.date),
      calendarDaysBetween(from, sourceDay.date),
      reason: 'day $i moved to the wrong offset',
    );
    expect(copiedDay.date, addDays(to, i), reason: 'day $i landed wrong');
    expect(copiedDay.startMinutes, sourceDay.startMinutes);
    expect(copiedDay.attendees, isEmpty);
  }

  // Date equality is what `_exists` uses, so a second copy must add nothing.
  expect(
    _ok(await repo.copyWeek(
      detachmentId: _d,
      fromWeekStart: from,
      toWeekStart: to,
    )),
    0,
    reason: 'a copied day must be recognised as already existing',
  );

  // And the same dates are reachable one day at a time, which is the read
  // path the day strip and the report builder use.
  for (var i = 0; i < 7; i++) {
    final day = addDays(to, i);
    final found = _ok(await repo.listForRange(_d, day, day));
    expect(found, hasLength(1), reason: 'day $i unreachable by date');
    expect(found.single.date, day);
  }
}

void main() {
  final transitions = representativeDstTransitions();

  group('copyWeek keeps calendar dates', () {
    test('an ordinary week copies day for day', () async {
      final now = DateTime(2026, 9, 12);
      final repo = _repo(now);
      final from = startOfWeek(now);
      await _seedWeek(repo, from);
      await _assertCopy(repo, from: from, to: addDays(from, 7));
    });

    test('copying across a month end keeps the offsets', () async {
      final now = DateTime(2026, 12, 26);
      final repo = _repo(now);
      final from = startOfWeek(now);
      await _seedWeek(repo, from);
      await _assertCopy(repo, from: from, to: addDays(from, 7));
    });

    test('copying backwards keeps the offsets', () async {
      final now = DateTime(2026, 9, 12);
      final repo = _repo(now);
      final from = startOfWeek(now);
      await _seedWeek(repo, from);
      await _assertCopy(repo, from: from, to: addDays(from, -7));
    });

    test('copying onto the same week is refused', () async {
      final now = DateTime(2026, 9, 12);
      final repo = _repo(now);
      final from = startOfWeek(now);
      final refused = await repo.copyWeek(
        detachmentId: _d,
        fromWeekStart: from,
        toWeekStart: addDays(from, 3),
      );
      expect(
        refused.when(
          success: (_, {stale = false}) => null,
          failure: (_, code) => code,
          offline: (_) => 'offline',
        ),
        'validation',
      );
    });
  });

  group('copyWeek across daylight saving', () {
    test('out of a week that contains a transition', () async {
      for (final transition in transitions) {
        final from = startOfWeek(transition);
        final repo = _repo(from);
        await _seedWeek(repo, from);
        await _assertCopy(repo, from: from, to: addDays(from, 7));
      }
    }, skip: transitions.isEmpty ? 'no DST in this timezone' : null);

    test('into a week that contains a transition', () async {
      for (final transition in transitions) {
        final to = startOfWeek(transition);
        final from = addDays(to, -7);
        final repo = _repo(from);
        await _seedWeek(repo, from);
        await _assertCopy(repo, from: from, to: to);
      }
    }, skip: transitions.isEmpty ? 'no DST in this timezone' : null);

    test('backwards out of a transition week', () async {
      for (final transition in transitions) {
        final from = startOfWeek(transition);
        final repo = _repo(from);
        await _seedWeek(repo, from);
        await _assertCopy(repo, from: from, to: addDays(from, -7));
      }
    }, skip: transitions.isEmpty ? 'no DST in this timezone' : null);

    test('a transition week is still seven readable days', () async {
      for (final transition in transitions) {
        final week = startOfWeek(transition);
        final repo = _repo(week);
        await _seedWeek(repo, week);
        final read = _ok(await repo.listForWeek(_d, week));
        expect(read, hasLength(7), reason: 'week of $transition');
        expect(read.map((s) => s.date).toSet(), hasLength(7));
        expect(localDayHours(transition), isNot(24),
            reason: '$transition should be a 23- or 25-hour day');
      }
    }, skip: transitions.isEmpty ? 'no DST in this timezone' : null);
  });
}
