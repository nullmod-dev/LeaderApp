import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_state.dart';

/// Task 4 corrective pass — `OutboxController.supersedeConflict` is the
/// create-then-retire, new-identity `useLocal` protocol
/// `FRONTEND-BACKEND-INTEGRATION.md` §5.5 decided and the old
/// `requeueAfterConflict`-based `useLocal` never actually implemented. These
/// tests exercise the primitive itself, with a failure-injecting fake store
/// so the ordering guarantees are proven, not merely asserted on the
/// happy path.
///
/// Final narrow correction: `supersedeConflict` now rejects a non-conflict
/// original and a missing/empty `resolutionVersion` before writing or
/// deleting anything — every call below that resolves successfully now
/// supplies a version explicitly, so the two new rejection tests are the
/// only ones exercising the "no version supplied" path.
class _FailingOutboxStore implements OutboxStore {
  _FailingOutboxStore(this._delegate);

  final OutboxStore _delegate;
  final List<String> calls = [];
  bool Function(PendingOperation operation)? failUpsertWhen;
  bool Function(String operationId)? failRemoveWhen;

  @override
  Future<List<PendingOperation>> readAll() => _delegate.readAll();

  @override
  Future<void> upsert(PendingOperation operation) async {
    calls.add('upsert:${operation.operationId}');
    if (failUpsertWhen?.call(operation) ?? false) {
      throw StateError('simulated upsert failure');
    }
    await _delegate.upsert(operation);
  }

  @override
  Future<void> remove(String operationId) async {
    calls.add('remove:$operationId');
    if (failRemoveWhen?.call(operationId) ?? false) {
      throw StateError('simulated remove failure');
    }
    await _delegate.remove(operationId);
  }
}

void main() {
  PendingOperation conflictedOp({String id = 'op-original'}) =>
      PendingOperation.create(
        kind: 'shift.assign',
        entityType: 'shift',
        entityId: 'sh_1',
        idFactory: () => id,
      ).copyWith(state: SyncState.conflict, lastProblemCode: 'stale');

  ({ProviderContainer container, _FailingOutboxStore store}) containerWith({
    required PendingOperation seeded,
    String Function() newId = _fixedNewId,
  }) {
    final store = _FailingOutboxStore(InMemoryOutboxStore(seed: [seeded]));
    final c = ProviderContainer(overrides: [
      outboxStoreProvider.overrideWithValue(store),
      newOperationIdProvider.overrideWithValue(newId),
    ]);
    addTearDown(c.dispose);
    return (container: c, store: store);
  }

  group('the replacement operation', () {
    test('gets a new operationId, distinct from the original', () async {
      final op = conflictedOp();
      final ctx = containerWith(seeded: op);
      await ctx.container.read(outboxProvider.future);

      final replacement = await ctx.container
          .read(outboxProvider.notifier)
          .supersedeConflict(
              originalOperationId: op.operationId, resolutionVersion: '8');

      expect(replacement.operationId, isNot(op.operationId));
      expect(replacement.operationId, 'op-new');
    });

    test('gets a new idempotencyKey, distinct from the original', () async {
      final op = conflictedOp();
      final ctx = containerWith(seeded: op);
      await ctx.container.read(outboxProvider.future);

      final replacement = await ctx.container
          .read(outboxProvider.notifier)
          .supersedeConflict(
              originalOperationId: op.operationId, resolutionVersion: '8');

      expect(replacement.idempotencyKey, isNot(op.idempotencyKey));
      expect(replacement.idempotencyKey, replacement.operationId);
    });

    test('references the original operation it resolves', () async {
      final op = conflictedOp();
      final ctx = containerWith(seeded: op);
      await ctx.container.read(outboxProvider.future);

      final replacement = await ctx.container
          .read(outboxProvider.notifier)
          .supersedeConflict(
              originalOperationId: op.operationId, resolutionVersion: '8');

      expect(replacement.resolvesOperationId, op.operationId);
      expect(replacement.isConflictResolution, isTrue);
    });

    test('carries the latest/current version forward', () async {
      final op = conflictedOp();
      final ctx = containerWith(seeded: op);
      await ctx.container.read(outboxProvider.future);

      final replacement =
          await ctx.container.read(outboxProvider.notifier).supersedeConflict(
                originalOperationId: op.operationId,
                resolutionVersion: '8',
              );

      expect(replacement.currentVersion, '8');
    });

    test('starts pending, so the ordinary sync loop tries it next run',
        () async {
      final op = conflictedOp();
      final ctx = containerWith(seeded: op);
      await ctx.container.read(outboxProvider.future);

      final replacement = await ctx.container
          .read(outboxProvider.notifier)
          .supersedeConflict(
              originalOperationId: op.operationId, resolutionVersion: '8');

      expect(replacement.state, SyncState.pending);
    });
  });

  test('the replacement is stored before the original is retired', () async {
    final op = conflictedOp();
    final ctx = containerWith(seeded: op);
    await ctx.container.read(outboxProvider.future);

    await ctx.container.read(outboxProvider.notifier).supersedeConflict(
        originalOperationId: op.operationId, resolutionVersion: '8');

    expect(ctx.store.calls, ['upsert:op-new', 'remove:op-original']);
  });

  test('validates the original conflicted operation still exists', () async {
    final op = conflictedOp();
    final ctx = containerWith(seeded: op);
    await ctx.container.read(outboxProvider.future);

    expect(
      () => ctx.container.read(outboxProvider.notifier).supersedeConflict(
            originalOperationId: 'never-existed',
            resolutionVersion: '8',
          ),
      throwsA(isA<StateError>()),
    );
  });

  group('validation before any write', () {
    test(
        'rejects an original operation that exists but is not a conflict — '
        'without writing or deleting anything', () async {
      final op = conflictedOp().copyWith(state: SyncState.pending);
      final ctx = containerWith(seeded: op);
      await ctx.container.read(outboxProvider.future);

      await expectLater(
        ctx.container.read(outboxProvider.notifier).supersedeConflict(
              originalOperationId: op.operationId,
              resolutionVersion: '8',
            ),
        throwsA(isA<StateError>()),
      );

      expect(ctx.store.calls, isEmpty);
      final stored = (await ctx.container.read(outboxProvider.future)).single;
      expect(stored.state, SyncState.pending);
      expect(stored.resolvesOperationId, isNull);
    });

    test(
        'rejects a missing current version — without writing or deleting '
        'anything', () async {
      final op = conflictedOp();
      final ctx = containerWith(seeded: op);
      await ctx.container.read(outboxProvider.future);

      await expectLater(
        ctx.container
            .read(outboxProvider.notifier)
            .supersedeConflict(originalOperationId: op.operationId),
        throwsA(isA<StateError>()),
      );

      expect(ctx.store.calls, isEmpty);
      final stored = (await ctx.container.read(outboxProvider.future)).single;
      expect(stored.operationId, op.operationId);
      expect(stored.state, SyncState.conflict);
    });

    test(
        'rejects an empty current version — without writing or deleting '
        'anything', () async {
      final op = conflictedOp();
      final ctx = containerWith(seeded: op);
      await ctx.container.read(outboxProvider.future);

      await expectLater(
        ctx.container.read(outboxProvider.notifier).supersedeConflict(
              originalOperationId: op.operationId,
              resolutionVersion: '',
            ),
        throwsA(isA<StateError>()),
      );

      expect(ctx.store.calls, isEmpty);
      final stored = (await ctx.container.read(outboxProvider.future)).single;
      expect(stored.operationId, op.operationId);
      expect(stored.state, SyncState.conflict);
    });
  });

  group('failure preservation', () {
    test(
        'a failure creating the replacement preserves the original conflict '
        'and its identity untouched', () async {
      final op = conflictedOp();
      final ctx = containerWith(seeded: op);
      ctx.store.failUpsertWhen =
          (candidate) => candidate.operationId == 'op-new';
      await ctx.container.read(outboxProvider.future);

      await expectLater(
        ctx.container.read(outboxProvider.notifier).supersedeConflict(
              originalOperationId: op.operationId,
              resolutionVersion: '8',
            ),
        throwsA(isA<StateError>()),
      );

      final stored = (await ctx.container.read(outboxProvider.future)).single;
      expect(stored.operationId, op.operationId);
      expect(stored.idempotencyKey, op.idempotencyKey);
      expect(stored.state, SyncState.conflict);
    });

    test(
        'a failure retiring the original never leaves the user with neither '
        'operation', () async {
      final op = conflictedOp();
      final ctx = containerWith(seeded: op);
      ctx.store.failRemoveWhen = (id) => id == op.operationId;
      await ctx.container.read(outboxProvider.future);

      await expectLater(
        ctx.container.read(outboxProvider.notifier).supersedeConflict(
              originalOperationId: op.operationId,
              resolutionVersion: '8',
            ),
        throwsA(isA<StateError>()),
      );

      final stored = await ctx.container.read(outboxProvider.future);
      expect(
          stored.map((o) => o.operationId),
          unorderedEquals([
            op.operationId,
            'op-new',
          ]));
    });
  });

  group('repeated submission stays idempotent', () {
    test('a second call after a completed resolution mints nothing new',
        () async {
      final op = conflictedOp();
      final ctx = containerWith(seeded: op);
      await ctx.container.read(outboxProvider.future);
      final notifier = ctx.container.read(outboxProvider.notifier);

      final first = await notifier.supersedeConflict(
          originalOperationId: op.operationId, resolutionVersion: '8');
      final second = await notifier.supersedeConflict(
          originalOperationId: op.operationId, resolutionVersion: '8');

      expect(second.operationId, first.operationId);
      final stored = await ctx.container.read(outboxProvider.future);
      expect(stored, hasLength(1));
    });

    test(
        'a retry after a failed retirement completes the retirement without '
        'minting a second replacement', () async {
      final op = conflictedOp();
      final ctx = containerWith(seeded: op);
      ctx.store.failRemoveWhen = (id) => id == op.operationId;
      await ctx.container.read(outboxProvider.future);
      final notifier = ctx.container.read(outboxProvider.notifier);

      await expectLater(
        notifier.supersedeConflict(
            originalOperationId: op.operationId, resolutionVersion: '8'),
        throwsA(isA<StateError>()),
      );
      // Both operations are on file after the first, failed attempt.
      expect(await ctx.container.read(outboxProvider.future), hasLength(2));

      ctx.store.failRemoveWhen = null;
      final resumed = await notifier.supersedeConflict(
          originalOperationId: op.operationId, resolutionVersion: '8');

      expect(resumed.operationId, 'op-new');
      final stored = await ctx.container.read(outboxProvider.future);
      expect(stored, hasLength(1));
      expect(stored.single.operationId, 'op-new');
    });

    test(
        'the replacement-recovery branch never retires an original that is '
        'no longer a conflict', () async {
      // A replacement already exists (`resolvesOperationId` set), and an
      // operation under the *original* id is still present too, but it has
      // moved on to some other state in the meantime — nothing should ever
      // retire it from inside the "recover a stuck retirement" branch.
      final replacement = PendingOperation.create(
        kind: 'shift.assign',
        entityType: 'shift',
        entityId: 'sh_1',
        resolvesOperationId: 'op-original',
        currentVersion: '8',
        idFactory: () => 'op-new',
      );
      final noLongerConflicted = conflictedOp().copyWith(
        state: SyncState.pending,
        clearLastProblemCode: true,
      );
      final store = _FailingOutboxStore(
        InMemoryOutboxStore(seed: [replacement, noLongerConflicted]),
      );
      final c = ProviderContainer(overrides: [
        outboxStoreProvider.overrideWithValue(store),
        newOperationIdProvider.overrideWithValue(_fixedNewId),
      ]);
      addTearDown(c.dispose);
      await c.read(outboxProvider.future);

      final second = await c.read(outboxProvider.notifier).supersedeConflict(
            originalOperationId: 'op-original',
            resolutionVersion: '8',
          );

      expect(second.operationId, 'op-new');
      expect(store.calls, isEmpty);
      final stored = await c.read(outboxProvider.future);
      expect(stored, hasLength(2));
      expect(
        stored.singleWhere((o) => o.operationId == 'op-original').state,
        SyncState.pending,
      );
    });
  });
}

String _fixedNewId() => 'op-new';
