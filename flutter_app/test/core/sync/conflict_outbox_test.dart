import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_conflict_classifier.dart';
import 'package:mtm/core/sync/sync_coordinator.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/core/sync/sync_transport.dart';

/// Task 2 — outbox conflict state. Extends the Task 1-era
/// `local_first_sync_test.dart` (left untouched) with the
/// `SyncState.conflict` transition, the retry-skip rule, the review count,
/// and the useLocal/useCurrent/reviewLater seam. See prompt §10 for the
/// numbered requirements each test below maps to.
class _FakeTransport implements SyncTransport {
  _FakeTransport(this.answer);
  Result<void> Function(PendingOperation op) answer;
  final List<String> pushedKeys = [];
  int pushes = 0;

  @override
  Future<Result<void>> push(PendingOperation operation) async {
    pushes++;
    pushedKeys.add(operation.idempotencyKey);
    return answer(operation);
  }
}

/// A code no real backend will ever send — the test's own private
/// vocabulary, never asserted as production behaviour.
const _staleWriteTestCode = 'test_only_stale_write';
bool _testClassifier(String? code) => code == _staleWriteTestCode;

ProviderContainer _container({
  required OutboxStore store,
  required SyncTransport transport,
  SyncConflictClassifier? classifier,
}) {
  final c = ProviderContainer(overrides: [
    outboxStoreProvider.overrideWithValue(store),
    syncTransportProvider.overrideWithValue(transport),
    if (classifier != null)
      syncConflictClassifierProvider.overrideWithValue(classifier),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('1+2. a conflict-classified failure preserves the original operation',
      () async {
    final store = InMemoryOutboxStore();
    final transport = _FakeTransport(
      (_) => const Failure<void>('stale', code: _staleWriteTestCode),
    );
    final c = _container(
        store: store, transport: transport, classifier: _testClassifier);

    final op = await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'shift.assign', entityId: 'sh_1');

    await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.auto);

    final stored = (await store.readAll()).single;
    expect(stored.operationId, op.operationId,
        reason: 'identity must not change when a conflict is detected');
    expect(stored.idempotencyKey, op.idempotencyKey);
    expect(stored.kind, op.kind);
    expect(stored.entityId, op.entityId);
  });

  test('3. a conflict is not treated as synced', () async {
    final store = InMemoryOutboxStore();
    final transport = _FakeTransport(
      (_) => const Failure<void>('stale', code: _staleWriteTestCode),
    );
    final c = _container(
        store: store, transport: transport, classifier: _testClassifier);
    await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'shift.assign', entityId: 'sh_1');

    await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.auto);

    final stored = (await store.readAll()).single;
    expect(stored.state, SyncState.conflict);
    expect(stored.state, isNot(SyncState.synced));
    expect(stored.isUnsynced, isTrue);
  });

  test('9. a conflicted operation is not retried indefinitely', () async {
    final store = InMemoryOutboxStore();
    final transport = _FakeTransport(
      (_) => const Failure<void>('stale', code: _staleWriteTestCode),
    );
    final c = _container(
        store: store, transport: transport, classifier: _testClassifier);
    await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'shift.assign', entityId: 'sh_1');

    final notifier = c.read(syncCoordinatorProvider.notifier);
    await notifier.syncNow(trigger: SyncTrigger.auto);
    await notifier.syncNow(trigger: SyncTrigger.manual);
    await notifier.syncNow(trigger: SyncTrigger.auto);

    expect(transport.pushes, 1,
        reason: 'classified once, then skipped by every later run');
  });

  test(
      '6. conflict/review count is accurate and distinct from the sync-pending count',
      () async {
    final store = InMemoryOutboxStore();
    final transport = _FakeTransport((op) => op.entityId == 'conflicted'
        ? const Failure<void>('stale', code: _staleWriteTestCode)
        : const Offline<void>());
    final c = _container(
        store: store, transport: transport, classifier: _testClassifier);

    await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'shift.assign', entityId: 'conflicted');
    await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'inventory.movement.add', entityId: 'still-pending');

    await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.auto);

    expect(c.read(conflictOperationsCountProvider), 1);
    expect(c.read(pendingOperationsCountProvider), 1,
        reason: 'the ordinary pending count must not double-count the '
            'conflicted operation');
  });

  test('8. generic temporary failures keep their pre-Task-2 behaviour',
      () async {
    final store = InMemoryOutboxStore();
    final transport = _FakeTransport(
      (_) => const Failure<void>('some_future_code'),
    );
    // No classifier override — the shipped default never classifies a
    // conflict, so this must behave exactly as before Task 2.
    final c = _container(store: store, transport: transport);
    await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'inventory.movement.add', entityId: 'i1');

    final notifier = c.read(syncCoordinatorProvider.notifier);
    await notifier.syncNow(trigger: SyncTrigger.auto);
    await notifier.syncNow(trigger: SyncTrigger.manual);

    expect(transport.pushes, 2, reason: 'a plain failure keeps retrying');
    final stored = (await store.readAll()).single;
    expect(stored.state, SyncState.failed);
    expect(c.read(conflictOperationsCountProvider), 0);
  });

  test('useLocal (requeueAfterConflict) retries with the same identity',
      () async {
    final store = InMemoryOutboxStore();
    var conflictNow = true;
    final transport = _FakeTransport((_) => conflictNow
        ? const Failure<void>('stale', code: _staleWriteTestCode)
        : const Success<void>(null));
    final c = _container(
        store: store, transport: transport, classifier: _testClassifier);
    final op = await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'shift.assign', entityId: 'sh_1');

    await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.auto);
    expect((await store.readAll()).single.state, SyncState.conflict);

    await c.read(outboxProvider.notifier).requeueAfterConflict(op.operationId);
    final requeued = (await store.readAll()).single;
    expect(requeued.state, SyncState.pending);
    expect(requeued.operationId, op.operationId);
    expect(requeued.idempotencyKey, op.idempotencyKey);

    conflictNow = false;
    final summary = await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.manual);

    expect(summary.outcome, SyncRunOutcome.allSynced);
    expect(transport.pushedKeys, everyElement(op.idempotencyKey));
    expect(await store.readAll(), isEmpty);
  });

  test(
      'useCurrent (discardConflict) drops the write without touching the '
      'transport again', () async {
    final store = InMemoryOutboxStore();
    final transport = _FakeTransport(
      (_) => const Failure<void>('stale', code: _staleWriteTestCode),
    );
    final c = _container(
        store: store, transport: transport, classifier: _testClassifier);
    final op = await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'shift.assign', entityId: 'sh_1');

    await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.auto);
    expect(transport.pushes, 1);

    await c.read(outboxProvider.notifier).discardConflict(op.operationId);

    expect(await store.readAll(), isEmpty);
    expect(transport.pushes, 1,
        reason: 'discarding a conflict never contacts the transport');
  });

  test('reviewLater (doing nothing) preserves the conflict across more runs',
      () async {
    final store = InMemoryOutboxStore();
    final transport = _FakeTransport(
      (_) => const Failure<void>('stale', code: _staleWriteTestCode),
    );
    final c = _container(
        store: store, transport: transport, classifier: _testClassifier);
    final op = await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'shift.assign', entityId: 'sh_1');

    await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.auto);
    // "reviewLater" is deliberately not a method call — calling nothing is
    // the behaviour under test.
    await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.manual);

    final stored = (await store.readAll()).single;
    expect(stored.state, SyncState.conflict);
    expect(stored.operationId, op.operationId);
    expect(stored.idempotencyKey, op.idempotencyKey);
    expect(transport.pushes, 1);
  });

  test('a run outcome distinguishes needsReview from a generic failure',
      () async {
    final store = InMemoryOutboxStore();
    final transport = _FakeTransport(
      (_) => const Failure<void>('stale', code: _staleWriteTestCode),
    );
    final c = _container(
        store: store, transport: transport, classifier: _testClassifier);
    await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'shift.assign', entityId: 'sh_1');

    final summary = await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.auto);

    expect(summary.outcome, SyncRunOutcome.needsReview);
  });
}
