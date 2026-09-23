import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/features/inventory/domain/inventory_models.dart';
import 'package:mtm/features/inventory/domain/inventory_repository.dart';
import 'package:mtm/features/notification/data/mock_notification_repository.dart';
import 'package:mtm/features/notification/data/notification_providers.dart';
import 'package:mtm/features/notification/domain/notification_models.dart';
import 'package:mtm/features/notification/domain/notification_read_store.dart';
import 'package:mtm/features/notification/domain/notification_repository.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/shift/domain/shift_repository.dart';
import 'package:mtm/features/tenant_feature/data/tenant_feature_providers.dart';
import 'package:mtm/l10n/strings.dart';

/// The feed as the screen and the badge actually see it: two halves merged,
/// filtered by grants, stamped with read state, and degrading the way the
/// designed states expect. None of this is reproducible by hand — it needs a
/// repository that fails, a device with no connectivity, a read store that
/// refuses a write, and an outbox that changes underneath.

const _det = 'd1';
const _operator = Capabilities(scoped: {_det: Cap.scoped});
const _volunteer = Capabilities(
  scoped: {
    _det: {Cap.detachmentView},
  },
);

final _now = DateTime(2026, 9, 5, 10);

AppNotification _row(
  String id, {
  NotificationKind kind = NotificationKind.stockLow,
  bool isRead = false,
}) =>
    AppNotification(
      id: id,
      kind: kind,
      occurredAt: _now,
      target: const StorageTarget(detachmentId: _det, itemId: 'i_1'),
      isRead: isRead,
    );

PendingOperation _op(String id, SyncState state) => PendingOperation.create(
      kind: 'inventory.movement.add',
      entityType: 'inventory',
      entityId: 'i_1',
      idFactory: () => id,
      clock: () => _now,
    ).copyWith(state: state, lastAttemptAt: _now, attemptCount: 1);

class _FakeRepository implements NotificationRepository {
  _FakeRepository(this.answer);

  Result<List<AppNotification>> answer;
  int calls = 0;

  @override
  Future<Result<List<AppNotification>>> feed(String detachmentId) async {
    calls++;
    return answer;
  }
}

/// Counts writes so a duplicate tap can be told apart from a real one, and
/// can be made to fail so the failed-mark path is reachable.
class _RecordingReadStore implements NotificationReadStore {
  final Set<String> _read = {};
  final List<List<String>> writes = [];
  bool fails = false;

  @override
  Future<Set<String>> readIds() async => Set<String>.of(_read);

  @override
  Future<void> markRead(Iterable<String> ids) async {
    if (fails) throw StateError('simulated read-store failure');
    writes.add(ids.toList()..sort());
    _read.addAll(ids);
  }
}

class _FakeShifts extends Fake implements ShiftRepository {
  _FakeShifts(this.answer);
  Result<List<Shift>> answer;

  @override
  Future<Result<List<Shift>>> listForRange(
    String detachmentId,
    DateTime from,
    DateTime to,
  ) async =>
      answer;
}

class _FakeInventory extends Fake implements InventoryRepository {
  _FakeInventory(this.answer);
  Result<List<InventoryItem>> answer;

  @override
  Future<Result<List<InventoryItem>>> listForDetachment(
    String detachmentId,
  ) async =>
      answer;
}

/// A container wired the way the app wires it, minus the network.
Future<({ProviderContainer container, _RecordingReadStore store})> _boot({
  Result<List<AppNotification>> repository = const Success([]),
  List<PendingOperation> outbox = const [],
  Capabilities capabilities = _operator,
  _RecordingReadStore? store,
}) async {
  final readStore = store ?? _RecordingReadStore();
  final container = ProviderContainer(overrides: [
    capabilitiesProvider.overrideWithValue(capabilities),
    tenantFeatureAvailableProvider.overrideWith((ref, key) => true),
    outboxStoreProvider.overrideWithValue(InMemoryOutboxStore(seed: outbox)),
    notificationReadStoreProvider.overrideWithValue(readStore),
    notificationRepositoryProvider
        .overrideWithValue(_FakeRepository(repository)),
  ]);
  addTearDown(container.dispose);

  // Both halves of the feed arrive asynchronously. Settle them first so a
  // test asserts on the answer rather than on the order they landed in.
  await container.read(outboxProvider.future);
  await container.read(notificationReadIdsProvider.future);
  return (container: container, store: readStore);
}

/// The merged feed as the screen sees it, after the record half has landed.
/// The source is awaited; the merge itself is synchronous.
Future<Result<List<AppNotification>>> _load(ProviderContainer container) async {
  await container.read(notificationSourceProvider(_det).future);
  return _feed(container);
}

Result<List<AppNotification>> _feed(ProviderContainer container) =>
    container.read(notificationFeedProvider(_det)).value!;

List<AppNotification> _rows(Result<List<AppNotification>> result) =>
    result.when(
      success: (data, {stale = false}) => data,
      failure: (_, __) => const [],
      offline: (cached) => cached ?? const [],
    );

void main() {
  test('the feed merges the record half with the outbox half', () async {
    final (:container, :store) = await _boot(
      repository: Success([_row('stockLow:i_1')]),
      outbox: [_op('op1', SyncState.conflict)],
    );

    final rows = _rows(await _load(container));

    expect(
      {for (final row in rows) row.kind},
      {NotificationKind.stockLow, NotificationKind.syncConflict},
    );
    expect(container.read(unreadNotificationCountProvider(_det)), 2);
  });

  test('marking one row read moves the badge by exactly one', () async {
    final (:container, :store) = await _boot(
      repository: Success([_row('a'), _row('b')]),
    );
    await container.read(notificationSourceProvider(_det).future);
    expect(container.read(unreadNotificationCountProvider(_det)), 2);

    final result = await container
        .read(notificationReadIdsProvider.notifier)
        .markRead(['a']);
    await container.read(notificationSourceProvider(_det).future);

    expect(result.isSuccess, isTrue);
    expect(container.read(unreadNotificationCountProvider(_det)), 1);
    final rows = _rows(_feed(container));
    expect(rows.firstWhere((r) => r.id == 'a').isRead, isTrue);
    expect(rows.firstWhere((r) => r.id == 'b').isRead, isFalse);
  });

  test('marking all read empties the badge in one write', () async {
    final (:container, :store) = await _boot(
      repository: Success([_row('a'), _row('b')]),
      outbox: [_op('op1', SyncState.failed)],
    );
    final rows = _rows(await _load(container));

    await container
        .read(notificationReadIdsProvider.notifier)
        .markRead([for (final row in rows) row.id]);
    await container.read(notificationSourceProvider(_det).future);

    expect(container.read(unreadNotificationCountProvider(_det)), 0);
    expect(store.writes.length, 1, reason: 'one write, not one per row');
  });

  test('tapping the same row twice writes read state once', () async {
    final (:container, :store) = await _boot(
      repository: Success([_row('a')]),
    );
    await container.read(notificationSourceProvider(_det).future);

    final notifier = container.read(notificationReadIdsProvider.notifier);
    final first = await notifier.markRead(['a']);
    final second = await notifier.markRead(['a']);

    expect(first, isA<Success<int>>());
    expect((first as Success<int>).data, 1);
    expect((second as Success<int>).data, 0, reason: 'nothing changed');
    expect(store.writes, [
      ['a']
    ]);
  });

  test('a read store that refuses the write leaves the badge alone', () async {
    final store = _RecordingReadStore()..fails = true;
    final (container: container, store: _) = await _boot(
      repository: Success([_row('a')]),
      store: store,
    );
    await container.read(notificationSourceProvider(_det).future);

    final result = await container
        .read(notificationReadIdsProvider.notifier)
        .markRead(['a']);
    await container.read(notificationSourceProvider(_det).future);

    expect(result, isA<Failure<int>>());
    expect((result as Failure<int>).message, S.notificationsMarkReadFailed);
    // Nothing marked locally: a badge that silently disagrees with what was
    // stored is worse than a retry.
    expect(container.read(unreadNotificationCountProvider(_det)), 1);
    expect(store.writes, isEmpty);
  });

  test('a repository failure is a failure, and the badge promises nothing',
      () async {
    final (:container, :store) = await _boot(
      repository: const Failure('boom', code: 'internal'),
    );

    final result = await _load(container);

    expect(result, isA<Failure<List<AppNotification>>>());
    expect(container.read(unreadNotificationCountProvider(_det)), 0);
  });

  test('offline with a cached copy still counts and still shows', () async {
    final (:container, :store) = await _boot(
      repository: Offline(cached: [_row('a')]),
    );

    final result = await _load(container);

    expect(result, isA<Offline<List<AppNotification>>>());
    expect(_rows(result).single.id, 'a');
    expect(container.read(unreadNotificationCountProvider(_det)), 1);
  });

  test('offline with nothing cached still shows the user their own work',
      () async {
    // The sync half is local. Hiding it because the network is down is
    // exactly when the user most needs to see it.
    final (:container, :store) = await _boot(
      repository: const Offline(),
      outbox: [_op('op1', SyncState.failed)],
    );

    final result = await _load(container);

    expect(_rows(result).single.kind, NotificationKind.syncFailed);
    expect(container.read(unreadNotificationCountProvider(_det)), 1);
  });

  test('offline with nothing at all falls through to the no-cache state',
      () async {
    final (:container, :store) = await _boot(repository: const Offline());

    final result = await _load(container);

    expect(result, isA<Offline<List<AppNotification>>>());
    expect(
      (result as Offline<List<AppNotification>>).cached,
      isNull,
      reason: 'the shared "offline, no cached copy" state, not an empty list',
    );
    expect(container.read(unreadNotificationCountProvider(_det)), 0);
  });

  test('the feed is filtered by the session\'s grants', () async {
    final (:container, :store) = await _boot(
      repository: Success([_row('stockLow:i_1')]),
      outbox: [_op('op1', SyncState.failed)],
      capabilities: _volunteer,
    );

    final rows = _rows(await _load(container));

    expect({for (final row in rows) row.kind}, {NotificationKind.syncFailed});
  });

  test('a sync run that changes the outbox changes the badge', () async {
    final (:container, :store) = await _boot(
      outbox: [_op('op1', SyncState.failed)],
    );
    await container.read(notificationSourceProvider(_det).future);
    expect(container.read(unreadNotificationCountProvider(_det)), 1);

    // The operation is accepted on a later run and leaves the outbox.
    await container.read(outboxProvider.notifier).markSynced('op1');
    await container.read(notificationSourceProvider(_det).future);

    expect(container.read(unreadNotificationCountProvider(_det)), 0);
  });

  group('the composed repository', () {
    Future<Result<List<AppNotification>>> feed({
      required Result<List<Shift>> shifts,
      required Result<List<InventoryItem>> items,
    }) =>
        MockNotificationRepository(
          shifts: _FakeShifts(shifts),
          inventory: _FakeInventory(items),
          clock: () => _now,
        ).feed(_det);

    test('one unreachable section degrades, it does not take the feed down',
        () async {
      final result = await feed(
        shifts: const Failure('boom', code: 'internal'),
        items: const Success([
          InventoryItem(
            id: 'i_1',
            detachmentId: _det,
            name: 'شاش',
            unit: 'قطعة',
            currentStock: 0,
            minimum: 5,
            expiresOn: null,
            level: StockLevel.empty,
          ),
        ]),
      );

      expect(_rows(result).single.kind, NotificationKind.stockDepleted);
    });

    test('both sections unreachable is the feed\'s own failure', () async {
      final result = await feed(
        shifts: const Failure('boom', code: 'internal'),
        items: const Failure('boom', code: 'internal'),
      );

      expect(result, isA<Failure<List<AppNotification>>>());
    });

    test('offline outranks failure when neither section could be read',
        () async {
      // "No connectivity" and "the server broke" say very different things to
      // the person holding the phone.
      final result = await feed(
        shifts: const Offline(),
        items: const Failure('boom', code: 'internal'),
      );

      expect(result, isA<Offline<List<AppNotification>>>());
    });
  });
}
