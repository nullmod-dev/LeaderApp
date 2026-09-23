/// Where "an administrator cleared this from the history" is kept.
///
/// Its own seam next to [NotificationReadStore], and the two are not the same
/// thing — mixing them is the mistake this file exists to prevent. *Read* means
/// the user has looked at a row that is still true. *Cleared* means the row is
/// a past event they no longer want listed. One is a badge; the other is
/// history.
///
/// **Only announcement rows are ever cleared, and that is a domain rule, not a
/// UI convenience.** Every other kind in the feed is a *live condition*
/// projected from a record that still exists: an understaffed shift, an item
/// under its minimum, a queued write that failed. Clearing one of those would
/// either lie (the condition is still true and would re-derive) or destroy
/// something operational (the shift, the item, the outbox entry). So the clear
/// action offered on the Notifications Center removes announcement history and
/// nothing else, and says so before it runs. Source records are never touched
/// by anything in this file.
abstract class NotificationHistoryStore {
  /// Every notification id an administrator has cleared from the list.
  Future<Set<String>> clearedIds();

  /// Records [ids] as cleared. Idempotent: re-clearing a stored id is a no-op,
  /// not a second write.
  Future<void> clear(Iterable<String> ids);
}

/// The shipped store.
///
/// **Lifetime of this object only** — the same gap [InMemoryNotificationReadStore]
/// has, and for the same reason: there is no durable local store in this build.
/// The seam is complete; a store writing to encrypted local storage, or a
/// backend owning cleared state per administrator, drops in without touching a
/// caller.
class InMemoryNotificationHistoryStore implements NotificationHistoryStore {
  final Set<String> _cleared = {};

  @override
  Future<Set<String>> clearedIds() async => Set<String>.of(_cleared);

  @override
  Future<void> clear(Iterable<String> ids) async => _cleared.addAll(ids);
}
