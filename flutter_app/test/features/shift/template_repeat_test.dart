import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/shift/data/mock_shift_repository.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/team/data/mock_team_repository.dart';

/// Day-based repetition: a template is the exact set of days a shift runs on,
/// it materialises and reconciles its own occurrences on save, it never drops
/// a day that has people on it, and it never stacks a duplicate shift.

T _ok<T>(Result<T> r) => r.when(
      success: (data, {stale = false}) => data,
      failure: (m, code) => fail('expected success, got failure: $m ($code)'),
      offline: (_) => fail('expected success, got offline'),
    );

MockShiftRepository _repo() => MockShiftRepository(MockTeamRepository());

const _d = 'd_dam_central';

void main() {
  final base = startOfWeek(DateTime.now()).add(const Duration(days: 21));
  DateTime day(int offset) => base.add(Duration(days: offset));

  group('create with repeat days', () {
    test('materialises one shift per chosen day, each tagged, deduped',
        () async {
      final repo = _repo();
      final anchor = _ok(await repo.create(
        detachmentId: _d,
        date: day(0),
        centerName: 'مركز التكرار',
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
        needed: 4,
        repeatOn: [day(1), day(2), day(0)], // day(0) duplicates the anchor
      ));
      expect(anchor.templateId, isNotNull);

      final made = _ok(await repo.shiftsForTemplate(anchor.templateId!));
      expect(made.map((s) => s.date).toList(), [day(0), day(1), day(2)]);
      expect(made.every((s) => s.templateId == anchor.templateId), isTrue);
      expect(made.every((s) => s.attendees.isEmpty), isTrue);

      final template = _ok(await repo.templates(_d))
          .firstWhere((t) => t.id == anchor.templateId);
      expect(template.dates, [day(0), day(1), day(2)]);
      expect(template.dayCount, 3);
    });

    test('a single day files no template', () async {
      final repo = _repo();
      final before = _ok(await repo.templates(_d)).length;
      final shift = _ok(await repo.create(
        detachmentId: _d,
        date: day(0),
        centerName: 'مركز مفرد',
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
        needed: 4,
      ));
      expect(shift.templateId, isNull);
      expect(_ok(await repo.templates(_d)).length, before);
    });

    test('does not stack onto a day that already has a shift at that time',
        () async {
      final repo = _repo();
      // A standalone shift already sits on day(1) at 08:00.
      _ok(await repo.create(
        detachmentId: _d,
        date: day(1),
        centerName: 'موجود',
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
        needed: 3,
      ));
      final anchor = _ok(await repo.create(
        detachmentId: _d,
        date: day(0),
        centerName: 'مركز التكرار',
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
        needed: 4,
        repeatOn: [day(1), day(2)],
      ));
      final made = _ok(await repo.shiftsForTemplate(anchor.templateId!));
      // day(1) was skipped — the pre-existing shift is not this template's.
      expect(made.map((s) => s.date).toList(), [day(0), day(2)]);
    });
  });

  group('updateRepeat reconciles', () {
    Future<(MockShiftRepository, String, String)> seeded() async {
      final repo = _repo();
      final anchor = _ok(await repo.create(
        detachmentId: _d,
        date: day(0),
        centerName: 'مركز التكرار',
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
        needed: 4,
        repeatOn: [day(1), day(2)],
      ));
      return (repo, anchor.id, anchor.templateId!);
    }

    test('adding a day materialises it; removing an empty day deletes it',
        () async {
      final (repo, anchorId, templateId) = await seeded();

      _ok(await repo.updateRepeat(anchorId, [day(0), day(2), day(5)]));

      final made = _ok(await repo.shiftsForTemplate(templateId));
      expect(made.map((s) => s.date).toList(), [day(0), day(2), day(5)]);
    });

    test('a day with people on it is never dropped', () async {
      final (repo, anchorId, templateId) = await seeded();

      // Put someone on the day(1) occurrence.
      final oneDay = _ok(await repo.shiftsForTemplate(templateId))
          .firstWhere((s) => s.date == day(1));
      final member = _ok(await repo.candidatesFor(oneDay.id))
          .firstWhere((c) => !c.busy)
          .member;
      _ok(await repo.assignVolunteer(oneDay.id, member.id));

      // Ask for a set that excludes day(1).
      final template = _ok(await repo.updateRepeat(anchorId, [day(0), day(2)]));

      final made = _ok(await repo.shiftsForTemplate(templateId));
      expect(made.any((s) => s.date == day(1)), isTrue,
          reason: 'the staffed day survives the removal');
      expect(template.dates.contains(day(1)), isTrue,
          reason: 'and is folded back into the template set');
    });

    test('collapsing to the anchor day deactivates the template', () async {
      final (repo, anchorId, templateId) = await seeded();

      _ok(await repo.updateRepeat(anchorId, [day(0)]));

      expect(_ok(await repo.templates(_d)).any((t) => t.id == templateId),
          isFalse);
      // The anchor shift is still there and still manageable.
      final anchor = _ok(await repo.byId(anchorId));
      expect(anchor.date, day(0));
    });

    test('editing an unrepeated shift into a repeat builds a template',
        () async {
      final repo = _repo();
      final shift = _ok(await repo.create(
        detachmentId: _d,
        date: day(0),
        centerName: 'مركز مفرد',
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
        needed: 4,
      ));
      expect(shift.templateId, isNull);

      final template =
          _ok(await repo.updateRepeat(shift.id, [day(0), day(1), day(2)]));
      expect(template.dates, [day(0), day(1), day(2)]);

      final anchor = _ok(await repo.byId(shift.id));
      expect(anchor.templateId, template.id);
      expect(_ok(await repo.shiftsForTemplate(template.id)).length, 3);
    });
  });
}
