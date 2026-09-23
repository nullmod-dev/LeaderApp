/// Where "the user has seen this" is kept.
///
/// Its own seam, next to [OutboxStore] and [ConflictReviewStore] rather than
/// on the repository, because read state covers rows from **both** halves of
/// the feed: the ones a backend derives from records and the ones the client
/// derives from its own outbox. One store, one set of ids, one badge.
///
/// A row is identified by [AppNotification.id], which is a stable function of
/// the condition and the record behind it — not of the fetch — so a read row
/// stays read across reloads for as long as the condition lasts.
abstract class NotificationReadStore {
  /// Every notification id the user has marked read.
  Future<Set<String>> readIds();

  /// Records [ids] as read. Idempotent: re-marking a stored id is a no-op,
  /// not a second write.
  Future<void> markRead(Iterable<String> ids);
}

/// The shipped store.
///
/// **Lifetime of this object only** — exactly the gap the theme preference
/// and the active-detachment choice have (`HANDOFF.md`): there is no durable
/// local store in this build, so nothing survives a relaunch. The seam is
/// complete; a concrete store writing to encrypted local storage, or a real
/// backend owning read state per user, drops in without touching a caller.
class InMemoryNotificationReadStore implements NotificationReadStore {
  final Set<String> _read = {};

  @override
  Future<Set<String>> readIds() async => Set<String>.of(_read);

  @override
  Future<void> markRead(Iterable<String> ids) async => _read.addAll(ids);
}
