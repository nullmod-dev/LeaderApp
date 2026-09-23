import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_coordinator.dart';
import 'package:mtm/core/sync/sync_overview.dart';
import 'package:mtm/core/sync/sync_state.dart';

/// The Sync Center's read model (roadmap §6).
///
/// These cover the parts a person cannot check by looking at the screen: the
/// counts, the priority between conditions that are true at the same time,
/// and what the app is allowed to claim about the connection. The layout
/// itself is verified by hand.
void main() {
  PendingOperation op(
    String id, {
    SyncState state = SyncState.pending,
    String? problem,
  }) =>
      PendingOperation.create(
        kind: 'shift.assign',
        entityType: 'shift',
        entityId: 'sh_1',
        idFactory: () => id,
      ).copyWith(state: state, lastProblemCode: problem);

  const idle = SyncStatus();

  group('counts', () {
    test('waiting covers not-yet-attempted and in-flight, never the rest', () {
      final o = buildSyncOverview(
        operations: [
          op('a'),
          op('b', state: SyncState.syncing),
          op('c', state: SyncState.failed, problem: 'server'),
          op('d', state: SyncState.conflict, problem: 'stale_write'),
        ],
        status: idle,
      );

      expect(o.waitingCount, 2);
      expect(o.failedCount, 1);
      expect(o.reviewCount, 1);
    });

    test('what the retry loop owes excludes conflicts — those wait on a human',
        () {
      final o = buildSyncOverview(
        operations: [
          op('a'),
          op('b', state: SyncState.failed),
          op('c', state: SyncState.conflict),
          op('d', state: SyncState.conflict),
        ],
        status: idle,
      );

      expect(o.pendingCount, 2);
      expect(o.reviewCount, 2);
      expect(o.hasUnsyncedWork, isTrue);
    });

    test('an empty outbox is up to date, not offline and not failed', () {
      final o = buildSyncOverview(operations: const [], status: idle);

      expect(o.health, SyncHealth.upToDate);
      expect(o.pendingCount, 0);
      expect(o.reviewCount, 0);
    });
  });

  group('status priority when several conditions are true at once', () {
    test('a run in flight is reported before anything else', () {
      final o = buildSyncOverview(
        operations: [op('a', state: SyncState.conflict), op('b')],
        status: const SyncStatus(
          phase: SyncPhase.syncing,
          lastOutcome: SyncRunOutcome.offline,
        ),
      );

      expect(o.health, SyncHealth.syncing);
      expect(o.isSyncing, isTrue);
    });

    test(
        'review outranks offline, failure and pending — only a human clears it',
        () {
      final o = buildSyncOverview(
        operations: [
          op('a', state: SyncState.conflict),
          op('b', state: SyncState.failed, problem: 'offline'),
          op('c'),
        ],
        status: const SyncStatus(lastOutcome: SyncRunOutcome.offline),
      );

      expect(o.health, SyncHealth.needsReview);
      // The counts behind the other conditions are still reported.
      expect(o.failedCount, 1);
      expect(o.waitingCount, 1);
    });

    test('offline outranks a failure while work is owed', () {
      final o = buildSyncOverview(
        operations: [op('a', state: SyncState.failed, problem: 'offline')],
        status: const SyncStatus(lastOutcome: SyncRunOutcome.offline),
      );

      expect(o.health, SyncHealth.offline);
    });

    test('offline with nothing owed is not raised as a sync problem', () {
      final o = buildSyncOverview(
        operations: const [],
        status: const SyncStatus(lastOutcome: SyncRunOutcome.offline),
      );

      expect(o.health, SyncHealth.upToDate);
      // The connection is still reported honestly, just not as an alarm.
      expect(o.connection, SyncConnection.offline);
    });

    test('a failure outranks work that has not been attempted', () {
      final o = buildSyncOverview(
        operations: [
          op('a', state: SyncState.failed, problem: 'server'),
          op('b')
        ],
        status: const SyncStatus(lastOutcome: SyncRunOutcome.failed),
      );

      expect(o.health, SyncHealth.failed);
    });
  });

  group('what may be claimed about the connection', () {
    test('nothing at all before a run has proved anything', () {
      final o = buildSyncOverview(operations: [op('a')], status: idle);

      expect(o.connection, SyncConnection.unknown);
      expect(o.isOffline, isFalse);
      expect(o.health, SyncHealth.pending);
    });

    test('a run that could not leave the device means offline', () {
      final o = buildSyncOverview(
        operations: [op('a', state: SyncState.failed, problem: 'offline')],
        status: const SyncStatus(lastOutcome: SyncRunOutcome.offline),
      );

      expect(o.connection, SyncConnection.offline);
    });

    test('a server that answered means online, even when it refused', () {
      for (final outcome in [
        SyncRunOutcome.allSynced,
        SyncRunOutcome.partial,
        SyncRunOutcome.needsReview,
      ]) {
        final o = buildSyncOverview(
          operations: const [],
          status: SyncStatus(lastOutcome: outcome),
        );
        expect(o.connection, SyncConnection.online, reason: outcome.name);
      }
    });

    test(
        'a connection lost mid-run is reported, not the success that came '
        'before it', () {
      final o = buildSyncOverview(
        // One change got through; the next could not leave the device.
        operations: [op('b', state: SyncState.failed, problem: 'offline')],
        status: const SyncStatus(lastOutcome: SyncRunOutcome.partial),
      );

      expect(o.connection, SyncConnection.offline);
      expect(o.health, SyncHealth.offline);
    });

    test('a generic failure claims neither — it proves neither', () {
      final o = buildSyncOverview(
        operations: [op('a', state: SyncState.failed, problem: 'server')],
        status: const SyncStatus(lastOutcome: SyncRunOutcome.failed),
      );

      expect(o.connection, SyncConnection.unknown);
    });

    test(
        'after a relaunch, a change that died for lack of connectivity is the '
        'evidence that survives', () {
      final o = buildSyncOverview(
        operations: [op('a', state: SyncState.failed, problem: 'offline')],
        // No run has happened yet in this session.
        status: idle,
      );

      expect(o.connection, SyncConnection.offline);
      expect(o.health, SyncHealth.offline);
    });

    test('a restored change with an unrelated problem claims nothing', () {
      final o = buildSyncOverview(
        operations: [op('a', state: SyncState.failed, problem: 'server')],
        status: idle,
      );

      expect(o.connection, SyncConnection.unknown);
      expect(o.health, SyncHealth.failed);
    });
  });

  test('the last successful sync is carried through untouched', () {
    final at = DateTime(2026, 9, 5, 19, 32);
    final o = buildSyncOverview(
      operations: const [],
      status: SyncStatus(
        lastSyncedAt: at,
        lastOutcome: SyncRunOutcome.allSynced,
      ),
    );

    expect(o.lastSyncedAt, at);
  });

  test('never synced is a state, not a failure', () {
    final o = buildSyncOverview(operations: const [], status: idle);

    expect(o.lastSyncedAt, isNull);
    expect(o.health, SyncHealth.upToDate);
  });
}
