import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mtm/core/network/api_client.dart';
import 'package:mtm/core/network/token_vault.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/storage/secure_store.dart';
import 'package:mtm/core/sync/http_sync_transport.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/sync_coordinator.dart';
import 'package:mtm/core/sync/sync_payload_store.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/features/auth/data/secure_auth_state_store.dart';
import 'package:mtm/features/inventory/data/http_inventory_repository.dart';
import 'package:mtm/features/inventory/domain/inventory_models.dart';

/// Decision D7 (Option 1) against the backend: the storage screen records a
/// movement through the repository — written online — and then enqueues the
/// same movement. These tests drive the real repository, outbox, coordinator
/// and HTTP transport over a fake server and prove that
///
///   (a) a movement is never sent twice, and
///   (b) a movement queued while its write failed is never silently dropped.

/// The `InventoryItem` the server answers a movement with.
Map<String, dynamic> _item({required int stock}) => {
      'id': 'i1',
      'detachmentId': 'd1',
      'name': 'شاش طبي',
      'unit': 'رول',
      'currentStock': stock,
      'minimum': 5,
      'level': 'ok',
      'unitsPerStrip': 1,
      'stripsPerCarton': 1,
      'preferredUnit': 'individual',
      'version': 2,
    };

/// A fake Leader API that counts what reached it.
class _Server {
  _Server({this.movementWorks = true, this.offline = false});

  bool movementWorks;
  bool offline;
  int movementPosts = 0;
  int syncPushes = 0;

  late final MockClient client = MockClient((request) async {
    if (offline) throw const SocketException('no route to host');
    final path = request.url.path;
    if (request.method == 'POST' &&
        path == '/api/v1/inventory-items/i1/movements') {
      movementPosts++;
      return movementWorks
          ? _json(200, _item(stock: 9))
          : _json(500, {
              'error': {'code': 'server', 'message': 'boom'},
            });
    }
    if (request.method == 'POST' && path == '/api/v1/sync/push') {
      syncPushes++;
      final op = ((jsonDecode(request.body) as Map)['operations'] as List).single
          as Map;
      return _json(200, {
        'results': [
          {
            'operationId': op['operationId'],
            'kind': op['kind'],
            'status': 'applied',
            'httpStatus': 200,
            'terminal': true,
          },
        ],
        'serverTime': DateTime.now().toUtc().toIso8601String(),
      });
    }
    return _json(404, {
      'error': {'code': 'not_found', 'message': 'no route'},
    });
  });

  static http.Response _json(int status, Object body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}

typedef _Rig = ({
  ProviderContainer container,
  HttpInventoryRepository inventory,
  InMemoryOutboxStore store,
});

_Rig _rig(_Server server) {
  final payloads = InMemorySyncPayloadStore();
  final api = ApiClient(
    vault: TokenVault(SecureAuthStateStore(InMemorySecureStore())),
    origin: 'http://leader.test',
    client: server.client,
  );
  final store = InMemoryOutboxStore();
  final container = ProviderContainer(overrides: [
    outboxStoreProvider.overrideWithValue(store),
    syncTransportProvider.overrideWithValue(HttpSyncTransport(api, payloads)),
  ]);
  addTearDown(container.dispose);
  return (
    container: container,
    inventory: HttpInventoryRepository(api, payloads),
    store: store,
  );
}

/// Exactly what `detachment_storage_tab.dart` does after a movement.
Future<void> _enqueueLikeTheScreen(ProviderContainer c) => c
    .read(outboxProvider.notifier)
    .enqueue(
        kind: 'inventory.movement.add',
        entityType: 'inventory_item',
        entityId: 'i1');

Future<void> _syncNow(ProviderContainer c, SyncTrigger trigger) =>
    c.read(syncCoordinatorProvider.notifier).syncNow(trigger: trigger);

Future<Result<InventoryItem>> _recordMovement(HttpInventoryRepository repo) =>
    repo.addMovement(
      itemId: 'i1',
      direction: MovementDirection.outflow,
      quantity: 1,
      reason: 'صرف',
      source: 'mobile_app',
    );

void main() {
  test('(a) a movement written online and then queued is sent exactly once',
      () async {
    final server = _Server();
    final rig = _rig(server);

    final result = await _recordMovement(rig.inventory);
    expect(result.isSuccess, isTrue);
    await _enqueueLikeTheScreen(rig.container);

    // Auto Sync, then a manual tap, then another auto run.
    await _syncNow(rig.container, SyncTrigger.auto);
    await _syncNow(rig.container, SyncTrigger.manual);
    await _syncNow(rig.container, SyncTrigger.auto);

    expect(server.movementPosts, 1, reason: 'the online write is the only one');
    expect(server.syncPushes, 0,
        reason: 'the queued copy is recognised as applied, never replayed');
    expect(await rig.store.readAll(), isEmpty,
        reason: 'the outbox entry is settled, not left pending');
  });

  test('(a) two movements on the same item are each sent once', () async {
    final server = _Server();
    final rig = _rig(server);

    for (var i = 0; i < 2; i++) {
      expect((await _recordMovement(rig.inventory)).isSuccess, isTrue);
      await _enqueueLikeTheScreen(rig.container);
    }
    await _syncNow(rig.container, SyncTrigger.manual);

    expect(server.movementPosts, 2);
    expect(server.syncPushes, 0);
    expect(await rig.store.readAll(), isEmpty);
  });

  test('(b) a movement queued while its write failed is kept, not dropped',
      () async {
    final server = _Server(movementWorks: false);
    final rig = _rig(server);

    final result = await _recordMovement(rig.inventory);
    expect(result, isA<Failure<InventoryItem>>());
    // The screen only enqueues on success; queue it anyway, the worst case.
    await _enqueueLikeTheScreen(rig.container);

    await _syncNow(rig.container, SyncTrigger.auto);
    await _syncNow(rig.container, SyncTrigger.manual);

    final rows = await rig.store.readAll();
    expect(rows, hasLength(1), reason: 'never silently removed');
    expect(rows.single.state, SyncState.failed);
    expect(rows.single.lastProblemCode, HttpSyncTransport.payloadMissingCode);
    expect(server.syncPushes, 0,
        reason: 'nothing is invented and sent in its place');
  });

  test('(b) an offline write leaves no receipt, so its queued copy stays',
      () async {
    final server = _Server(offline: true);
    final rig = _rig(server);

    expect(await _recordMovement(rig.inventory), isA<Offline<InventoryItem>>());
    await _enqueueLikeTheScreen(rig.container);

    // Back online: the queued copy still cannot be confirmed as applied.
    server.offline = false;
    await _syncNow(rig.container, SyncTrigger.manual);

    final rows = await rig.store.readAll();
    expect(rows, hasLength(1));
    expect(rows.single.state, SyncState.failed);
    expect(server.movementPosts, 0);
  });

  test('a stored payload replays through /sync/push once, by its operation id',
      () async {
    final server = _Server();
    final rig = _rig(server);
    final payloads = InMemorySyncPayloadStore();
    final transport = HttpSyncTransport(
      ApiClient(
        vault: TokenVault(SecureAuthStateStore(InMemorySecureStore())),
        origin: 'http://leader.test',
        client: server.client,
      ),
      payloads,
    );
    final c = ProviderContainer(overrides: [
      outboxStoreProvider.overrideWithValue(rig.store),
      syncTransportProvider.overrideWithValue(transport),
    ]);
    addTearDown(c.dispose);

    final op = await c.read(outboxProvider.notifier).enqueue(
        kind: 'inventory.movement.add',
        entityType: 'inventory_item',
        entityId: 'i1');
    await payloads.put(op.operationId, {
      'itemId': 'i1',
      'direction': 'inflow',
      'quantity': 2,
      'reason': 'توريد',
    });

    await _syncNow(c, SyncTrigger.manual);
    await _syncNow(c, SyncTrigger.manual);

    expect(server.syncPushes, 1);
    expect(await rig.store.readAll(), isEmpty);
    expect(await payloads.read(op.operationId), isNull);
  });
}
