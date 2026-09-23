import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/outbox_controller.dart';
import '../../../core/sync/sync_state.dart';
import '../domain/conflict_models.dart';
import 'conflict_current_application.dart';
import 'conflict_review_controller.dart';

/// Turns a Task 1 [ConflictResolutionDecision] into the local state change it
/// honestly implies (`FRONTEND-BACKEND-INTEGRATION.md` §5.5).
///
/// This **is** the live handler: `NeedsReviewPage` passes
/// `conflictDecisionHandlerProvider` straight into
/// `ConflictResolutionRouteArgs.onDecision`, so a decision taken on the
/// Task 1 screen lands here. Nothing here talks to a server or a transport —
/// still true after this corrective pass — but each branch now does the
/// full *local* half §5.5/§5.6 actually require, not a placeholder.
///
/// - **reviewLater** does nothing — no lookup, no validation, nothing
///   touched. The operation stays exactly as it was — still a conflict,
///   still waiting for a human decision — and its stored review metadata
///   and any feature-owned snapshot stay with it, which is what "preserves
///   the unresolved operation" means here and why it is still on the Needs
///   Review list on the way back out.
/// - **useLocal / useCurrent** both first load the still-conflicted
///   `PendingOperation` by [ConflictResolutionDecision.localOperationId] and
///   validate it: it must exist, it must still be [SyncState.conflict], and
///   [ConflictResolutionDecision.conflictId] must actually name it. Any of
///   these failing throws a typed [ConflictResolutionException] and
///   changes nothing — except in the one case where the operation is
///   gone entirely, where the review metadata left behind for it is
///   dropped too, because it now describes a conflict that no longer
///   exists. Both then revalidate: a record that moved *again* since
///   this comparison was built is reported as such rather than
///   resolved against a version the user never saw.
///   - **useLocal** additionally requires
///     [ConflictResolutionDecision.currentVersion] to be non-null and
///     non-empty, then calls `OutboxController.supersedeConflict` — a
///     brand-new operation that references the original through
///     `PendingOperation.resolvesOperationId` and carries the version
///     forward as `PendingOperation.currentVersion`, durably created
///     *before* the original is retired (see that method's own doc comment
///     for the exact ordering). Nothing is pushed here; the new operation
///     waits for the ordinary sync loop like any other pending write. Only
///     once it succeeds is the stored `ConflictReviewEntry` forgotten, and
///     only then is the registered [ConflictSnapshotCleaner] invoked.
///   - **useCurrent** looks up the owning feature's registered
///     [ConflictCurrentApplier] and applies the typed current/shared record
///     to its own local repository *first*. Only once that reports success
///     is the pending write retired (`OutboxController.discardConflict`),
///     then the review entry forgotten, then the snapshot cleaner invoked
///     last. A missing applier, a missing snapshot, or a failed apply
///     throws instead of silently discarding the user's local edit.
///
/// **Failure behaviour.** Every validation step and every awaited call lets
/// its exception propagate unchanged — nothing here catches an error
/// partway and leaves the operation half-resolved. The caller is
/// `ConflictResolutionPage._submit`, which already treats a thrown
/// [ConflictDecisionHandler] as "decision failed": the screen stays open,
/// `S.conflictDecisionFailed` is shown, and nothing about the conflict — the
/// operation, its review entry, or any feature-owned snapshot — is touched.
Future<void> applyConflictResolution(
  Ref ref,
  ConflictResolutionDecision decision,
) async {
  if (decision.intent == ConflictResolutionIntent.reviewLater) return;

  final ops = await ref.read(outboxProvider.future);
  final original = ops
      .where((op) => op.operationId == decision.localOperationId)
      .firstOrNull;
  if (original == null) {
    // Resolved from somewhere else, or the sync that carried it finally went
    // through. Either way there is nothing left to decide, and any metadata
    // still stored for it is stale — drop it so the review list does not go
    // on offering a conflict that no longer exists.
    await ref.read(conflictReviewProvider.notifier).forget(decision.conflictId);
    throw ConflictResolutionException(
      ConflictResolutionFailure.alreadyResolved,
      'no conflicted operation "${decision.localOperationId}" to resolve — '
      'it may already have been resolved or synced elsewhere',
    );
  }
  if (original.state != SyncState.conflict) {
    throw ConflictResolutionException(
      ConflictResolutionFailure.alreadyResolved,
      'operation "${decision.localOperationId}" is not a conflict '
      '(state: ${original.state.wire})',
    );
  }
  if (decision.conflictId != original.operationId) {
    throw ConflictResolutionException(
      ConflictResolutionFailure.couldNotApply,
      'conflictId "${decision.conflictId}" does not match operation '
      '"${original.operationId}"',
    );
  }

  // Revalidation (§9). The screen was built from the review entry stored at
  // detection; a *second* detection replaces that entry rather than stacking
  // one, so a version that has moved since means the two versions on screen
  // are no longer the two versions being resolved. Only a demonstrable move
  // blocks: with either side unknown there is no evidence, and inventing one
  // would strand a resolvable conflict.
  final entry = (await ref.read(conflictReviewProvider.future))
      .where((e) => e.conflictId == decision.conflictId)
      .firstOrNull;
  if (entry != null &&
      entry.currentVersion != null &&
      decision.currentVersion != null &&
      entry.currentVersion != decision.currentVersion) {
    throw ConflictResolutionException(
      ConflictResolutionFailure.recordChanged,
      'the record behind "${decision.conflictId}" changed again since this '
      'comparison was built — it must be reviewed against the newer version',
    );
  }

  final outbox = ref.read(outboxProvider.notifier);
  final cleaner =
      ref.read(conflictSnapshotCleanersProvider)[original.entityType];

  if (decision.intent == ConflictResolutionIntent.useLocal) {
    final version = decision.currentVersion;
    if (version == null || version.isEmpty) {
      throw ConflictResolutionException(
        ConflictResolutionFailure.couldNotApply,
        'useLocal requires a non-empty current version for '
        '"${decision.conflictId}"',
      );
    }
    await outbox.supersedeConflict(
      originalOperationId: decision.localOperationId,
      resolutionVersion: version,
    );
    await ref.read(conflictReviewProvider.notifier).forget(decision.conflictId);
    if (cleaner != null) await cleaner(original);
    return;
  }

  // useCurrent. The applier is the feature's own writer: it may throw a
  // typed [ConflictResolutionException] to say *why* it could not write
  // (deleted, not permitted, offline), and that reason is passed straight
  // through untouched. A plain `false` means "could not apply" with nothing
  // more specific to say. In every one of those cases the conflict and the
  // local edit are still here.
  final applier =
      ref.read(conflictCurrentAppliersProvider)[original.entityType];
  final applied = applier != null && await applier(original);
  if (!applied) {
    throw ConflictResolutionException(
      ConflictResolutionFailure.couldNotApply,
      'could not apply the current version for "${decision.conflictId}" '
      'locally — the local edit is preserved',
    );
  }
  await outbox.discardConflict(decision.localOperationId);
  await ref.read(conflictReviewProvider.notifier).forget(decision.conflictId);
  if (cleaner != null) await cleaner(original);
}

final conflictDecisionHandlerProvider =
    Provider<ConflictDecisionHandler>((ref) {
  return (decision) => applyConflictResolution(ref, decision);
});
