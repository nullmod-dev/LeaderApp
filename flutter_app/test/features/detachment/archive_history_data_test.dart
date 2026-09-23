import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/inventory/data/mock_inventory_repository.dart';
import 'package:mtm/features/inventory/domain/inventory_models.dart';
import 'package:mtm/features/search/data/search_providers.dart';
import 'package:mtm/features/shift/data/mock_shift_repository.dart';
import 'package:mtm/features/shift/data/shift_providers.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/team/data/mock_team_repository.dart';
import 'package:mtm/features/team/data/team_providers.dart';
import 'package:mtm/features/team/domain/team_models.dart';

/// What history actually holds, and what it does not.
///
/// The archive is only worth opening if the records behind it read back the
/// way they were written. These are the cases nobody can verify by looking at
/// the screen: an overnight run that ends on the following calendar day, a
/// finished shift's recorded attendance, a member deleted after the fact, and
/// the promise that operational Global Search still leaves all of it alone.

const _archived = 'd_north_arch';

T _success<T>(Result<T> result) => result.when(
      success: (data, {stale = false}) => data,
      failure: (message, code) => fail('$message ($code)'),
      offline: (_) => fail('offline'),
    );

/// Every shift the archived detachment ever ran, within the lookback window.
Future<List<Shift>> _history(MockShiftRepository repository) async {
  final now = dateOnly(DateTime.now());
  return _success(await repository.listForRange(
    _archived,
    now.subtract(scheduleLookback),
    now,
  ));
}

void main() {
  group('the archive has real shift history behind it', () {
    test('a finished detachment ran shifts, all of them in the past', () async {
      final repository = MockShiftRepository(MockTeamRepository());
      final history = await _history(repository);

      expect(history, isNotEmpty);
      final today = dateOnly(DateTime.now());
      expect(
        history.every((s) => s.date.isBefore(today)),
        isTrue,
        reason: 'an archived detachment has no shift on or after today',
      );
    });

    test('the schedule opens on the last week it actually worked', () async {
      // Without this the archive's schedule opens on the current week, which
      // a finished detachment never reached, and reads as a broken screen.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final day =
          await container.read(lastScheduledDayProvider(_archived).future);
      expect(day, isNotNull);

      final repository = MockShiftRepository(MockTeamRepository());
      final history = await _history(repository);
      final latest =
          history.map((s) => s.date).reduce((a, b) => a.isAfter(b) ? a : b);
      expect(day, latest);
      expect(startOfWeek(day!), isNot(startOfWeek(DateTime.now())));
    });

    test('a detachment that ran nothing anchors on nothing, not on a guess',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        await container.read(lastScheduledDayProvider('no_such_id').future),
        isNull,
      );
    });
  });

  group('historical attendance reads back as recorded', () {
    test('a finished shift carries settled attendance, never a pending row',
        () async {
      final repository = MockShiftRepository(MockTeamRepository());
      final history = await _history(repository);
      final attendees = [for (final s in history) ...s.attendees];

      expect(attendees, isNotEmpty);
      expect(
        attendees.every((a) => a.attendance != AttendanceState.notCheckedIn),
        isTrue,
        reason: 'a completed shift left an assignment unreviewed',
      );
      expect(
        attendees.any((a) => a.attendance == AttendanceState.checkedOut),
        isTrue,
      );
      expect(
        attendees.any((a) => a.attendance == AttendanceState.absent),
        isTrue,
      );
    });

    test('a present record keeps the stamps it was written with', () async {
      final repository = MockShiftRepository(MockTeamRepository());
      final history = await _history(repository);
      final present = [
        for (final s in history)
          for (final a in s.attendees)
            if (a.attendance == AttendanceState.checkedOut) (s, a),
      ];
      expect(present, isNotEmpty);
      for (final (shift, member) in present) {
        expect(member.checkInAt, isNotNull);
        expect(member.checkOutAt, isNotNull);
        expect(member.checkOutAt!.isAfter(member.checkInAt!), isTrue);
        // The stamps belong to that shift's own run, not to today.
        expect(member.checkInAt, shift.start);
        expect(member.checkOutAt, shift.end);
      }
    });

    test('an overnight historical shift ends on the following day', () async {
      // The one time case history must not get wrong: a 20:00–02:00 run
      // belongs to the day it began, and its checkout is stamped after
      // midnight. Recomputing it against today's clock would move it.
      final repository = MockShiftRepository(MockTeamRepository());
      final history = await _history(repository);
      final overnight = history.where((s) => s.crossesMidnight).toList();

      expect(overnight, isNotEmpty, reason: 'no overnight shift in history');
      for (final shift in overnight) {
        expect(shift.end.difference(shift.start).inMinutes, greaterThan(0));
        expect(dateOnly(shift.end),
            dateOnly(shift.date.add(const Duration(days: 1))));
        for (final member in shift.attendees) {
          if (member.checkOutAt == null) continue;
          expect(member.checkOutAt!.isAfter(member.checkInAt!), isTrue);
          expect(
            dateOnly(member.checkOutAt!),
            dateOnly(shift.date.add(const Duration(days: 1))),
          );
        }
      }
    });
  });

  group('a record that has since been deleted does not break history', () {
    test('deleting a member drops them from past shifts without failing',
        () async {
      // The honest limitation, pinned: `TeamRepository` answers with the
      // current roster and shift attendees are re-resolved against it, so a
      // deleted member leaves history rather than being preserved in it.
      // Nothing crashes, nothing else moves, and no other member is
      // substituted — but the count does fall.
      final team = MockTeamRepository();
      final repository = MockShiftRepository(team);
      final before = await _history(repository);
      final staffed = before.firstWhere((s) => s.attendees.length >= 2);
      final doomed = staffed.attendees.first;
      final survivor = staffed.attendees[1];

      _success(await team.delete(doomed.id));

      final after = await _history(repository);
      final same = after.firstWhere((s) => s.id == staffed.id);
      expect(same.attendees.map((a) => a.id), isNot(contains(doomed.id)));
      expect(same.attendees.map((a) => a.id), contains(survivor.id));
      expect(same.attendees.length, staffed.attendees.length - 1);
      // The surviving row keeps the attendance it was written with.
      final kept = same.attendees.firstWhere((a) => a.id == survivor.id);
      expect(kept.attendance, survivor.attendance);
      expect(kept.checkInAt, survivor.checkInAt);
    });
  });

  group('the archived store is a movement log, not a reconstruction', () {
    test('its items carry the movements that produced their closing stock',
        () async {
      final inventory = MockInventoryRepository();
      final items = _success(await inventory.listForDetachment(_archived));
      expect(items, isNotEmpty);

      var movementCount = 0;
      for (final item in items) {
        final movements = _success(await inventory.movementsForItem(item.id));
        movementCount += movements.length;
        for (final movement in movements) {
          expect(movement.at.isBefore(DateTime.now()), isTrue);
        }
      }
      expect(movementCount, greaterThan(0));
      // Closing stock is the stored quantity, exactly as written — nothing
      // recomputes a historical level for an earlier date.
      expect(
        items.any((i) => i.level == StockLevel.empty),
        isTrue,
        reason: 'the store should read back what it was left holding',
      );
    });
  });

  group('operational Global Search still leaves the archive alone', () {
    test('no archived detachment, and none of its records, enters the index',
        () async {
      final container = ProviderContainer(
        overrides: [
          currentUserResultProvider.overrideWith(
            (ref) async => const Success<AuthUser?>(AuthUser(
              id: 'u',
              name: 'مشرف',
              email: 'admin@mtm.org',
              role: AuthRole.mainAdmin,
              saasTenantId: kDemoSaasTenantId,
              capabilities: Capabilities(global: Cap.all),
              orgName: 'MTM',
            )),
          ),
        ],
      );
      addTearDown(container.dispose);

      final index = await container.read(searchIndexProvider.future);
      expect(
        index.results.any((r) => r.detachmentId == _archived),
        isFalse,
        reason: 'archived records reached the operational search corpus',
      );

      // And the archived detachment really does have indexable records — the
      // assertion above would pass trivially if it were empty.
      final roster = _success(
        await container
            .read(teamRepositoryProvider)
            .listForDetachment(_archived),
      );
      expect(roster, isNotEmpty);
      expect(
        index.results.any((r) => roster.any((m) => m.name == r.title)),
        isFalse,
      );
    });
  });
}
