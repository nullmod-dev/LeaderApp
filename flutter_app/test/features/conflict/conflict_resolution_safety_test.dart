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

/// The conflict cases nobody can reproduce by hand: the conflict that was
/// already decided somewhere else, the record that moved *again* while the
/// screen was open, and the feature writer that failed for a reason the user
/// deserves to be told precisely (roadmap §7, §9, §10, §16).
///
/// The rule every one of these holds to: a resolution that does not happen
/// leaves the local change, the conflict, and the metadata behind it exactly
/// as they were.
void main() {
  const conflictId = 'op-conflict-1';

  ConflictReviewEntry entry({String? currentVersion}) => ConflictReviewEntry(
        conflictId: conflictId,
        entityType: 'shift',
        entityId: 'sh_1',
        recordTitle: 'الشفت · مركز داريا',
        detectedAt: DateTime(2026, 9, 5, 10),
        currentVersion: currentVersion,
        differences: const [
          ConflictFieldComparison(
            fieldId: 'needed',
            label: 'العدد المطلوب',
            localValue: '٤',
            currentValue: '٦',
          ),
        ],
      );

  PendingOperation op({SyncState state = SyncState.conflict}) =>
      PendingOperation.create(
        kind: 'shift.assign',
        entityType: 'shift',
        entityId: 'sh_1',
        idFactory: () => conflictId,
      ).copyWith(state: state, lastProblemCode: 'stale_write');

  ProviderContainer containerWith({
    List<PendingOperation> ops = const [],
    ConflictReviewEntry? storedEntry,
    Map<String, ConflictCurrentApplier> appliers = const {},
  }) {
    final c = ProviderContainer(overrides: [
      outboxStoreProvider.overrideWithValue(InMemoryOutboxStore(seed: ops)),
      conflictReviewStoreProvider.overrideWithValue(
        InMemoryConflictReviewStore(
          seed: storedEntry == null ? [] : [storedEntry],
        ),
      ),
      newOperationIdProvider.overrideWithValue(() => 'replacement-1'),
      conflictCurrentAppliersProvider.overrideWithValue(appliers),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  ConflictResolutionDecision decision(
    ConflictResolutionIntent intent, {
    String? currentVersion = '8',
  }) =>
      ConflictResolutionDecision(
        conflictId: conflictId,
        localOperationId: conflictId,
        intent: intent,
        currentVersion: currentVersion,
      );

  group('a conflict that is no longer there', () {
    test('is reported as already resolved, not as a failure to save', () async {
      final c = containerWith(ops: const [], storedEntry: entry());
      await c.read(outboxProvider.future);

      await expectLater(
        c.read(conflictDecisionHandlerProvider)(
          decision(ConflictResolutionIntent.useLocal),
        ),
        throwsA(
          isA<ConflictResolutionException>()
              .having((e) => e.reason, 'reason',
                  ConflictResolutionFailure.alreadyResolved)
              .having((e) => e.isStale, 'closes the screen', isTrue),
        ),
      );
    });

    test('drops the metadata it left behind, so the list stops offering it',
        () async {
      final c = containerWith(ops: const [], storedEntry: entry());
      await c.read(outboxProvider.future);
      expect(await c.read(conflictReviewProvider.future), hasLength(1));

      await expectLater(
        c.read(conflictDecisionHandlerProvider)(
          decision(ConflictResolutionIntent.useCurrent),
        ),
        throwsA(isA<ConflictResolutionException>()),
      );

      expect(await c.read(conflictReviewProvider.future), isEmpty);
      expect(c.read(needsReviewItemsProvider).value, isEmpty);
    });

    test('an operation that has moved on is not resolved again', () async {
      // Superseded elsewhere: the row is here, but it is no longer waiting on
      // a decision.
      final c = containerWith(
        ops: [op(state: SyncState.pending)],
        storedEntry: entry(),
      );
      await c.read(outboxProvider.future);

      await expectLater(
        c.read(conflictDecisionHandlerProvider)(
          decision(ConflictResolutionIntent.useLocal),
        ),
        throwsA(isA<ConflictResolutionException>().having((e) => e.reason,
            'reason', ConflictResolutionFailure.alreadyResolved)),
      );

      final ops = await c.read(outboxProvider.future);
      expect(ops.single.operationId, conflictId,
          reason: 'nothing was superseded');
      expect(ops.single.state, SyncState.pending);
    });
  });

  group('a record that changed again after the comparison was built', () {
    test('is not resolved against the version the user never saw', () async {
      final c = containerWith(
        ops: [op()],
        // Detected a second time since: the stored "current" moved on.
        storedEntry: entry(currentVersion: '9'),
      );
      await c.read(outboxProvider.future);

      await expectLater(
        c.read(conflictDecisionHandlerProvider)(
          decision(ConflictResolutionIntent.useLocal, currentVersion: '8'),
        ),
        throwsA(
          isA<ConflictResolutionException>()
              .having((e) => e.reason, 'reason',
                  ConflictResolutionFailure.recordChanged)
              .having((e) => e.isStale, 'closes the screen', isTrue),
        ),
      );

      final ops = await c.read(outboxProvider.future);
      expect(ops.single.operationId, conflictId);
      expect(ops.single.state, SyncState.conflict);
      expect(await c.read(conflictReviewProvider.future), hasLength(1));
    });

    test('blocks the destructive choice too', () async {
      final c = containerWith(
        ops: [op()],
        storedEntry: entry(currentVersion: '9'),
        appliers: {'shift': (_) async => true},
      );
      await c.read(outboxProvider.future);

      await expectLater(
        c.read(conflictDecisionHandlerProvider)(
          decision(ConflictResolutionIntent.useCurrent, currentVersion: '8'),
        ),
        throwsA(isA<ConflictResolutionException>().having((e) => e.reason,
            'reason', ConflictResolutionFailure.recordChanged)),
      );

      expect(await c.read(outboxProvider.future), hasLength(1),
          reason: 'the local edit was not discarded');
    });

    test('a version only one side knows is no evidence, and blocks nothing',
        () async {
      final c = containerWith(
        ops: [op()],
        // Detection captured no version at all.
        storedEntry: entry(),
      );
      await c.read(outboxProvider.future);

      await c.read(conflictDecisionHandlerProvider)(
        decision(ConflictResolutionIntent.useLocal, currentVersion: '8'),
      );

      final ops = await c.read(outboxProvider.future);
      expect(ops.single.resolvesOperationId, conflictId,
          reason: 'the resolution went through');
    });

    test('matching versions resolve normally', () async {
      final c = containerWith(
        ops: [op()],
        storedEntry: entry(currentVersion: '8'),
      );
      await c.read(outboxProvider.future);

      await c.read(conflictDecisionHandlerProvider)(
        decision(ConflictResolutionIntent.useLocal, currentVersion: '8'),
      );

      expect((await c.read(outboxProvider.future)).single.currentVersion, '8');
      expect(await c.read(conflictReviewProvider.future), isEmpty);
    });
  });

  group('a feature writer that refused', () {
    Future<void> expectReason(
      ConflictResolutionFailure reason,
      ConflictCurrentApplier applier,
    ) async {
      final c = containerWith(
        ops: [op()],
        storedEntry: entry(),
        appliers: {'shift': applier},
      );
      await c.read(outboxProvider.future);

      await expectLater(
        c.read(conflictDecisionHandlerProvider)(
          decision(ConflictResolutionIntent.useCurrent, currentVersion: null),
        ),
        throwsA(isA<ConflictResolutionException>()
            .having((e) => e.reason, 'reason', reason)),
      );

      final ops = await c.read(outboxProvider.future);
      expect(ops.single.state, SyncState.conflict,
          reason: 'the conflict and the local edit are still here');
      expect(await c.read(conflictReviewProvider.future), hasLength(1));
    }

    test('says the record was deleted, and keeps the local change', () async {
      await expectReason(
        ConflictResolutionFailure.recordDeleted,
        (_) async => throw ConflictResolutionException(
          ConflictResolutionFailure.recordDeleted,
          'gone',
        ),
      );
    });

    test('says the session may not do this, and keeps the local change',
        () async {
      await expectReason(
        ConflictResolutionFailure.notPermitted,
        (_) async => throw ConflictResolutionException(
          ConflictResolutionFailure.notPermitted,
          'forbidden',
        ),
      );
    });

    test('says a connection is needed, and keeps the local change', () async {
      await expectReason(
        ConflictResolutionFailure.offline,
        (_) async => throw ConflictResolutionException(
          ConflictResolutionFailure.offline,
          'no connection',
        ),
      );
    });

    test('a plain refusal is neither stale nor specific', () async {
      final c = containerWith(
        ops: [op()],
        storedEntry: entry(),
        appliers: {'shift': (_) async => false},
      );
      await c.read(outboxProvider.future);

      await expectLater(
        c.read(conflictDecisionHandlerProvider)(
          decision(ConflictResolutionIntent.useCurrent, currentVersion: null),
        ),
        throwsA(isA<ConflictResolutionException>()
            .having((e) => e.reason, 'reason',
                ConflictResolutionFailure.couldNotApply)
            .having((e) => e.isStale, 'keeps the screen open', isFalse)),
      );
    });
  });
}
