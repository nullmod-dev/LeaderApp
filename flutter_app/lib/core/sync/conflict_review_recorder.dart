import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pending_operation.dart';
import 'sync_state.dart';

/// Called by [SyncCoordinator] the moment a push is classified as a
/// stale-write conflict, so the *safe review metadata* for that conflict can
/// be stored durably before the user walks away from connectivity (roadmap
/// §4; `FRONTEND-BACKEND-INTEGRATION.md` §5.4 "current-as-of-detection
/// snapshot").
///
/// It is a **hook, not a policy**. Core sync stays payload-free and
/// feature-agnostic: it hands over the operation it just moved to
/// [SyncState.conflict] and knows nothing about what — if anything — the
/// owning feature is able to store for it. Everything domain-shaped
/// (record title, the feature-approved differences, the typed snapshot)
/// lives behind this typedef, in `features/conflict`.
///
/// Contract for an implementation:
///
/// - It runs **after** the operation is already durably [SyncState.conflict].
///   Recording review metadata is an enrichment; the conflict itself is
///   preserved and counted from the outbox whether this succeeds or not.
/// - It must never navigate, never show UI, and never contact a transport.
///   Auto Sync runs it in the background while the user is doing something
///   else (roadmap §4).
/// - It may legitimately do nothing when the owning feature cannot produce
///   safe, displayable metadata. That is not an error — the Needs Review
///   inbox renders such an entry as "details unavailable" rather than
///   inventing any.
typedef ConflictReviewRecorder = Future<void> Function(
  PendingOperation operation,
);

/// The default: record nothing.
///
/// Deliberately the default rather than the real implementation, so
/// `core/sync` never imports a feature. The app installs the real recorder
/// as a `ProviderScope` override in `main.dart`
/// (`conflictReviewOverrides`); a test that does not care about review
/// metadata gets this no-op and still sees the conflict preserved and
/// counted.
Future<void> noopConflictReviewRecorder(PendingOperation operation) async {}

final conflictReviewRecorderProvider = Provider<ConflictReviewRecorder>(
  (ref) => noopConflictReviewRecorder,
);
