import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/shift/data/mock_shift_repository.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/team/data/mock_team_repository.dart';
import 'package:mtm/features/team/domain/team_models.dart';

/// The two day-level schedule operations the shifts screen offers:
/// "copy the previous day" onto the selected one, and editing a saved
/// template's day set from the templates sheet.
///
/// Both have the same safety contract as every other repetition path in the
/// app: never stack a duplicate on a day+time that already has one, never
/// carry assignments forward, and never delete a shift that has people on it.

T _ok<T>(Result<T> r) => r.when(
      success: (data, {stale = false}) => data,
      failure: (m, code) => fail('expected success, got failure: $m ($code)'),
      offline: (_) => fail('expected success, got offline'),
    );

String _failure<T>(Result<T> r) => r.when(
      success: (_, {stale = false}) => fail('expected a failure'),
      failure: (m, __) => m,
      offline: (_) => fail('expected a failure, got offline'),
    );

MockShiftRepository _repo() => MockShiftRepository(MockTeamRepository());

/// [offset] calendar days after [from], at local midnight — DST and all.
DateTime _calendarDay(DateTime from, int offset) =>
    DateTime(from.year, from.month, from.day + offset);

const _d = 'd_dam_central';

void main() {
  // Well clear of the seeded weeks, so these tests own their days.
  //
  // Calendar arithmetic, never `Duration`: a day is not always 24 hours. Add
  // `Duration(days: 1)` across the end of daylight saving and you land at
  // 23:00 on the *previous* day, which is not a date at all — the repository
  // normalises every date through `dateOnly`, so the expectation would drift
  // away from production for whichever weeks straddle a DST change. Building
  // each day as `DateTime(y, m, d + n)` rolls the month over and always lands
  // on local midnight, exactly like `dateOnly` does.
  final base = _calendarDay(startOfWeek(DateTime.now()), 42);
  DateTime day(int offset) => _calendarDay(base, offset);

  Future<Shift> makeShift(
    MockShiftRepository repo, {
    required DateTime on,
    String center = 'مركز النسخ',
    int start = 8 * 60,
    int end = 14 * 60,
    int needed = 3,
  }) async =>
      _ok(await repo.create(
        detachmentId: _d,
        date: on,
        centerName: center,
        startMinutes: start,
        endMinutes: end,
        needed: needed,
      ));

  Future<List<Shift>> shiftsOn(MockShiftRepository repo, DateTime on) async {
    final all = _ok(await repo.listForRange(_d, on, on));
    return all;
  }

  group('copy the previous day', () {
    test('clones every shift of the source day onto the target', () async {
      final repo = _repo();
      await makeShift(repo, on: day(0), center: 'الصباحية');
      await makeShift(repo,
          on: day(0), center: 'المسائية', start: 14 * 60, end: 20 * 60);

      final added = _ok(await repo.copyDay(
        detachmentId: _d,
        fromDay: day(0),
        toDay: day(1),
      ));
      expect(added, 2);

      final copied = await shiftsOn(repo, day(1));
      expect(
          copied.map((s) => s.centerName).toList(), ['الصباحية', 'المسائية']);
      expect(copied.map((s) => s.startMinutes).toList(), [8 * 60, 14 * 60]);
    });

    test('the copies are unstaffed and independent of any template', () async {
      final repo = _repo();
      final anchor = _ok(await repo.create(
        detachmentId: _d,
        date: day(0),
        centerName: 'مركز التكرار',
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
        needed: 4,
        repeatOn: [day(3)],
      ));
      // Put someone on the source day, so "assignments do not travel" is a
      // real claim and not a vacuous one.
      final roster = _ok(await MockTeamRepository().listForDetachment(_d));
      await repo.assignVolunteer(anchor.id, roster.first.id);
      expect(_ok(await repo.byId(anchor.id)).attendees, hasLength(1));

      _ok(await repo.copyDay(
        detachmentId: _d,
        fromDay: day(0),
        toDay: day(1),
      ));

      final copy = (await shiftsOn(repo, day(1))).single;
      expect(copy.attendees, isEmpty);
      expect(copy.templateId, isNull,
          reason: 'the source template knows nothing about this day');
    });

    test('running it twice adds nothing the second time', () async {
      final repo = _repo();
      await makeShift(repo, on: day(0));

      expect(
        _ok(await repo.copyDay(
            detachmentId: _d, fromDay: day(0), toDay: day(1))),
        1,
      );
      expect(
        _ok(await repo.copyDay(
            detachmentId: _d, fromDay: day(0), toDay: day(1))),
        0,
        reason: 'the day+time already carries a shift',
      );
      expect(await shiftsOn(repo, day(1)), hasLength(1));
    });

    test('an empty previous day copies nothing, and says so with a zero',
        () async {
      final repo = _repo();
      expect(
        _ok(await repo.copyDay(
            detachmentId: _d, fromDay: day(0), toDay: day(1))),
        0,
      );
    });

    test('a day cannot be copied onto itself', () async {
      final repo = _repo();
      await makeShift(repo, on: day(0));
      expect(
        _failure(await repo.copyDay(
            detachmentId: _d, fromDay: day(0), toDay: day(0))),
        contains('نفسه'),
      );
    });

    test('the previous day may sit in the previous week', () async {
      final repo = _repo();
      // base is a Saturday — the first day of the week here — so day(-1) is
      // the last day of the week before it.
      await makeShift(repo, on: day(-1));
      expect(
        _ok(await repo.copyDay(
            detachmentId: _d, fromDay: day(-1), toDay: day(0))),
        1,
      );
      expect(await shiftsOn(repo, day(0)), hasLength(1));
    });
  });

  group('editing a template\'s days from the templates sheet', () {
    Future<ShiftTemplate> repeating(MockShiftRepository repo) async {
      final anchor = _ok(await repo.create(
        detachmentId: _d,
        date: day(0),
        centerName: 'مركز القالب',
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
        needed: 3,
        repeatOn: [day(1), day(2)],
      ));
      return _ok(await repo.templates(_d))
          .firstWhere((t) => t.id == anchor.templateId);
    }

    test('adding a day materialises a shift from the template spec', () async {
      final repo = _repo();
      final template = await repeating(repo);

      final updated = _ok(await repo.updateTemplateDates(
        template.id,
        [day(0), day(1), day(2), day(5)],
      ));
      expect(updated.dates, [day(0), day(1), day(2), day(5)]);

      final made = _ok(await repo.shiftsForTemplate(template.id));
      expect(
          made.map((s) => s.date).toList(), [day(0), day(1), day(2), day(5)]);
      final fresh = made.firstWhere((s) => s.date == day(5));
      expect(fresh.centerName, template.centerName);
      expect(fresh.startMinutes, template.startMinutes);
      expect(fresh.needed, template.needed);
      expect(fresh.attendees, isEmpty);
    });

    test('removing an empty day deletes its shift', () async {
      final repo = _repo();
      final template = await repeating(repo);

      final updated = _ok(await repo.updateTemplateDates(
        template.id,
        [day(0), day(2)],
      ));
      expect(updated.dates, [day(0), day(2)]);
      expect(
        _ok(await repo.shiftsForTemplate(template.id)).map((s) => s.date),
        [day(0), day(2)],
      );
      expect(await shiftsOn(repo, day(1)), isEmpty);
    });

    test('a staffed day is never removed — it is folded back into the set',
        () async {
      final repo = _repo();
      final template = await repeating(repo);
      final staffed = _ok(await repo.shiftsForTemplate(template.id))
          .firstWhere((s) => s.date == day(1));
      final roster = _ok(await MockTeamRepository().listForDetachment(_d));
      await repo.assignVolunteer(staffed.id, roster.first.id);

      final updated = _ok(await repo.updateTemplateDates(
        template.id,
        [day(0)],
      ));
      // day(1) survives because someone is on it; day(2) was empty and went.
      expect(updated.dates, [day(0), day(1)]);
      expect(updated.active, isTrue);
      final kept = _ok(await repo.shiftsForTemplate(template.id));
      expect(kept.map((s) => s.date), [day(0), day(1)]);
      expect(kept.firstWhere((s) => s.date == day(1)).attendees, hasLength(1));
    });

    test('collapsing to a single day stops the repeat but keeps the shift',
        () async {
      final repo = _repo();
      final template = await repeating(repo);

      final updated =
          _ok(await repo.updateTemplateDates(template.id, [day(0)]));
      expect(updated.active, isFalse);
      expect(updated.dates, [day(0)]);
      expect(_ok(await repo.shiftsForTemplate(template.id)), hasLength(1));
    });

    test('a day already occupied by another shift is not doubled up', () async {
      final repo = _repo();
      final template = await repeating(repo);
      // An independent shift at the same time on a day the template is
      // about to claim.
      await makeShift(repo, on: day(4), center: 'مركز آخر');

      _ok(await repo.updateTemplateDates(
        template.id,
        [day(0), day(1), day(2), day(4)],
      ));
      final onFour = await shiftsOn(repo, day(4));
      expect(onFour, hasLength(1));
      expect(onFour.single.centerName, 'مركز آخر');
      expect(onFour.single.templateId, isNull);
    });

    test('an unknown template id fails rather than inventing one', () async {
      final repo = _repo();
      expect(
        _failure(await repo.updateTemplateDates('tpl_nope', [day(0)])),
        contains('القالب'),
      );
    });
  });

  group('the card names a supervisor', () {
    test('Shift.manager is the assigned shift supervisor, or null', () async {
      final repo = _repo();
      final shift = await makeShift(repo, on: day(0));
      expect(_ok(await repo.byId(shift.id)).manager, isNull);

      final roster = _ok(await MockTeamRepository().listForDetachment(_d));
      final supervisor =
          roster.firstWhere((m) => m.role == TeamRole.shiftSupervisor);
      final other =
          roster.firstWhere((m) => m.role != TeamRole.shiftSupervisor);

      await repo.assignVolunteer(shift.id, other.id);
      expect(_ok(await repo.byId(shift.id)).manager, isNull,
          reason: 'a member who is not a supervisor is not the manager');

      await repo.assignVolunteer(shift.id, supervisor.id);
      expect(_ok(await repo.byId(shift.id)).manager?.id, supervisor.id);
    });
  });
}
