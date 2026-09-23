import 'package:flutter/foundation.dart';

import 'shift_models.dart';

/// The current-as-of-detection snapshot `FRONTEND-BACKEND-INTEGRATION.md`
/// §5.4 requires: what the server's `409 stale_write` body said the record
/// looked like at the moment a push conflicted, captured then because that
/// is the only moment connectivity is guaranteed.
///
/// Typed, never raw — [current] is an ordinary [Shift], the same model
/// every other read/write already uses, so [ShiftConflictSnapshotStore]
/// never needs a bespoke serialization shape and `composeShiftConflictReview`
/// can hand it straight to `presentShiftConflict` unchanged.
@immutable
class ShiftConflictSnapshot {
  const ShiftConflictSnapshot({
    required this.current,
    this.baseVersion,
    this.currentVersion,
  });

  /// The shift as the server reported it at detection time — never the
  /// user's local edit, never a fabricated stand-in.
  final Shift current;

  /// Opaque concurrency tokens carried for `ConflictPresentation` /
  /// `ConflictReviewEntry`. Never displayed, never compared here.
  final String? baseVersion;
  final String? currentVersion;
}

/// Persistence seam for [ShiftConflictSnapshot]s, keyed by the conflicting
/// operation's id (`PendingOperation.operationId` — the outbox path always
/// sets `conflictId` equal to it, `FRONTEND-BACKEND-INTEGRATION.md` §5.4).
///
/// THE SEAM. A shipping build backs this with the same encrypted local
/// database (SQLCipher) `OutboxStore` / `ConflictReviewStore` already live
/// in — a table keyed by `conflictId`, written with `Shift.toJson()` plus
/// the two version strings. Until that database exists,
/// [InMemoryShiftConflictSnapshotStore] stands in with the same lifetime
/// limitation as `InMemoryOutboxStore` / `InMemoryConflictReviewStore`: it
/// holds snapshots for the lifetime of the object only, **not** durable
/// across an OS process restart. This is a scaffold, not a shortcut —
/// nothing here claims otherwise, and no database package is added merely
/// to claim durability that does not exist yet.
///
/// This store is feature-owned and lives entirely inside `features/shift`
/// — `core/sync` never imports it, exactly as `core/sync` never imports
/// `ConflictReviewStore`. It is also **not** a second "what needs review"
/// queue: a snapshot here without a matching `SyncState.conflict` operation
/// on the outbox is inert — nothing ever looks it up except
/// `composeShiftConflictReview`/`applyShiftConflictCurrentVersion`, and both
/// are only ever called for an operation the outbox still lists as
/// conflicted.
abstract class ShiftConflictSnapshotStore {
  /// The stored snapshot for [conflictId], or `null` when nothing was ever
  /// captured for it (no real transport exists to capture one from yet —
  /// see `composeShiftConflictReview`'s "may safely return no entry"
  /// contract).
  Future<ShiftConflictSnapshot?> read(String conflictId);

  /// Inserts, or replaces the snapshot stored for [conflictId] — a later
  /// detection on the same operation supersedes rather than stacks, the
  /// same rule `ConflictReviewStore.upsert` follows.
  Future<void> upsert(String conflictId, ShiftConflictSnapshot snapshot);

  /// Drops the snapshot for [conflictId]. A no-op when nothing is stored
  /// under it.
  Future<void> remove(String conflictId);
}
