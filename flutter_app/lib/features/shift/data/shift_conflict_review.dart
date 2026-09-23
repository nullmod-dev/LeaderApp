import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem/problem.dart';
import '../../../core/sync/pending_operation.dart';
import '../../conflict/data/conflict_current_application.dart';
import '../../conflict/data/conflict_review_recording.dart';
import '../../conflict/domain/conflict_models.dart';
import '../../conflict/domain/conflict_review_entry.dart';
import '../presentation/shift_conflict_adapter.dart';
import 'shift_providers.dart';

/// The Shift feature's representative typed conflict-review path — the
/// smallest real registration `FRONTEND-BACKEND-INTEGRATION.md` §7 asks for
/// in place of the empty production composer registry.
///
/// Both functions below read the *local* side from the same
/// `shiftRepositoryProvider` every other shift screen already reads (the
/// user's unsynced edit is still sitting there — a failed push never
/// touches local state) and the *current* side from
/// `shiftConflictSnapshotStoreProvider`, the feature-owned snapshot a future
/// transport integration captures at `409` detection time. Neither function
/// fabricates a "current" record: with no captured snapshot, both return the
/// same honest "nothing to show/apply" answer their generic seams already
/// define (`ConflictReviewComposer`, `ConflictCurrentApplier`).

/// Builds the durable [ConflictReviewEntry] for one conflicted shift write,
/// or `null` when there is nothing safe to show yet.
Future<ConflictReviewEntry?> composeShiftConflictReview(
  Ref ref,
  PendingOperation operation,
) async {
  if (operation.entityType != 'shift') return null;
  final entityId = operation.entityId;
  if (entityId == null) return null;

  final snapshot = await ref
      .read(shiftConflictSnapshotStoreProvider)
      .read(operation.operationId);
  if (snapshot == null) return null;

  final localResult = await ref.read(shiftRepositoryProvider).byId(entityId);
  final local = localResult.when(
    success: (data, {stale = false}) => data,
    failure: (_, __) => null,
    offline: (_) => null,
  );
  if (local == null) return null;

  final presentation = presentShiftConflict(
    conflictId: operation.operationId,
    localOperationId: operation.operationId,
    local: local,
    current: snapshot.current,
    baseVersion: snapshot.baseVersion,
    currentVersion: snapshot.currentVersion,
  );

  return ConflictReviewEntry.fromPresentation(
    presentation,
    detectedAt: DateTime.now(),
  );
}

/// Applies a conflicted shift write's captured "current" snapshot to the
/// local repository — the `useCurrent` half of resolving a shift conflict.
/// Returns whether the local write actually succeeded; a missing snapshot
/// or a failed repository write returns `false` rather than throwing, so
/// `applyConflictResolution` can treat it exactly like any other applier
/// failure ("do not resolve").
///
/// Deliberately does **not** remove the snapshot itself — see
/// [clearShiftConflictSnapshot] for why cleanup is a separate, later step.
Future<bool> applyShiftConflictCurrentVersion(
  Ref ref,
  PendingOperation operation,
) async {
  if (operation.entityType != 'shift') return false;

  final snapshot = await ref
      .read(shiftConflictSnapshotStoreProvider)
      .read(operation.operationId);
  if (snapshot == null) return false;

  final result =
      await ref.read(shiftRepositoryProvider).update(snapshot.current);
  return result.when(
    success: (_, {stale = false}) => true,
    // Two refusals have something specific and useful to tell the user, so
    // they are named rather than flattened into "could not apply": the record
    // is gone, or this session may not write it. Anything else stays a plain
    // `false` — the generic "could not apply", which the resolver already
    // handles without discarding anything.
    failure: (_, code) => switch (ProblemCode.parse(code)) {
      ProblemCode.notFound => throw ConflictResolutionException(
          ConflictResolutionFailure.recordDeleted,
          'the shift this change belongs to no longer exists',
        ),
      ProblemCode.notPermitted => throw ConflictResolutionException(
          ConflictResolutionFailure.notPermitted,
          'this session may not write the current shift version',
        ),
      _ => false,
    },
    offline: (_) => throw ConflictResolutionException(
      ConflictResolutionFailure.offline,
      'the current shift version could not be written without a connection',
    ),
  );
}

/// Removes the captured snapshot for one conflicted shift operation.
///
/// Called only after the outbox resolution that consumed it (`useLocal` or
/// `useCurrent`) has already succeeded (`conflict_outbox_resolver.dart`'s
/// ordering) — never from inside [applyShiftConflictCurrentVersion] itself,
/// so a failure retiring the outbox operation after a successful local
/// apply still leaves the snapshot in place for a retry.
Future<void> clearShiftConflictSnapshot(
  Ref ref,
  PendingOperation operation,
) async {
  if (operation.entityType != 'shift') return;
  await ref
      .read(shiftConflictSnapshotStoreProvider)
      .remove(operation.operationId);
}

/// Installs the Shift composer/applier/cleaner over `features/conflict`'s
/// empty default registries.
///
/// Applied at the app's composition root (`main.dart`), the same pattern
/// `conflictReviewOverrides` already uses, so `features/conflict` keeps
/// knowing nothing about `features/shift`.
final List<Override> shiftConflictReviewOverrides = [
  conflictReviewComposersProvider.overrideWith(
    (ref) =>
        {'shift': (operation) => composeShiftConflictReview(ref, operation)},
  ),
  conflictCurrentAppliersProvider.overrideWith(
    (ref) => {
      'shift': (operation) => applyShiftConflictCurrentVersion(ref, operation),
    },
  ),
  conflictSnapshotCleanersProvider.overrideWith(
    (ref) => {
      'shift': (operation) => clearShiftConflictSnapshot(ref, operation),
    },
  ),
];
