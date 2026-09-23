import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/pending_operation.dart';

/// Applies the typed "current" record captured for one conflicted
/// [PendingOperation] to the owning feature's own local state/repository —
/// the local half of a `useCurrent` decision.
///
/// Returns whether the local application actually succeeded. `false` (never
/// an exception, though a thrown error is treated as `false` too — see
/// `conflict_outbox_resolver.dart`) means "do not resolve": the caller must
/// not retire the operation and must not drop its review metadata. This
/// mirrors [ConflictReviewComposer]'s "returning null/false is a legitimate
/// answer, not a failure" contract — a snapshot that is missing, invalid, or
/// unsupported is an honest reason to keep the conflict exactly as it was,
/// not a reason to lose the user's local edit.
///
/// Owned by the feature that owns the record, for the same reason a
/// composer is: only that feature knows how to apply its own typed snapshot
/// to its own repository (`ShiftRepository.update`, for the Shift adapter).
///
/// Deliberately does **not** also remove the snapshot it just applied — see
/// [ConflictSnapshotCleaner] for why that is a separate step with a
/// separate, later moment to run in.
typedef ConflictCurrentApplier = Future<bool> Function(
  PendingOperation operation,
);

/// Appliers by `PendingOperation.entityType`.
///
/// **Empty today, deliberately** — same reasoning as
/// `conflictReviewComposersProvider`: a feature joins by overriding this
/// provider once it has a real captured "current" snapshot to apply, at the
/// composition root (`main.dart`), so `features/conflict` never imports a
/// feature.
final conflictCurrentAppliersProvider =
    Provider<Map<String, ConflictCurrentApplier>>(
  (ref) => const <String, ConflictCurrentApplier>{},
);

/// Removes whatever feature-owned snapshot backed one conflicted
/// [PendingOperation]'s composer/applier — called only after the outbox
/// resolution that consumed it (`useLocal` or `useCurrent`) has **already
/// succeeded** (`conflict_outbox_resolver.dart`'s ordering).
///
/// Deliberately a separate step from [ConflictCurrentApplier], not folded
/// into it: applying a snapshot and retiring the outbox operation it
/// resolves are two different moments with two different failure
/// consequences. An applier that deleted its own snapshot as part of
/// "applying" it could not be safely retried if the *outbox* half of the
/// resolution (`OutboxController.discardConflict` /
/// `OutboxController.supersedeConflict`) failed afterwards — the snapshot
/// required to retry would already be gone. This runs only once that half
/// has actually succeeded.
typedef ConflictSnapshotCleaner = Future<void> Function(
  PendingOperation operation,
);

/// Cleaners by `PendingOperation.entityType`. Same empty-by-default,
/// composition-root-registered pattern as [ConflictReviewComposer] /
/// [ConflictCurrentApplier].
final conflictSnapshotCleanersProvider =
    Provider<Map<String, ConflictSnapshotCleaner>>(
  (ref) => const <String, ConflictSnapshotCleaner>{},
);
