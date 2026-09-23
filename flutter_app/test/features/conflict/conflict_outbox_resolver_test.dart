import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/features/conflict/data/conflict_current_application.dart';
import 'package:mtm/features/conflict/data/conflict_outbox_resolver.dart';
import 'package:mtm/features/conflict/data/conflict_review_controller.dart';
import 'package:mtm/features/conflict/data/in_memory_conflict_review_store.dart';
import 'package:mtm/features/conflict/domain/conflict_models.dart';
import 'package:mtm/features/conflict/domain/conflict_review_entry.dart';

/// The seam between a Task 1 [ConflictResolutionDecision] and the shared
/// outbox / review store — see `conflict_outbox_resolver.dart`'s file doc
/// comment for what this deliberately does and does not claim.
///
/// Task 4 corrective pass: `useLocal` now mints a new logical operation
/// (`FRONTEND-BACKEND-INTEGRATION.md` §5.5) instead of requeuing the
/// original under the same identity, and `useCurrent` now applies the
/// feature-owned "current" snapshot locally before the pending write is
/// retired, through the `conflictCurrentAppliersProvider` registry seam.
/// Both use fake, failure-injecting collaborators here — the *real* Shift
/// composer/applier are covered separately in
/// `test/features/shift/shift_conflict_review_test.dart`.
void main() {
  const conflictId = 'op-conflict-1';

  ConflictReviewEntry entry({String conflictId = conflictId}) =>
      ConflictReviewEntry(
        conflictId: conflictId,
        entityType: 'shift',
        entityId: 'sh_1',
        recordTitle: 'الشفت · مركز داريا',
        detectedAt: DateTime(2026, 9, 5, 10),
        differences: const [
          ConflictFieldComparison(
            fieldId: 'needed',
            label: 'العدد المطلوب',
            localValue: '٤',
            currentValue: '٦',
          ),
        ],
      );

  PendingOperation conflictedOp({String id = conflictId}) =>
      PendingOperation.create(
        kind: 'shift.assign',
        entityType: 'shift',
        entityId: 'sh_1',
        idFactory: () => id,
      ).copyWith(state: SyncState.conflict, lastProblemCode: 'stale');

  ProviderContainer containerWith({
    required PendingOperation seededOp,
    ConflictReviewEntry? seededEntry,
    Map<String, ConflictCurrentApplier> appliers = const {},
    String Function() newId = _fixedNewId,
  }) {
    final c = ProviderContainer(overrides: [
      outboxStoreProvider
          .overrideWithValue(InMemoryOutboxStore(seed: [seededOp])),
      conflictReviewStoreProvider.overrideWithValue(
        InMemoryConflictReviewStore(
          seed: seededEntry == null ? [] : [seededEntry],
        ),
      ),
      newOperationIdProvider.overrideWithValue(newId),
      conflictCurrentAppliersProvider.overrideWithValue(appliers),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('useLocal', () {
    test(
        'mints a new operation that references the original, and forgets '
        'the review entry', () async {
      final op = conflictedOp();
      final c = containerWith(seededOp: op, seededEntry: entry());
      await c.read(outboxProvider.future);
      final handler = c.read(conflictDecisionHandlerProvider);

      await handler(ConflictResolutionDecision(
        conflictId: conflictId,
        localOperationId: op.operationId,
        intent: ConflictResolutionIntent.useLocal,
        currentVersion: '8',
      ));

      final ops = await c.read(outboxProvider.future);
      final replacement = ops.single;
      expect(replacement.operationId, isNot(op.operationId));
      expect(replacement.state, SyncState.pending);
      expect(replacement.resolvesOperationId, op.operationId);
      expect(replacement.currentVersion, '8');
      expect(await c.read(conflictReviewProvider.future), isEmpty);
    });

    test(
        'a failure minting the replacement leaves the conflict and its '
        'review entry exactly as they were', () async {
      final op = conflictedOp();
      final c = containerWith(
        seededOp: op,
        seededEntry: entry(),
        newId: () => throw StateError('id factory unavailable'),
      );
      await c.read(outboxProvider.future);
      final handler = c.read(conflictDecisionHandlerProvider);

      await expectLater(
        handler(ConflictResolutionDecision(
          conflictId: conflictId,
          localOperationId: op.operationId,
          intent: ConflictResolutionIntent.useLocal,
          currentVersion: '8',
        )),
        throwsA(isA<StateError>()),
      );

      final ops = await c.read(outboxProvider.future);
      expect(ops.single.operationId, op.operationId);
      expect(ops.single.state, SyncState.conflict);
      expect(await c.read(conflictReviewProvider.future), hasLength(1));
    });

    test(
        'a missing currentVersion preserves the original operation and its '
        'review entry — no replacement is minted', () async {
      final op = conflictedOp();
      final c = containerWith(seededOp: op, seededEntry: entry());
      await c.read(outboxProvider.future);
      final handler = c.read(conflictDecisionHandlerProvider);

      await expectLater(
        handler(ConflictResolutionDecision(
          conflictId: conflictId,
          localOperationId: op.operationId,
          intent: ConflictResolutionIntent.useLocal,
          // currentVersion omitted — null.
        )),
        throwsA(isA<StateError>()),
      );

      final ops = await c.read(outboxProvider.future);
      expect(ops.single.operationId, op.operationId);
      expect(ops.single.state, SyncState.conflict);
      expect(await c.read(conflictReviewProvider.future), hasLength(1));
    });

    test(
        'a conflictId that does not match the operation is rejected '
        'without changing anything', () async {
      final op = conflictedOp();
      final c = containerWith(seededOp: op, seededEntry: entry());
      await c.read(outboxProvider.future);
      final handler = c.read(conflictDecisionHandlerProvider);

      await expectLater(
        handler(ConflictResolutionDecision(
          conflictId: 'not-the-operation-id',
          localOperationId: op.operationId,
          intent: ConflictResolutionIntent.useLocal,
          currentVersion: '8',
        )),
        throwsA(isA<StateError>()),
      );

      final ops = await c.read(outboxProvider.future);
      expect(ops.single.operationId, op.operationId);
      expect(ops.single.state, SyncState.conflict);
      expect(await c.read(conflictReviewProvider.future), hasLength(1));
    });
  });

  group('useCurrent', () {
    test(
        'applies the current snapshot locally, then retires the operation '
        'and forgets its review entry', () async {
      final op = conflictedOp();
      final calls = <String>[];
      final c = containerWith(
        seededOp: op,
        seededEntry: entry(),
        appliers: {
          'shift': (operation) async {
            calls.add('applied:${operation.operationId}');
            return true;
          },
        },
      );
      await c.read(outboxProvider.future);
      final handler = c.read(conflictDecisionHandlerProvider);

      await handler(ConflictResolutionDecision(
        conflictId: conflictId,
        localOperationId: op.operationId,
        intent: ConflictResolutionIntent.useCurrent,
      ));

      expect(calls, ['applied:${op.operationId}']);
      expect(await c.read(outboxProvider.future), isEmpty);
      expect(await c.read(conflictReviewProvider.future), isEmpty);
    });

    test(
        'a failed local application preserves the operation and its '
        'review entry — no network call, no replacement operation', () async {
      final op = conflictedOp();
      final c = containerWith(
        seededOp: op,
        seededEntry: entry(),
        appliers: {'shift': (operation) async => false},
      );
      await c.read(outboxProvider.future);
      final handler = c.read(conflictDecisionHandlerProvider);

      await expectLater(
        handler(ConflictResolutionDecision(
          conflictId: conflictId,
          localOperationId: op.operationId,
          intent: ConflictResolutionIntent.useCurrent,
        )),
        throwsA(isA<StateError>()),
      );

      final ops = await c.read(outboxProvider.future);
      expect(ops, hasLength(1));
      expect(ops.single.operationId, op.operationId);
      expect(ops.single.state, SyncState.conflict);
      expect(await c.read(conflictReviewProvider.future), hasLength(1));
    });

    test(
        'an applier that throws is treated the same as a failed apply — '
        'the local edit is never silently discarded', () async {
      final op = conflictedOp();
      final c = containerWith(
        seededOp: op,
        seededEntry: entry(),
        appliers: {
          'shift': (operation) async => throw StateError('snapshot unusable'),
        },
      );
      await c.read(outboxProvider.future);
      final handler = c.read(conflictDecisionHandlerProvider);

      await expectLater(
        handler(ConflictResolutionDecision(
          conflictId: conflictId,
          localOperationId: op.operationId,
          intent: ConflictResolutionIntent.useCurrent,
        )),
        throwsA(isA<StateError>()),
      );

      final ops = await c.read(outboxProvider.future);
      expect(ops.single.operationId, op.operationId);
      expect(ops.single.state, SyncState.conflict);
      expect(await c.read(conflictReviewProvider.future), hasLength(1));
    });

    test(
        'no registered adapter for the domain cannot silently discard the '
        'local work', () async {
      final op = conflictedOp();
      // No 'shift' entry in the appliers map at all.
      final c = containerWith(seededOp: op, seededEntry: entry());
      await c.read(outboxProvider.future);
      final handler = c.read(conflictDecisionHandlerProvider);

      await expectLater(
        handler(ConflictResolutionDecision(
          conflictId: conflictId,
          localOperationId: op.operationId,
          intent: ConflictResolutionIntent.useCurrent,
        )),
        throwsA(isA<StateError>()),
      );

      final ops = await c.read(outboxProvider.future);
      expect(ops.single.operationId, op.operationId);
      expect(await c.read(conflictReviewProvider.future), hasLength(1));
    });
  });

  test(
      'reviewLater leaves the conflicted operation and its review entry '
      'untouched', () async {
    final op = conflictedOp();
    final c = containerWith(seededOp: op, seededEntry: entry());
    await c.read(outboxProvider.future);
    final handler = c.read(conflictDecisionHandlerProvider);

    await handler(ConflictResolutionDecision(
      conflictId: conflictId,
      localOperationId: op.operationId,
      intent: ConflictResolutionIntent.reviewLater,
    ));

    final ops = await c.read(outboxProvider.future);
    final stored = ops.single;
    expect(stored.state, SyncState.conflict);
    expect(stored.operationId, op.operationId);
    expect(stored.idempotencyKey, op.idempotencyKey);
    expect(await c.read(conflictReviewProvider.future), hasLength(1));
  });
}

String _fixedNewId() => 'op-new';
