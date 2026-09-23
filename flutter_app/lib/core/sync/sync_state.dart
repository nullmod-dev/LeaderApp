/// The lifecycle a single local write moves through on its way to the
/// shared server state.
///
/// MTM is offline-first: a valid write is saved locally and the user keeps
/// working. Synchronisation happens afterwards — automatically when it can,
/// or on demand from Settings. This enum is the *smallest* model that
/// supports both paths and the conflict/review distinction Task 2 (roadmap
/// §6) adds on top.
///
/// ## What is modelled now
///
/// - [pending]  — saved locally, not yet accepted by the server. This is
///   also the "saved locally, offline, never attempted" case: there is no
///   separate `local` state, because the instant a write is stored it is
///   already waiting to sync.
/// - [syncing]  — an attempt is in flight for this operation right now.
/// - [synced]   — the server has accepted it. The operation can be dropped
///   from the outbox.
/// - [failed]   — an attempt finished without acceptance and without a
///   permanent verdict: no connectivity, a transport error, a `5xx`, or a
///   future `409 in_progress`. **This is not data loss.** The local write
///   still stands; the operation is simply still owed to the server and
///   will be retried (auto or manual) with the *same* identity. This is the
///   *temporary/retryable* failure case — see [isRetryable].
/// - [conflict] — a push came back classified as a stale write (the record
///   moved under this operation) rather than a temporary failure. The
///   operation is **not** data loss and is **not** [synced]: it keeps its
///   original identity and metadata, stops being picked up by the ordinary
///   retry loop ([isRetryable] is `false`), and waits for a human decision
///   through the Task 1 conflict screen (`useLocal` / `useCurrent` /
///   `reviewLater` — see `OutboxController.requeueAfterConflict` /
///   `discardConflict`). The agreed wire code is `stale_write`
///   (`ProblemCode.staleWrite`, Task 3) — see `sync_conflict_classifier.dart`
///   — but no real backend or transport exists yet to ever send it.
///
/// ## Deferred — owned by a future Needs-Review inbox task
///
/// - `needsReview` — a durable, cross-conflict inbox listing every
///   [conflict] operation for review at once. Task 2 exposes only a count
///   (`OutboxController.conflictOperationsCountProvider`) and a quiet
///   attention state in Settings; the inbox itself is not built.
///
/// Adding it is additive: a new enum value, a new `case` in the places that
/// switch exhaustively, and the store/records already round-trip an unknown
/// string safely (see [SyncState.fromWire]).
enum SyncState {
  pending('pending'),
  syncing('syncing'),
  synced('synced'),
  failed('failed'),
  conflict('conflict');

  const SyncState(this.wire);

  /// The stable string persisted in the outbox and (later) sent to / read
  /// from the `/sync` queue. Kept separate from [name] so reordering the
  /// enum can never re-point a stored record.
  final String wire;

  /// True while the operation has not reached a terminal, accepted state —
  /// used for "still outstanding" counts. Includes [conflict]: a conflicted
  /// operation is unresolved, just not by the ordinary retry loop.
  bool get isUnsynced => this != SyncState.synced;

  /// True for the states the *ordinary* sync loop (auto or manual) may pick
  /// up and push again: [pending], [syncing] (already in flight this run),
  /// and [failed] (a temporary/retryable failure). [conflict] is
  /// deliberately excluded — once classified, an operation waits for a
  /// human decision and must not be hammered by routine retries (roadmap
  /// §7).
  bool get isRetryable =>
      this == SyncState.pending ||
      this == SyncState.syncing ||
      this == SyncState.failed;

  /// True only for [conflict] — kept as a named predicate so call sites read
  /// as intent ("does this need a human decision?") rather than an enum
  /// comparison.
  bool get needsReview => this == SyncState.conflict;

  /// A value this build does not recognise resolves to [pending] rather
  /// than throwing: a record written by a newer client (or a future
  /// `needsReview`) is still safe to keep and show as "waiting". It is
  /// never silently treated as done.
  static SyncState fromWire(String? wire) {
    for (final s in values) {
      if (s.wire == wire) return s;
    }
    return SyncState.pending;
  }
}
