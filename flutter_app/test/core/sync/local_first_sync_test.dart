import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_coordinator.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/core/sync/sync_transport.dart';

/// A transport whose answer the test controls. Records every push so we can
/// assert the SAME operation (same idempotency key) was retried, not a new
/// one.
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

ProviderContainer _container({
  required OutboxStore store,
  required SyncTransport transport,
  String Function()? ids,
}) {
  final c = ProviderContainer(overrides: [
    outboxStoreProvider.overrideWithValue(store),
    syncTransportProvider.overrideWithValue(transport),
    if (ids != null) newOperationIdProvider.overrideWithValue(ids),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('1. a write is registered locally with no server involved', () async {
    final store = InMemoryOutboxStore();
    final c = _container(
        store: store,
        transport: _FakeTransport((_) {
          fail('the transport must not be touched by a local write');
        }));

    final op = await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'inventory.movement.add', entityId: 'i1');

    expect(op.state, SyncState.pending);
    expect(c.read(pendingOperationsCountProvider), 1);
    // It is on disk (the store), not just in memory.
    expect((await store.readAll()).single.operationId, op.operationId);
  });

  test('2. a retry reuses the same idempotency identity (auto + manual)',
      () async {
    final store = InMemoryOutboxStore();
    final transport = _FakeTransport((_) => const Offline<void>());
    final c = _container(store: store, transport: transport);

    final op = await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'shift.attendance.mark', entityId: 'sh_1');

    await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.auto);
    await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.manual);
    await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.auto);

    expect(transport.pushes, 3);
    expect(transport.pushedKeys, everyElement(op.idempotencyKey));
    // Still exactly one operation — no key was minted per attempt.
    expect((await store.readAll()).length, 1);
    expect((await store.readAll()).single.idempotencyKey, op.idempotencyKey);
    expect((await store.readAll()).single.attemptCount, 3);
  });

  test('3 + 4 + 5. Auto and Manual drain the same op; Manual never dupes',
      () async {
    final store = InMemoryOutboxStore();
    // First attempt (auto) is offline; the manual retry succeeds.
    var online = false;
    final transport = _FakeTransport(
      (_) => online ? const Success<void>(null) : const Offline<void>(),
    );
    final c = _container(store: store, transport: transport);

    final op = await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'inventory.movement.add', entityId: 'i1');

    await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.auto);
    expect(c.read(pendingOperationsCountProvider), 1,
        reason: 'offline: the op stays pending, not lost');

    online = true;
    final summary = await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.manual);

    expect(summary.outcome, SyncRunOutcome.allSynced);
    expect(summary.synced, 1);
    expect(transport.pushedKeys, everyElement(op.idempotencyKey));
    expect(await store.readAll(), isEmpty,
        reason: 'a synced op leaves the outbox');
    expect(c.read(pendingOperationsCountProvider), 0);
  });

  test('6. app restart preserves the operation identity and state', () async {
    final store = InMemoryOutboxStore(); // one store == one device

    // Run one: enqueue, fail to sync (offline).
    final first = _container(
      store: store,
      transport: _FakeTransport((_) => const Offline<void>()),
    );
    final op = await first
        .read(outboxProvider.notifier)
        .enqueue(kind: 'shift.attendance.mark', entityId: 'sh_9');
    await first
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.auto);
    first.dispose();

    // Run two: fresh container over the same store — a relaunch.
    final second = _container(
      store: store,
      transport: _FakeTransport((_) => const Success<void>(null)),
    );
    final restored = await second.read(outboxProvider.future);
    expect(restored.single.operationId, op.operationId);
    expect(restored.single.idempotencyKey, op.idempotencyKey);
    expect(restored.single.isUnsynced, isTrue);

    // And the retry after restart still carries the original key.
    final t = second.read(syncTransportProvider) as _FakeTransport;
    await second
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.auto);
    expect(t.pushedKeys.single, op.idempotencyKey);
    expect(await store.readAll(), isEmpty);
  });

  test('7. a connectivity blip does not become a user-visible failure',
      () async {
    final store = InMemoryOutboxStore();
    final c = _container(
      store: store,
      transport: _FakeTransport((_) => const Offline<void>()),
    );
    await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'inventory.movement.add', entityId: 'i1');

    final summary = await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.auto);

    // Offline is its own outcome, distinct from `failed`.
    expect(summary.outcome, SyncRunOutcome.offline);
    final op = (await store.readAll()).single;
    expect(op.state, SyncState.failed, reason: 'still owed, will retry');
    expect(op.lastProblemCode, 'offline');
    // The local data is untouched and still counted as pending, not dropped.
    expect(c.read(pendingOperationsCountProvider), 1);
  });

  test('8 + 9. an unknown backend problem passes through as a safe code only',
      () async {
    final store = InMemoryOutboxStore();
    final c = _container(
      store: store,
      transport: _FakeTransport(
        (_) => const Failure<void>(
          'SQLSTATE 23505 duplicate key; token=Bearer abc.def',
          code: 'some_future_code',
        ),
      ),
    );
    await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'inventory.movement.add', entityId: 'i1');

    final summary = await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.manual);

    expect(summary.outcome, SyncRunOutcome.failed);
    final op = (await store.readAll()).single;
    // Only the wire CODE is retained — never the raw server detail text.
    expect(op.lastProblemCode, 'some_future_code');
    expect(op.toJson().toString(), isNot(contains('Bearer')));
    expect(op.toJson().toString(), isNot(contains('SQLSTATE')));
    expect(op.isUnsynced, isTrue);
  });

  test('re-entrant syncNow calls join one run — a write never fans out',
      () async {
    final store = InMemoryOutboxStore();
    final transport = _FakeTransport((_) => const Success<void>(null));
    final c = _container(store: store, transport: transport);
    await c
        .read(outboxProvider.notifier)
        .enqueue(kind: 'inventory.movement.add', entityId: 'i1');

    final notifier = c.read(syncCoordinatorProvider.notifier);
    await Future.wait([
      notifier.syncNow(trigger: SyncTrigger.auto),
      notifier.syncNow(trigger: SyncTrigger.manual),
      notifier.syncNow(trigger: SyncTrigger.auto),
    ]);

    expect(transport.pushes, 1, reason: 'one operation, one push');
  });

  test('a sync run with nothing pending is a no-op', () async {
    final store = InMemoryOutboxStore();
    final transport = _FakeTransport((_) => fail('nothing to push'));
    final c = _container(store: store, transport: transport);

    final summary = await c
        .read(syncCoordinatorProvider.notifier)
        .syncNow(trigger: SyncTrigger.auto);

    expect(summary.outcome, SyncRunOutcome.nothingPending);
    expect(transport.pushes, 0);
  });
}
