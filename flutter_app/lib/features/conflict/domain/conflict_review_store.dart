import 'conflict_review_entry.dart';

/// Persistence seam for the durable Needs Review metadata — the feature-owned
/// half of a conflict, next to the generic `PendingOperation` the outbox
/// already keeps.
///
/// THE SEAM. A shipping build backs this with the same encrypted local
/// database (SQLCipher) the outbox lives in — a table keyed by
/// [ConflictReviewEntry.conflictId], written with `toJson()`. It is
/// deliberately **not** a new generic column on `PendingOperation`
/// (`FRONTEND-BACKEND-INTEGRATION.md` §5.4, "Feature-owned, not a new
/// generic field"): sync core stays payload-free and generic, features own
/// their own typed data. It must never live in the plaintext preferences
/// bucket theme and motion level use (`DATA-NEEDS.md` §3.3).
///
/// Two rules the interface itself encodes:
///
/// - **Superseded, not accumulated.** [upsert] replaces the entry for a
///   `conflictId`; a second `409` on the same operation must not leave two
///   stacked "current" states for the review screen to choose between.
/// - **One lifetime, tied to the operation's.** [remove] is called when the
///   conflict is resolved (`useLocal` / `useCurrent`) or the operation
///   otherwise leaves the outbox. `reviewLater` removes nothing.
abstract class ConflictReviewStore {
  /// Every stored entry. Ordering is not part of the contract — the inbox
  /// sorts what it shows.
  Future<List<ConflictReviewEntry>> readAll();

  /// Inserts, or replaces the entry with the same
  /// [ConflictReviewEntry.conflictId].
  Future<void> upsert(ConflictReviewEntry entry);

  /// Drops one entry. A no-op when nothing is stored under [conflictId].
  Future<void> remove(String conflictId);
}
