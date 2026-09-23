import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/data/customer_demo_controller.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/demo/data/demo_control_plane.dart';
import 'package:mtm/features/demo/domain/demo_policy.dart';

/// The Customer Demo control plane: the policy a Super Admin administers, and
/// the session records it keeps.
///
/// These are the product rules rather than the widget, so they are asserted
/// against the plane itself — the screen is exercised in
/// `platform/platform_demo_management_test.dart`.
void main() {
  // A pinned instant. Every expiry assertion here is about a window, and a
  // window measured against `DateTime.now` is a window that changes while the
  // test runs.
  var now = DateTime.utc(2026, 9, 16, 12);

  ProviderContainer plane({List<DemoSession> seed = const []}) {
    final container = ProviderContainer(overrides: [
      clockProvider.overrideWithValue(() => now),
      demoControlPlaneSeedProvider.overrideWithValue(seed),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  const actor = DemoPolicyActor(accountId: 'sa_1', displayName: 'مسؤول المنصة');

  DemoSession sessionOf(Result<DemoSession> result) =>
      (result as Success<DemoSession>).data;

  setUp(() => now = DateTime.utc(2026, 9, 16, 12));

  group('the default policy', () {
    test('offers the trial for twenty-four hours', () {
      final policy = plane().read(demoControlPlaneProvider).policy;

      expect(policy.enabled, isTrue);
      expect(policy.defaultDuration, const Duration(hours: 24));
      expect(DemoPolicy.defaultDemoDuration, const Duration(hours: 24));
      // Nobody has administered it yet, so it claims no author.
      expect(policy.revision, 1);
      expect(policy.updatedBy, isNull);
    });

    test('is what the login side reads, rather than a second constant', () {
      final container = plane();

      expect(container.read(customerDemoPolicyProvider).available, isTrue);
      expect(
        container.read(customerDemoPolicyProvider).duration,
        const Duration(hours: 24),
      );
    });

    test('stamps a new session twenty-four hours out', () {
      final container = plane();

      final session = sessionOf(container
          .read(demoControlPlaneProvider.notifier)
          .startSession(accountId: 'acc_1'));

      expect(session.startedAt, now);
      expect(session.expiresAt, now.add(const Duration(hours: 24)));
      expect(session.status, DemoSessionStatus.active);
      expect(session.policyRevision, 1);
    });
  });

  group('only a Super Admin may administer it', () {
    test('every mutation is refused without an actor', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      final started = sessionOf(notifier.startSession(accountId: 'acc_1'));

      for (final refused in <Result<Object?>>[
        notifier.setEnabled(false),
        notifier.setDefaultDuration(const Duration(hours: 48)),
        notifier.terminate(started.demoSessionId),
        notifier.terminateAllActive(),
        notifier.cleanExpired(),
      ]) {
        expect(refused, isA<Failure<Object?>>());
        expect(
          (refused as Failure<Object?>).code,
          DemoControlPlaneCodes.notAuthorized,
        );
      }

      // And nothing moved: a refusal is not a partial write.
      expect(container.read(demoControlPlaneProvider).policy,
          DemoPolicy.initial);
      expect(
        container.read(demoControlPlaneProvider).sessionById(
              started.demoSessionId,
            )!.status,
        DemoSessionStatus.active,
      );
    });

    test('a change records who made it and bumps the revision', () {
      final container = plane();

      container
          .read(demoControlPlaneProvider.notifier)
          .setDefaultDuration(const Duration(hours: 48), actor: actor);

      final policy = container.read(demoControlPlaneProvider).policy;
      expect(policy.defaultDuration, const Duration(hours: 48));
      expect(policy.revision, 2);
      expect(policy.updatedBy, actor);
      expect(policy.updatedAt, now);
    });
  });

  group('disabling the offer', () {
    test('blocks a new trial from starting', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);

      notifier.setEnabled(false, actor: actor);

      final refused = notifier.startSession(accountId: 'acc_2');
      expect(refused, isA<Failure<DemoSession>>());
      expect(
        (refused as Failure<DemoSession>).code,
        DemoControlPlaneCodes.demoUnavailable,
      );
      // The login side sees the same answer, from the same policy.
      expect(container.read(customerDemoPolicyProvider).available, isFalse);
    });

    test('does not end the trials already running', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      final running = sessionOf(notifier.startSession(accountId: 'acc_1'));

      notifier.setEnabled(false, actor: actor);

      final after = container
          .read(demoControlPlaneProvider)
          .sessionById(running.demoSessionId)!;
      expect(after.statusAt(now), DemoSessionStatus.active);
      expect(after.expiresAt, running.expiresAt);
      expect(container.read(demoSessionCountsActive), 1);
    });
  });

  group('changing the default duration', () {
    test('applies to new sessions and leaves running ones alone', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      final before = sessionOf(notifier.startSession(accountId: 'acc_1'));

      notifier.setDefaultDuration(const Duration(hours: 48), actor: actor);
      final after = sessionOf(notifier.startSession(accountId: 'acc_2'));

      // The one started under the old policy keeps its own expiry, and still
      // records the revision that authorized it.
      final unchanged = container
          .read(demoControlPlaneProvider)
          .sessionById(before.demoSessionId)!;
      expect(unchanged.expiresAt, now.add(const Duration(hours: 24)));
      expect(unchanged.policyRevision, 1);

      expect(after.expiresAt, now.add(const Duration(hours: 48)));
      expect(after.policyRevision, 2);
    });

    test('will not go below an hour, however far it is stepped down', () {
      var duration = const Duration(hours: 24);
      for (var i = 0; i < 50; i++) {
        duration = DemoDurationPolicy.decrement(duration);
      }

      expect(duration, DemoDurationPolicy.minimum);
      expect(DemoDurationPolicy.canDecrease(duration), isFalse);

      final container = plane();
      container
          .read(demoControlPlaneProvider.notifier)
          .setDefaultDuration(Duration.zero, actor: actor);
      expect(
        container.read(demoControlPlaneProvider).policy.defaultDuration,
        DemoDurationPolicy.minimum,
      );
    });

    test('steps in hours below a day and in days above one', () {
      expect(
        DemoDurationPolicy.increment(const Duration(hours: 6)),
        const Duration(hours: 7),
      );
      expect(
        DemoDurationPolicy.increment(const Duration(hours: 24)),
        const Duration(hours: 48),
      );
      expect(
        DemoDurationPolicy.decrement(const Duration(hours: 48)),
        const Duration(hours: 24),
      );
      // And there is deliberately no ceiling in the client: the backend owns
      // the safe configured range.
      var far = const Duration(hours: 24);
      for (var i = 0; i < 100; i++) {
        far = DemoDurationPolicy.increment(far);
      }
      expect(far, const Duration(hours: 24 * 101));
    });
  });

  group('ending trials', () {
    test('terminates one, and refuses a second attempt on it', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      final one = sessionOf(notifier.startSession(accountId: 'acc_1'));
      final other = sessionOf(notifier.startSession(accountId: 'acc_2'));

      expect(notifier.terminate(one.demoSessionId, actor: actor).isSuccess,
          isTrue);

      final state = container.read(demoControlPlaneProvider);
      expect(state.sessionById(one.demoSessionId)!.statusAt(now),
          DemoSessionStatus.terminated);
      expect(state.sessionById(one.demoSessionId)!.endedAt, now);
      // The other trial is untouched — "terminate this one" means this one.
      expect(state.sessionById(other.demoSessionId)!.statusAt(now),
          DemoSessionStatus.active);

      final again = notifier.terminate(one.demoSessionId, actor: actor);
      expect((again as Failure<DemoSession>).code,
          DemoControlPlaneCodes.sessionNotActive);
    });

    test('terminates every running trial and answers how many', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      notifier.startSession(accountId: 'acc_1');
      notifier.startSession(accountId: 'acc_2');
      final third = sessionOf(notifier.startSession(accountId: 'acc_3'));
      notifier.terminate(third.demoSessionId, actor: actor);

      final result = notifier.terminateAllActive(actor: actor);

      // Two, not three: the one already ended was not ended twice.
      expect((result as Success<int>).data, 2);
      expect(container.read(demoSessionCountsActive), 0);
      // A second sweep has nothing to do, and says so rather than failing.
      expect(
        (notifier.terminateAllActive(actor: actor) as Success<int>).data,
        0,
      );
    });

    test('an unknown id is not found, and changes nothing', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      notifier.startSession(accountId: 'acc_1');

      final refused = notifier.terminate('nope', actor: actor);

      expect((refused as Failure<DemoSession>).code,
          DemoControlPlaneCodes.sessionNotFound);
      expect(container.read(demoSessionCountsActive), 1);
    });
  });

  group('expiry', () {
    test('closes a window by time alone, with no actor and no write', () {
      final container = plane();
      final session = sessionOf(container
          .read(demoControlPlaneProvider.notifier)
          .startSession(accountId: 'acc_1'));

      expect(session.statusAt(now), DemoSessionStatus.active);
      expect(session.remainingAt(now), const Duration(hours: 24));

      final later = now.add(const Duration(hours: 24));
      expect(session.statusAt(later), DemoSessionStatus.expired);
      expect(session.remainingAt(later), Duration.zero);
      // The stored field never moved: expiry is derived, not recorded.
      expect(session.status, DemoSessionStatus.active);
    });

    test('a terminated trial stays terminated whatever the clock says', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      final session = sessionOf(notifier.startSession(accountId: 'acc_1'));
      notifier.terminate(session.demoSessionId, actor: actor);

      final ended = container
          .read(demoControlPlaneProvider)
          .sessionById(session.demoSessionId)!;
      expect(
        ended.statusAt(now.add(const Duration(days: 9))),
        DemoSessionStatus.terminated,
      );
    });

    test('cleaning removes expired records and keeps terminated ones', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      final willExpire = sessionOf(notifier.startSession(accountId: 'acc_1'));
      final ended = sessionOf(notifier.startSession(accountId: 'acc_2'));
      notifier.terminate(ended.demoSessionId, actor: actor);

      now = now.add(const Duration(hours: 25));
      container.invalidate(demoSessionCountsActive);

      final removed = notifier.cleanExpired(actor: actor);

      expect((removed as Success<int>).data, 1);
      final state = container.read(demoControlPlaneProvider);
      expect(state.sessionById(willExpire.demoSessionId), isNull);
      // The decision somebody made is still on the record.
      expect(state.sessionById(ended.demoSessionId)!.status,
          DemoSessionStatus.terminated);
    });
  });

  group('starting a trial twice', () {
    test('resumes the running one instead of opening a second', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);

      final first = sessionOf(notifier.startSession(accountId: 'acc_1'));
      // A double tap, a retry after a dropped response, a second device.
      final second = sessionOf(notifier.startSession(accountId: 'acc_1'));

      expect(second.demoSessionId, first.demoSessionId);
      expect(second.expiresAt, first.expiresAt);
      // One person, one window — and the operator's list counts people, so a
      // duplicate here would be a miscount there.
      expect(container.read(demoControlPlaneProvider).sessions, hasLength(1));
    });

    test('is per identity — another account still gets its own', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);

      final mine = sessionOf(notifier.startSession(accountId: 'acc_1'));
      final theirs = sessionOf(notifier.startSession(accountId: 'acc_2'));

      expect(theirs.demoSessionId, isNot(mine.demoSessionId));
      expect(container.read(demoControlPlaneProvider).sessions, hasLength(2));
    });

    test('resumes even while the offer is switched off', () {
      // Disabling blocks *new* trials. Refusing to hand a running trial back
      // to its own holder would end it, which the switch explicitly does not.
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      final mine = sessionOf(notifier.startSession(accountId: 'acc_1'));
      notifier.setEnabled(false, actor: actor);

      expect(
        sessionOf(notifier.startSession(accountId: 'acc_1')).demoSessionId,
        mine.demoSessionId,
      );
      // But an identity with no trial is still refused one.
      expect(notifier.startSession(accountId: 'acc_2').isFailure, isTrue);
    });

    test('opens a fresh trial once the previous one is over', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      final first = sessionOf(notifier.startSession(accountId: 'acc_1'));

      now = now.add(const Duration(hours: 25));

      final second = sessionOf(notifier.startSession(accountId: 'acc_1'));
      expect(second.demoSessionId, isNot(first.demoSessionId));
      expect(second.expiresAt, now.add(const Duration(hours: 24)));
    });

    test('a start that does not complete leaves no record behind', () {
      // The window is stamped before the session exists, so a failed start has
      // to take its record with it: a trial nobody was ever in is not a trial
      // that ended early, and must not appear on the operator's list at all.
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      final stillborn = sessionOf(notifier.startSession(accountId: 'acc_1'));

      notifier.discardFailedStart(stillborn.demoSessionId);

      expect(container.read(demoControlPlaneProvider).sessions, isEmpty);
      // And the identity may try again cleanly.
      expect(notifier.startSession(accountId: 'acc_1').isSuccess, isTrue);
    });
  });

  group('how a trial was ended', () {
    test('the holder ending it is terminated — not a fourth state', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      final mine = sessionOf(notifier.startSession(accountId: 'acc_1'));

      notifier.endOwnSession(mine.demoSessionId);

      final record =
          container.read(demoControlPlaneProvider).sessionById(mine.demoSessionId)!;
      expect(record.status, DemoSessionStatus.terminated);
      expect(record.terminationReason, DemoSessionTerminationReason.userEnded);
      expect(record.endedAt, now);
      // Three lifecycle values, whatever the reason was.
      expect(DemoSessionStatus.values, hasLength(3));
    });

    test('an operator ending one is recorded as the operator', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      final theirs = sessionOf(notifier.startSession(accountId: 'acc_1'));

      final ended = sessionOf(
        notifier.terminate(theirs.demoSessionId, actor: actor),
      );

      expect(ended.status, DemoSessionStatus.terminated);
      expect(
        ended.terminationReason,
        DemoSessionTerminationReason.superAdminTerminated,
      );
    });

    test('terminate-all is distinguishable from ending one', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      notifier.startSession(accountId: 'acc_1');
      notifier.startSession(accountId: 'acc_2');

      notifier.terminateAllActive(actor: actor);

      for (final session in container.read(demoControlPlaneProvider).sessions) {
        expect(session.status, DemoSessionStatus.terminated);
        expect(
          session.terminationReason,
          DemoSessionTerminationReason.terminateAll,
        );
      }
    });

    test('a reason is metadata: expiry has none, and none authorizes anything',
        () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      final mine = sessionOf(notifier.startSession(accountId: 'acc_1'));

      now = now.add(const Duration(hours: 25));

      final record =
          container.read(demoControlPlaneProvider).sessionById(mine.demoSessionId)!;
      // Time ended it, so nobody asked for it.
      expect(record.statusAt(now), DemoSessionStatus.expired);
      expect(record.terminationReason, isNull);
      expect(record.endedAt, isNull);
    });
  });

  group('cleaning up is an operational action, never a history delete', () {
    test('it drops closed rows and touches nothing that records a decision',
        () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      final willExpire = sessionOf(notifier.startSession(accountId: 'acc_1'));
      final ended = sessionOf(notifier.startSession(accountId: 'acc_2'));
      notifier.terminate(ended.demoSessionId, actor: actor);
      final policyBefore = container.read(demoControlPlaneProvider).policy;

      now = now.add(const Duration(hours: 25));
      notifier.cleanExpired(actor: actor);

      final state = container.read(demoControlPlaneProvider);
      // The row an operator no longer reads is gone…
      expect(state.sessionById(willExpire.demoSessionId), isNull);
      // …and everything that records somebody's decision survives it: the
      // terminated session, why it ended, and the policy revision that
      // authorized the window. Audit itself is backend-authored and this
      // action has no reach into it at all (`BACKEND-HANDOFF.md` §12).
      final kept = state.sessionById(ended.demoSessionId)!;
      expect(kept.status, DemoSessionStatus.terminated);
      expect(
        kept.terminationReason,
        DemoSessionTerminationReason.superAdminTerminated,
      );
      expect(kept.policyRevision, policyBefore.revision);
      expect(state.policy, policyBefore);
    });

    test('a cleaned-away trial is still a trial that happened', () {
      // The evidence a demo existed does not live in this list, so removing a
      // row from it may never be read as "that trial never ran". The client
      // authors no Audit event and can erase none.
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      notifier.startSession(accountId: 'acc_1');

      now = now.add(const Duration(hours: 25));
      final removed = notifier.cleanExpired(actor: actor);

      expect((removed as Success<int>).data, 1);
      expect(container.read(demoControlPlaneProvider).sessions, isEmpty);
      // Nothing here offers a way to delete a started/terminated/expired fact;
      // the only history the product keeps is the backend's.
      expect(notifier.cleanExpired(actor: actor), isA<Success<int>>());
    });
  });

  group('the verdict a running trial is judged by', () {
    test('leaves an unregistered demo session alone', () {
      // No id registered: a session envelope saying "demo" is not retired by a
      // control plane that never saw it.
      expect(plane().read(demoSessionVerdictProvider), DemoMode.active);
    });

    test('expires when the record is terminated, and when time runs out', () {
      final container = plane();
      final notifier = container.read(demoControlPlaneProvider.notifier);
      final session = sessionOf(notifier.startSession(accountId: 'acc_1'));
      container.read(activeDemoSessionIdProvider.notifier).state =
          session.demoSessionId;

      expect(container.read(demoSessionVerdictProvider), DemoMode.active);

      notifier.terminate(session.demoSessionId, actor: actor);
      expect(container.read(demoSessionVerdictProvider), DemoMode.expired);
    });

    test('expires when the record has been cleaned away', () {
      final container = plane();
      container.read(activeDemoSessionIdProvider.notifier).state = 'gone';

      expect(container.read(demoSessionVerdictProvider), DemoMode.expired);
    });
  });

  group('what a session record may carry', () {
    test('is an id, an account, a workspace and three timestamps — no more',
        () {
      final container = plane();
      final session = sessionOf(container
          .read(demoControlPlaneProvider.notifier)
          .startSession(accountId: 'acc_1'));

      final json = session.toJson();

      // Whatever a future backend adds, none of these words may appear: the
      // operator's list is not a place a credential can leak into.
      final serialized = json.toString().toLowerCase();
      for (final secret in [
        'token',
        'secret',
        'password',
        'credential',
        'bearer',
        'cookie',
      ]) {
        expect(serialized, isNot(contains(secret)), reason: secret);
      }
      expect(json.keys, containsAll(<String>['demoSessionId', 'accountId']));
    });
  });
}

/// The active count, as a provider so a test can invalidate it after moving
/// the pinned clock.
final demoSessionCountsActive = Provider<int>((ref) {
  final now = ref.watch(clockProvider)();
  return ref.watch(demoControlPlaneProvider).activeAt(now).length;
});
