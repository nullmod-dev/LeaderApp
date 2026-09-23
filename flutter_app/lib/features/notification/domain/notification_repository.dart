import '../../../core/result/result.dart';
import 'notification_models.dart';

/// The record-derived half of the Notifications Center.
///
/// One call rather than three: a mobile client opening a feed on a bad
/// connection should pay for one round trip. A real backend serves this by
/// joining data it already owns — see `API_CONTRACT.md` § Notifications.
///
/// The **client-owned** half (a queued write that failed, a conflict waiting
/// on a decision) is not here on purpose: it is read straight off the local
/// outbox by `buildSyncNotifications`, so it stays true with no network at
/// all. The two halves are merged in `notification_providers.dart`.
///
/// Read state is deliberately **not** on this interface — it belongs to the
/// session rather than to the feed, and covers rows from both halves. See
/// [NotificationReadStore] in `notification_read_store.dart`.
abstract class NotificationRepository {
  /// Every condition this detachment's records currently raise, unfiltered by
  /// the session's grants (the caller applies `visibleNotifications`) and with
  /// [AppNotification.isRead] left at its default (the caller applies
  /// `applyReadState`).
  Future<Result<List<AppNotification>>> feed(String detachmentId);
}
