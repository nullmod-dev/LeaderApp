import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../demo/data/demo_workspace.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/result/result.dart';
import '../../../core/sync/outbox_controller.dart';
import '../../../l10n/strings.dart';
import '../../announcement/data/announcement_providers.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../shift/data/shift_providers.dart';
import '../domain/notification_history_store.dart';
import '../domain/notification_models.dart';
import '../domain/notification_read_store.dart';
import '../domain/notification_repository.dart';
import '../domain/notification_selectors.dart';
import 'mock_notification_repository.dart';
import '../../tenant_feature/data/tenant_feature_providers.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart';

/// The record-derived half of the feed.
///
/// Composed from the same repositories the rest of the app reads, so the
/// centre can never raise a row for a shift or an item that exists nowhere
/// else.
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final inventoryEnabled = ref.watch(
    tenantFeatureAvailableProvider(TenantFeatureKey.inventory),
  );
  final demo = ref.watch(demoWorkspaceProvider);
  if (demo != null) return demo.notifications;
  return MockNotificationRepository(
    shifts: ref.watch(shiftRepositoryProvider),
    inventory: inventoryEnabled ? ref.watch(inventoryRepositoryProvider) : null,
  );
});

/// Where read state is persisted. Override with a durable store in a shipping
/// build — see [InMemoryNotificationReadStore] for the gap this leaves.
final notificationReadStoreProvider = Provider<NotificationReadStore>((ref) {
  return InMemoryNotificationReadStore();
});

/// Where cleared history is persisted. A separate store from read state on
/// purpose — see the note at the top of `notification_history_store.dart`.
final notificationHistoryStoreProvider =
    Provider<NotificationHistoryStore>((ref) {
  return InMemoryNotificationHistoryStore();
});

/// The ids the user has marked read, live.
///
/// An [AsyncNotifier] for the same reason `OutboxController` is one: the
/// stored set arrives asynchronously and the screen has to render in the
/// meantime. Until it lands every row reads as unread, which is the safe
/// direction to be wrong in — the badge over-reports rather than hiding
/// something the user has not seen.
class NotificationReadController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() =>
      ref.read(notificationReadStoreProvider).readIds();

  Set<String> get _current => state.valueOrNull ?? const {};

  /// Marks [ids] read.
  ///
  /// Ids already on file are dropped before the store is touched, so a
  /// double tap — or a "mark all" over a mostly-read list — is one write of
  /// what actually changed, never a second write of what did not. Returns
  /// [Success] with how many rows changed.
  Future<Result<int>> markRead(Iterable<String> ids) async {
    final known = _current;
    final added = {
      for (final id in ids)
        if (!known.contains(id)) id,
    };
    if (added.isEmpty) return const Success(0);

    try {
      await ref.read(notificationReadStoreProvider).markRead(added);
    } catch (_) {
      // The store is a seam: a durable or server-backed implementation can
      // genuinely fail. Nothing is marked locally when it does — a badge that
      // silently disagrees with what was stored is worse than a retry.
      return const Failure(S.notificationsMarkReadFailed);
    }

    state = AsyncData({...known, ...added});
    return Success(added.length);
  }
}

final notificationReadIdsProvider =
    AsyncNotifierProvider<NotificationReadController, Set<String>>(
  NotificationReadController.new,
);

/// The ids an administrator has cleared from the list, live.
///
/// An [AsyncNotifier] for the same reason [NotificationReadController] is one:
/// the stored set arrives asynchronously and the screen has to render in the
/// meantime. Until it lands nothing is filtered out, which is the safe
/// direction to be wrong in — a row briefly shown is recoverable; a row
/// wrongly hidden is a notice the administrator never learns was sent.
class NotificationHistoryController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() =>
      ref.read(notificationHistoryStoreProvider).clearedIds();

  Set<String> get _current => state.valueOrNull ?? const {};

  /// Clears [ids] from the history.
  ///
  /// Ids already on file are dropped before the store is touched, so a second
  /// confirmation — or a clear over an already-cleared list — is one write of
  /// what actually changed, never a second write of what did not. That is also
  /// the duplicate-action guard: returning [Success] with `0` is the honest
  /// answer to "clear twice", and nothing downstream is invalidated.
  ///
  /// **Nothing operational is deleted here.** The only ids that ever reach this
  /// method are announcement history rows (`clearableNotificationIds` decides
  /// that, from the feed itself); shifts, stock items, conflicts and outbox
  /// operations are untouched, and the conditions they raise re-derive on the
  /// next load exactly as before.
  Future<Result<int>> clear(Iterable<String> ids) async {
    final known = _current;
    final added = {
      for (final id in ids)
        if (!known.contains(id)) id,
    };
    if (added.isEmpty) return const Success(0);

    try {
      await ref.read(notificationHistoryStoreProvider).clear(added);
    } catch (_) {
      return const Failure(S.notificationsClearFailed);
    }

    state = AsyncData({...known, ...added});
    return Success(added.length);
  }
}

final notificationClearedIdsProvider =
    AsyncNotifierProvider<NotificationHistoryController, Set<String>>(
  NotificationHistoryController.new,
);

/// The announcement half of the feed.
///
/// Read from the announcement repository through its own provider rather than
/// hard-coded into the Notifications Center — the rule that every row enters
/// through a source seam. Cleared ids are applied here, at the point the rows
/// are built, so a cleared announcement never reaches the merge at all.
///
/// An unreadable announcement source yields an empty list (see
/// [announcementsOf]): one failing source must not blank a feed that still has
/// shifts, stock and the user's own queued writes to show.
final announcementNotificationsProvider = Provider.autoDispose
    .family<List<AppNotification>, String>((ref, detachmentId) {
  return buildAnnouncementNotifications(
    detachmentId: detachmentId,
    announcements: ref.watch(visibleAnnouncementsProvider(detachmentId)),
    clearedIds:
        ref.watch(notificationClearedIdsProvider).valueOrNull ?? const {},
  );
});

/// The client-owned half of the feed: the user's own queued writes.
///
/// Read straight off the outbox, so it is exactly as true with no network as
/// with one — and it is why an offline device with nothing cached can still
/// have a feed worth opening.
final syncNotificationsProvider = Provider<List<AppNotification>>((ref) {
  return buildSyncNotifications(
    operations: ref.watch(outboxProvider).valueOrNull ?? const [],
  );
});

/// The record half, fetched once per detachment.
///
/// Deliberately depends on nothing volatile. The merge below watches the
/// outbox, the read set and the session's grants — if this provider watched
/// them too, every queued write and every row the user opened would restart a
/// round trip for data that had not changed.
final notificationSourceProvider = FutureProvider.autoDispose
    .family<Result<List<AppNotification>>, String>((ref, detachmentId) {
  return ref.watch(notificationRepositoryProvider).feed(detachmentId);
});

/// The whole feed for one detachment: both halves, filtered by the session's
/// grants, stamped with read state.
///
/// A plain [Provider], not a fetch: merging is synchronous and cheap, so a
/// sync run changing the outbox, or a row being marked read, recomputes the
/// list — and with it the badge — without asking the repository anything
/// again. `autoDispose` and keyed by detachment like every other
/// detachment-scoped read (`DETACHMENT-SCOPING.md` §2 rule 2); it stays alive
/// while the dashboard's bell is on screen, so returning from a
/// notification's destination re-renders rather than refetching.
final notificationFeedProvider = Provider.autoDispose
    .family<AsyncValue<Result<List<AppNotification>>>, String>(
        (ref, detachmentId) {
  final capabilities = ref.watch(capabilitiesProvider);
  final readIds =
      ref.watch(notificationReadIdsProvider).valueOrNull ?? const {};
  final local = ref.watch(syncNotificationsProvider);
  // The third half. Announcements are records rather than conditions, so they
  // are merged in beside the derived rows and the outbox rather than being
  // asked of the record repository — which owns no announcement and never will.
  final announcementsEnabled = ref.watch(
    tenantFeatureAvailableProvider(TenantFeatureKey.announcements),
  );
  final announcements = announcementsEnabled
      ? ref.watch(announcementNotificationsProvider(detachmentId))
      : const <AppNotification>[];

  List<AppNotification> compose(List<AppNotification> remote) => applyReadState(
        visibleNotifications(
          [...remote, ...local, ...announcements],
          detachmentId: detachmentId,
          capabilities: capabilities,
        ),
        readIds,
      );

  return ref.watch(notificationSourceProvider(detachmentId)).whenData(
        (result) => result.when(
          success: (data, {stale = false}) =>
              Success(compose(data), stale: stale),
          failure: (message, code) => Failure(message, code: code),
          offline: (cached) {
            // Offline with nothing cached is still not necessarily an empty
            // screen: the user's own unsynced work is local, and hiding it
            // because the network is down is exactly when they most need to
            // see it. Only when there is nothing at all does the screen fall
            // through to the shared "offline, no cached copy" state.
            final rows = compose(cached ?? const []);
            return rows.isEmpty ? const Offline() : Offline(cached: rows);
          },
        ),
      );
});

/// How many rows in [notificationFeedProvider] are unread — the number the
/// bell shows.
///
/// Derived from the very list the screen renders rather than counted
/// separately, which is what makes the badge and the screen impossible to
/// disagree. Zero while the feed is loading or unreadable: a badge is a
/// promise that something is there.
final unreadNotificationCountProvider =
    Provider.autoDispose.family<int, String>((ref, detachmentId) {
  final feed = ref.watch(notificationFeedProvider(detachmentId)).valueOrNull;
  if (feed == null) return 0;
  return feed.when(
    success: (data, {stale = false}) => unreadCount(data),
    failure: (_, __) => 0,
    offline: (cached) => cached == null ? 0 : unreadCount(cached),
  );
});

/// The ids in [items] an administrator may clear from the history.
///
/// **Announcements only, and by construction rather than by convention.** Every
/// other kind in the feed is a projection of a live condition: clearing one
/// would either lie — the condition is still true and the row re-derives on the
/// next load — or, if it were made to stick, would mean deleting the shift, the
/// stock item or the outbox operation behind it. Neither is something a "clear
/// notifications" button is allowed to do, so this function is the one place
/// that decides what the action can even reach.
List<String> clearableNotificationIds(List<AppNotification> items) => [
      for (final n in items)
        if (n.kind == NotificationKind.announcement) n.id,
    ];
