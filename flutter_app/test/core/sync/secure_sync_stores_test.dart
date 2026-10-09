import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/storage/secure_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/secure_sync_stores.dart';
import 'package:mtm/core/sync/sync_state.dart';

/// The durable outbox: it survives a restart, keeps one queue per account,
/// and never loses a write to two overlapping changes.
PendingOperation _op(String id, {int minute = 0}) => PendingOperation(
      operationId: id,
      idempotencyKey: 'key-$id',
      kind: 'inventory.movement.add',
      createdAt: DateTime.utc(2026, 10, 9, 9, minute),
      entityType: 'inventory_item',
      entityId: 'item-$id',
    );

void main() {
  late InMemorySecureStore device;

  setUp(() => device = InMemorySecureStore());

  group('outbox', () {
    test('a queued write survives an app restart, oldest first', () async {
      final first = SecureOutboxStore(device, accountId: 'acc-1');
      await first.upsert(_op('b', minute: 5));
      await first.upsert(_op('a', minute: 1));

      // A new process over the same phone.
      final relaunched = SecureOutboxStore(device, accountId: 'acc-1');
      final rows = await relaunched.readAll();
      expect(rows.map((o) => o.operationId), ['a', 'b']);
      expect(rows.first.idempotencyKey, 'key-a',
          reason: 'the same identity is replayed after a restart');
    });

    test('state changes and removal are kept too', () async {
      final store = SecureOutboxStore(device, accountId: 'acc-1');
      await store.upsert(_op('a'));
      await store.upsert(_op('a').copyWith(
        state: SyncState.failed,
        attemptCount: 2,
        lastProblemCode: 'network',
      ));
      var rows = await SecureOutboxStore(device, accountId: 'acc-1').readAll();
      expect(rows.single.state, SyncState.failed);
      expect(rows.single.attemptCount, 2);

      await store.remove('a');
      rows = await SecureOutboxStore(device, accountId: 'acc-1').readAll();
      expect(rows, isEmpty);
      expect(device.values.containsKey(SecureSyncKeys.outbox('acc-1')), isFalse,
          reason: 'an empty queue leaves nothing behind');
    });

    test("one account never sees another account's queue", () async {
      await SecureOutboxStore(device, accountId: 'acc-1').upsert(_op('a'));
      expect(await SecureOutboxStore(device, accountId: 'acc-2').readAll(),
          isEmpty);
      expect(
          (await SecureOutboxStore(device, accountId: 'acc-1').readAll())
              .single
              .operationId,
          'a');
    });

    test('two overlapping upserts both land', () async {
      final store = SecureOutboxStore(device, accountId: 'acc-1');
      await Future.wait([
        for (var i = 0; i < 10; i++) store.upsert(_op('op$i', minute: i)),
      ]);
      final rows = await SecureOutboxStore(device, accountId: 'acc-1').readAll();
      expect(rows, hasLength(10));
    });

    test('a corrupt record reads as an empty queue, not a crash', () async {
      await device.writeString(SecureSyncKeys.outbox('acc-1'), '{not json');
      expect(await SecureOutboxStore(device, accountId: 'acc-1').readAll(),
          isEmpty);
    });

    test('is stored under the persisted mtm.* convention', () {
      expect(SecureSyncKeys.outbox('acc-1'), startsWith('mtm.sync.'));
      expect(SecureSyncKeys.payloads('acc-1'), startsWith('mtm.sync.'));
    });
  });

  group('payloads and receipts', () {
    test('a payload and its version survive a restart', () async {
      await SecureSyncPayloadStore(device, accountId: 'acc-1')
          .put('op-1', {'quantity': 3, 'note': 'شاش'}, version: 4);

      final stored =
          await SecureSyncPayloadStore(device, accountId: 'acc-1').read('op-1');
      expect(stored?.payload, {'quantity': 3, 'note': 'شاش'});
      expect(stored?.version, 4);
      expect(
          await SecureSyncPayloadStore(device, accountId: 'acc-2').read('op-1'),
          isNull);
    });

    test('a receipt is spent exactly once, across a restart', () async {
      await SecureSyncPayloadStore(device, accountId: 'acc-1')
          .recordApplied('inventory.movement.add', 'item-1');

      final relaunched = SecureSyncPayloadStore(device, accountId: 'acc-1');
      expect(
          await relaunched.consumeApplied('inventory.movement.add', 'item-1'),
          isTrue);
      expect(
          await SecureSyncPayloadStore(device, accountId: 'acc-1')
              .consumeApplied('inventory.movement.add', 'item-1'),
          isFalse);
    });

    test('removing the last payload leaves nothing behind', () async {
      final store = SecureSyncPayloadStore(device, accountId: 'acc-1');
      await store.put('op-1', {'a': 1});
      await store.remove('op-1');
      expect(device.values.containsKey(SecureSyncKeys.payloads('acc-1')),
          isFalse);
    });

    test('the record is JSON a future store can migrate', () async {
      await SecureSyncPayloadStore(device, accountId: 'acc-1')
          .put('op-1', {'a': 1});
      final raw = jsonDecode(device.values[SecureSyncKeys.payloads('acc-1')]!)
          as Map<String, dynamic>;
      expect(raw.keys, containsAll(['payloads', 'receipts']));
    });
  });
}
