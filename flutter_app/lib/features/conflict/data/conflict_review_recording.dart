import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/conflict_review_recorder.dart';
import '../../../core/sync/pending_operation.dart';
import '../domain/conflict_review_entry.dart';
import 'conflict_review_controller.dart';

/// Builds the durable review metadata for one conflicted operation, or
/// returns `null` when it cannot.
///
/// Owned by the feature that owns the record, because only that feature has
/// the typed local and "current as of detection" records, knows which fields
/// are safe to display, and can format them
/// (`FRONTEND-BACKEND-INTEGRATION.md` §5.4). A composer is the natural home
/// for the snapshot capture that section requires: it runs at detection
/// time, when the `409` body — and connectivity — are still available.
///
/// Returning `null` is a legitimate answer, not a failure: it means "this
/// operation really is conflicted, but I have nothing safe to show for it
/// yet." The inbox then lists the conflict without a differences screen
/// rather than inventing one.
typedef ConflictReviewComposer = Future<ConflictReviewEntry?> Function(
  PendingOperation operation,
);

/// Composers by `PendingOperation.entityType`.
///
/// **Empty today, deliberately.** No feature can compose an entry yet
/// because no feature stores a current-as-of-detection snapshot — that piece
/// is specified in §5.4 and still unbuilt — and, more simply, nothing in the
/// shipped app can conflict at all: `OfflineSyncTransport` is the only
/// transport and it never returns a `stale_write`. Registering a composer
/// that fabricated a "current" record to make the inbox look populated would
/// be inventing a backend conflict, which this task explicitly must not do.
///
/// A feature joins by overriding this provider with its own entry, e.g.
/// `{'shift': composeShiftConflictReview}`, once it has a real snapshot to
/// build a `presentShiftConflict(...)` from.
final conflictReviewComposersProvider =
    Provider<Map<String, ConflictReviewComposer>>(
  (ref) => const <String, ConflictReviewComposer>{},
);

/// The real [ConflictReviewRecorder]: asks the owning feature for safe
/// metadata and stores it.
///
/// Runs *after* `SyncCoordinator` has already moved the operation to
/// `SyncState.conflict`, so the conflict itself is preserved and counted
/// whatever happens here. It never navigates and never touches a transport.
Future<void> recordConflictForReview(
  Ref ref,
  PendingOperation operation,
) async {
  final composer =
      ref.read(conflictReviewComposersProvider)[operation.entityType];
  if (composer == null) return;

  final entry = await composer(operation);
  if (entry == null) return;

  // §5.4: conflictId *is* the operation id on the outbox path. A composer
  // that minted a second identity would silently orphan its own entry.
  assert(
    entry.conflictId == operation.operationId,
    'a conflict review entry must be keyed by the conflicting operation id',
  );
  if (entry.conflictId != operation.operationId) return;

  await ref.read(conflictReviewProvider.notifier).record(entry);
}

/// Installs [recordConflictForReview] over the core no-op hook.
///
/// Applied at the app's composition root (`main.dart`) rather than inside
/// `core/sync`, so core sync keeps knowing nothing about any feature. A test
/// that wants the real recorder applies the same overrides.
final List<Override> conflictReviewOverrides = [
  conflictReviewRecorderProvider.overrideWith(
    (ref) => (operation) => recordConflictForReview(ref, operation),
  ),
];
