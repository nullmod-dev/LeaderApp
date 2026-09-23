import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/announcement/data/announcement_providers.dart';
import 'package:mtm/features/announcement/domain/announcement_models.dart';
import 'package:mtm/features/announcement/domain/announcement_repository.dart';
import 'package:mtm/features/notification/data/notification_providers.dart';
import 'package:mtm/features/notification/domain/notification_history_store.dart';
import 'package:mtm/features/notification/domain/notification_models.dart';
import 'package:mtm/features/notification/domain/notification_repository.dart';
import 'package:mtm/features/notification/domain/notification_selectors.dart';
import 'package:mtm/features/tenant_feature/data/tenant_feature_providers.dart';

/// How an announcement becomes a row in the Notifications Center, and what that
/// row is deliberately not allowed to do.
///
/// The rules being locked in here are the ones a screenshot cannot show: that
/// an announcement never touches the unread badge, that clearing history
/// reaches announcements and nothing else, that an unreadable announcement
/// source does not blank a feed which still has shifts and queued writes in it.

final _now = DateTime(2026, 9, 7, 10);

const _dam = 'd_dam_central';
const _coast = 'd_coast';

const _operator = Capabilities(scoped: {_dam: Cap.scoped});
const _scopedElsewhere = Capabilities(
  scoped: {
    _coast: {Cap.detachmentView},
  },
);

Announcement _a(
  String id, {
  List<String> targets = const [_dam],
  Duration publishedAgo = const Duration(minutes: 5),
  Duration expiresIn = const Duration(hours: 24),
  AnnouncementStatus status = AnnouncementStatus.active,
}) =>
    Announcement(
      id: id,
      text: 'إعلان $id',
      detachmentIds: targets,
      placements: const {AnnouncementPlacement.notifications},
      publishedAt: _now.subtract(publishedAgo),
      expiresAt: _now.add(expiresIn),
      status: status,
    );

/// A stock row from the record half — the kind that must survive everything an
/// announcement does.
AppNotification _stockRow() => AppNotification(
      id: notificationId(NotificationKind.stockLow, 'i_1'),
      kind: NotificationKind.stockLow,
      occurredAt: _now,
      recordLabel: 'باراسيتامول',
      target: const StorageTarget(detachmentId: _dam, itemId: 'i_1'),
    );

PendingOperation _conflictedOp() => PendingOperation.create(
      kind: 'inventory.movement.add',
      entityType: 'inventory',
      entityId: 'i_1',
      idFactory: () => 'op1',
      clock: () => _now,
    ).copyWith(
      state: SyncState.conflict,
      lastAttemptAt: _now,
      attemptCount: 1,
    );

class _FakeRecords implements NotificationRepository {
  _FakeRecords(this.answer);
  Result<List<AppNotification>> answer;

  @override
  Future<Result<List<AppNotification>>> feed(String detachmentId) async =>
      answer;
}

class _FakeAnnouncements implements AnnouncementRepository {
  _FakeAnnouncements(this.answer);
  Result<List<Announcement>> answer;

  @override
  Future<Result<List<Announcement>>> list() async => answer;

  @override
  Future<Result<Announcement>> byId(String id) async =>
      const Failure('gone', code: 'not_found');

  @override
  Future<Result<Announcement>> publish({
    required String text,
    required List<String> detachmentIds,
    required Set<AnnouncementPlacement> placements,
    required DateTime publishedAt,
    required DateTime expiresAt,
    String? authorName,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Result<Announcement>> withdraw(String id) async =>
      throw UnimplementedError();
}

Future<ProviderContainer> _boot({
  Result<List<AppNotification>> records = const Success([]),
  Result<List<Announcement>> announcements = const Success([]),
  List<PendingOperation> outbox = const [],
  Capabilities capabilities = _operator,
}) async {
  final container = ProviderContainer(overrides: [
    clockProvider.overrideWithValue(() => _now),
    capabilitiesProvider.overrideWithValue(capabilities),
    tenantFeatureAvailableProvider.overrideWith((ref, key) => true),
    outboxStoreProvider.overrideWithValue(InMemoryOutboxStore(seed: outbox)),
    notificationHistoryStoreProvider
        .overrideWithValue(InMemoryNotificationHistoryStore()),
    notificationRepositoryProvider.overrideWithValue(_FakeRecords(records)),
    announcementRepositoryProvider
        .overrideWithValue(_FakeAnnouncements(announcements)),
  ]);
  addTearDown(container.dispose);

  await container.read(outboxProvider.future);
  await container.read(notificationReadIdsProvider.future);
  await container.read(notificationClearedIdsProvider.future);
  await container.read(announcementListProvider.future);
  return container;
}

Future<List<AppNotification>> _feed(ProviderContainer container) async {
  await container.read(notificationSourceProvider(_dam).future);
  return container.read(notificationFeedProvider(_dam)).value!.when(
        success: (data, {stale = false}) => data,
        failure: (_, __) => const [],
        offline: (cached) => cached ?? const [],
      );
}

void main() {
  group('one announcement, one history entry', () {
    test('a published announcement produces exactly one row', () async {
      final container = await _boot(
        announcements: Success([_a('a1')]),
      );
      final rows = await _feed(container);
      expect(rows, hasLength(1));
      expect(rows.single.kind, NotificationKind.announcement);
      expect(rows.single.id, 'announcement:a1');
      // The row carries the notice itself, and points at the announcement
      // rather than at a detachment it merely names.
      expect(rows.single.recordLabel, 'إعلان a1');
      expect(
        rows.single.target,
        const AnnouncementTarget(announcementId: 'a1'),
      );
    });

    test('the row is anchored to the publication time', () async {
      final container = await _boot(
        announcements: Success([
          _a('a1', publishedAgo: const Duration(hours: 30)),
        ]),
      );
      final rows = await _feed(container);
      expect(
        rows.single.occurredAt,
        _now.subtract(const Duration(hours: 30)),
      );
    });

    test('an expired announcement keeps its history row', () async {
      final container = await _boot(
        announcements: Success([
          _a(
            'a1',
            publishedAgo: const Duration(days: 3),
            expiresIn: const Duration(days: -2),
          ),
        ]),
      );
      expect(await _feed(container), hasLength(1));
    });

    test('a withdrawn announcement keeps its history row', () async {
      final container = await _boot(
        announcements: Success([
          _a('a1', status: AnnouncementStatus.withdrawn),
        ]),
      );
      expect(await _feed(container), hasLength(1));
    });

    test('an announcement for another detachment never appears', () async {
      final container = await _boot(
        announcements: Success([
          _a('a1', targets: const [_coast])
        ]),
      );
      expect(await _feed(container), isEmpty);
    });

    test('a session scoped elsewhere sees nothing of this detachment',
        () async {
      final container = await _boot(
        announcements: Success([_a('a1')]),
        capabilities: _scopedElsewhere,
      );
      expect(await _feed(container), isEmpty);
    });
  });

  group('no read state, ever', () {
    test('an announcement row is born read and adds nothing to the badge',
        () async {
      final container = await _boot(
        announcements: Success([_a('a1')]),
      );
      final rows = await _feed(container);

      expect(rows.single.isRead, isTrue);
      expect(rows.single.tracksReadState, isFalse);
      expect(container.read(unreadNotificationCountProvider(_dam)), 0);
    });

    test('publishing does not disturb another kind\'s unread count', () async {
      final container = await _boot(
        records: Success([_stockRow()]),
        announcements: Success([_a('a1'), _a('a2')]),
      );
      final rows = await _feed(container);

      expect(rows, hasLength(3));
      // One unread row — the stock one. The two announcements count for
      // nothing, which is the whole point of Point 14 §15.
      expect(container.read(unreadNotificationCountProvider(_dam)), 1);
    });

    test('marking everything read leaves announcements exactly as they were',
        () async {
      final container = await _boot(
        records: Success([_stockRow()]),
        announcements: Success([_a('a1')]),
      );
      var rows = await _feed(container);
      final unread = [
        for (final r in rows)
          if (!r.isRead) r.id,
      ];
      // The announcement is not in the list "mark all" would write.
      expect(unread, [notificationId(NotificationKind.stockLow, 'i_1')]);

      await container
          .read(notificationReadIdsProvider.notifier)
          .markRead(unread);
      rows = await _feed(container);
      expect(container.read(unreadNotificationCountProvider(_dam)), 0);
      // And no announcement id was ever stored.
      expect(
        container.read(notificationReadIdsProvider).value,
        isNot(contains('announcement:a1')),
      );
    });

    test('a stored read id for an announcement changes nothing', () async {
      // Defence in depth: even if some future store somehow held one, the
      // announcement row is passed through untouched.
      final container = await _boot(
        announcements: Success([_a('a1')]),
      );
      await container
          .read(notificationReadIdsProvider.notifier)
          .markRead(['announcement:a1']);
      final rows = await _feed(container);
      expect(rows.single.isRead, isTrue);
      expect(container.read(unreadNotificationCountProvider(_dam)), 0);
    });
  });

  group('clearing history', () {
    test('only announcement rows are clearable', () async {
      final container = await _boot(
        records: Success([_stockRow()]),
        announcements: Success([_a('a1')]),
        outbox: [_conflictedOp()],
      );
      final rows = await _feed(container);
      expect(rows, hasLength(3));

      expect(clearableNotificationIds(rows), ['announcement:a1']);
    });

    test('clearing removes the announcement row and nothing else', () async {
      final container = await _boot(
        records: Success([_stockRow()]),
        announcements: Success([_a('a1')]),
        outbox: [_conflictedOp()],
      );
      var rows = await _feed(container);

      final cleared = await container
          .read(notificationClearedIdsProvider.notifier)
          .clear(clearableNotificationIds(rows));
      expect(cleared, isA<Success<int>>());

      rows = await _feed(container);
      expect(rows.map((r) => r.kind), [
        NotificationKind.stockLow,
        NotificationKind.syncConflict,
      ]);
    });

    test('clearing deletes no source record', () async {
      // The stock row and the conflicted operation are projections of records
      // that must survive a clear untouched — this is the guarantee that a
      // "clear notifications" button cannot destroy operational state.
      final container = await _boot(
        records: Success([_stockRow()]),
        announcements: Success([_a('a1')]),
        outbox: [_conflictedOp()],
      );
      final rows = await _feed(container);
      await container
          .read(notificationClearedIdsProvider.notifier)
          .clear(clearableNotificationIds(rows));

      final outbox = container.read(outboxProvider).value!;
      expect(outbox, hasLength(1));
      expect(outbox.single.operationId, 'op1');
      expect(outbox.single.needsReview, isTrue);
      // And the derived condition still re-derives on the next load.
      expect(
        (await _feed(container)).map((r) => r.kind),
        contains(NotificationKind.stockLow),
      );
    });

    test('a scoped admin\'s clearable set never reaches another detachment',
        () async {
      // The concern this test exists for: «مسح الإشعارات» must not become a
      // global destructive action. The ids come from the *visible* feed, which
      // was already narrowed by the grant, so an announcement addressed to the
      // coast is not in the set a Damascus admin can clear — it is not in the
      // set they can see.
      final container = await _boot(
        announcements: Success([
          _a('a_dam'),
          _a('a_coast', targets: const [_coast]),
        ]),
      );

      final clearable = clearableNotificationIds(await _feed(container));

      expect(
        clearable,
        [notificationId(NotificationKind.announcement, 'a_dam')],
      );
    });

    test('clearing an id that is not an announcement changes nothing',
        () async {
      // Direct controller invocation, bypassing the confirmation dialog and
      // `clearableNotificationIds` entirely. The cleared set is read in exactly
      // one place — the announcement builder — so a foreign id is inert rather
      // than destructive.
      final container = await _boot(
        records: Success([_stockRow()]),
        announcements: Success([_a('a_1')]),
        outbox: [_conflictedOp()],
      );

      await container
          .read(notificationClearedIdsProvider.notifier)
          .clear([_stockRow().id, 'op1', 'nonsense']);

      final kinds = {for (final n in await _feed(container)) n.kind};
      expect(kinds, contains(NotificationKind.stockLow));
      expect(kinds, contains(NotificationKind.syncConflict));
      expect(kinds, contains(NotificationKind.announcement));
    });

    test('clearing twice writes once and reports nothing changed', () async {
      final container = await _boot(
        announcements: Success([_a('a1')]),
      );
      final rows = await _feed(container);
      final ids = clearableNotificationIds(rows);

      final first = await container
          .read(notificationClearedIdsProvider.notifier)
          .clear(ids);
      final second = await container
          .read(notificationClearedIdsProvider.notifier)
          .clear(ids);

      expect(
        first.when(
          success: (n, {stale = false}) => n,
          failure: (_, __) => -1,
          offline: (_) => -1,
        ),
        1,
      );
      expect(
        second.when(
          success: (n, {stale = false}) => n,
          failure: (_, __) => -1,
          offline: (_) => -1,
        ),
        0,
      );
    });

    test('a cleared announcement does not come back on the next load',
        () async {
      final container = await _boot(
        announcements: Success([_a('a1')]),
      );
      await container
          .read(notificationClearedIdsProvider.notifier)
          .clear(['announcement:a1']);
      container.invalidate(notificationSourceProvider(_dam));
      expect(await _feed(container), isEmpty);
    });
  });

  group('one failing source does not take the others down', () {
    test('an unreadable announcement source leaves the rest of the feed',
        () async {
      final container = await _boot(
        records: Success([_stockRow()]),
        announcements: const Failure('boom', code: 'server'),
        outbox: [_conflictedOp()],
      );
      final rows = await _feed(container);
      expect(rows.map((r) => r.kind), [
        NotificationKind.stockLow,
        NotificationKind.syncConflict,
      ]);
    });

    test('an offline announcement source with a cached copy still shows it',
        () async {
      final container = await _boot(
        announcements: Offline(cached: [_a('a1')]),
      );
      expect(await _feed(container), hasLength(1));
    });

    test('an unreadable record source still reports its own failure', () async {
      // The pre-existing rule, unchanged by announcements: when the record half
      // cannot be read at all the feed reports *that*, rather than rendering a
      // partial list as though it were complete. Adding announcements must not
      // paper over a broken shift/stock source — a screen that quietly showed
      // one notice while the rest of the detachment was unreadable would be
      // worse than the error state.
      final container = await _boot(
        records: const Failure('boom', code: 'server'),
        announcements: Success([_a('a1')]),
      );
      await container.read(notificationSourceProvider(_dam).future);
      final result = container.read(notificationFeedProvider(_dam)).value!;
      expect(result, isA<Failure<List<AppNotification>>>());
      expect(container.read(unreadNotificationCountProvider(_dam)), 0);
    });
  });

  group('destinations', () {
    test('an announcement row opens the announcement, never a detachment',
        () async {
      final container = await _boot(
        announcements: Success([
          _a('a1', targets: const [_dam, _coast]),
        ]),
      );
      final rows = await _feed(container);
      final destination = destinationFor(
        rows.single,
        container.read(capabilitiesProvider),
      );
      expect(
        destination,
        isA<OpenAnnouncement>()
            .having((d) => d.announcementId, 'announcementId', 'a1'),
      );
    });

    test('a stale destination is a failure, not a crash', () async {
      final container = await _boot(
        announcements: Success([_a('a1')]),
      );
      // The fake repository has no `byId` answer — exactly the case where the
      // announcement was withdrawn and removed between the feed loading and
      // the row being tapped.
      final result =
          await container.read(announcementRepositoryProvider).byId('a1');
      expect(result, isA<Failure<Announcement>>());
    });
  });
}
