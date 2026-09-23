import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'outbox_controller.dart';
import 'pending_operation.dart';
import 'sync_coordinator.dart';
import 'sync_state.dart';

/// What the app can honestly say about the connection.
///
/// MTM has no connectivity plugin and no separate reachability probe: the
/// only evidence it ever gets is what a sync attempt came back with. So this
/// has three values, not two — [unknown] is the state before anything has
/// been proved, and the UI shows no connection claim at all for it rather
/// than guessing "متصل".
enum SyncConnection { unknown, online, offline }

/// The single headline the Sync Center leads with.
///
/// Exactly one is true at a time, resolved by the priority in
/// [buildSyncOverview]. Ordered here worst-to-best for readability only; the
/// priority lives in one place and is covered by test.
enum SyncHealth {
  /// A run is in flight right now.
  syncing,

  /// At least one change is waiting on a human decision. It outranks
  /// everything below because no amount of retrying or reconnecting clears
  /// it — only the user can.
  needsReview,

  /// There is work owed to the server and the last attempt could not reach
  /// it. Nothing is wrong with the data; there is no connection.
  offline,

  /// An attempt reached a verdict that was neither acceptance nor a
  /// conflict. Retryable, and the local change still stands.
  failed,

  /// Work is saved locally and has not been attempted yet.
  pending,

  /// Nothing is owed to the server.
  upToDate,
}

/// Everything the Sync Center renders, derived once from the outbox and the
/// coordinator's status.
///
/// Deliberately carries no Arabic: the copy lives in `strings.dart` and is
/// resolved by the widget, so this stays a pure value a test can assert on.
@immutable
class SyncOverview {
  const SyncOverview({
    required this.health,
    required this.connection,
    required this.waitingCount,
    required this.failedCount,
    required this.reviewCount,
    required this.isSyncing,
    this.lastSyncedAt,
  });

  final SyncHealth health;
  final SyncConnection connection;

  /// Saved locally, never attempted (or in flight this run).
  final int waitingCount;

  /// Attempted, not accepted, still owed to the server.
  final int failedCount;

  /// Waiting on a human decision. Never retried automatically.
  final int reviewCount;

  final bool isSyncing;

  /// When a run last got at least one change accepted. `null` means no sync
  /// has ever completed on this device — not a failure.
  final DateTime? lastSyncedAt;

  /// Everything the ordinary retry loop will pick up on the next run.
  /// Conflicts are excluded: they are not retried, they are reviewed.
  int get pendingCount => waitingCount + failedCount;

  bool get hasUnsyncedWork => pendingCount > 0;
  bool get needsReview => reviewCount > 0;
  bool get isOffline => connection == SyncConnection.offline;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncOverview &&
          other.health == health &&
          other.connection == connection &&
          other.waitingCount == waitingCount &&
          other.failedCount == failedCount &&
          other.reviewCount == reviewCount &&
          other.isSyncing == isSyncing &&
          other.lastSyncedAt == lastSyncedAt;

  @override
  int get hashCode => Object.hash(health, connection, waitingCount, failedCount,
      reviewCount, isSyncing, lastSyncedAt);

  @override
  String toString() => 'SyncOverview(${health.name}, ${connection.name}, '
      'waiting: $waitingCount, failed: $failedCount, review: $reviewCount)';
}

/// The problem code a push carries when it could not leave the device.
const String _offlineProblemCode = 'offline';

/// What the last run proved about the connection — nothing more.
SyncConnection connectionFromSync({
  required SyncStatus status,
  required List<PendingOperation> operations,
}) {
  // The most recent evidence there is, and the only kind that survives a
  // relaunch: a change whose last attempt could not leave the device. It is
  // checked before the run outcome because a run can succeed for the first
  // change and lose the connection on the second — "partial" would then
  // report a connection that is already gone. An operation that later gets
  // through is removed from the outbox, so this evidence cannot go stale.
  final strandedOffline = operations.any((op) =>
      op.state == SyncState.failed &&
      op.lastProblemCode == _offlineProblemCode);
  if (strandedOffline) return SyncConnection.offline;

  switch (status.lastOutcome) {
    case SyncRunOutcome.offline:
      return SyncConnection.offline;
    // The server answered: it accepted something, or it returned a verdict
    // this client understood. Either way the device reached it.
    case SyncRunOutcome.allSynced:
    case SyncRunOutcome.partial:
    case SyncRunOutcome.needsReview:
      return SyncConnection.online;
    // An error that is neither acceptance nor a conflict proves nothing
    // either way — a dead network and a failing server look the same here,
    // so the screen claims neither.
    case SyncRunOutcome.failed:
      return SyncConnection.unknown;
    case SyncRunOutcome.nothingPending:
    case null:
      // Nothing has been proved this session, and no change is stranded for
      // lack of a connection. The screen claims neither.
      return SyncConnection.unknown;
  }
}

/// Reduces the outbox and the coordinator's status to the one thing the Sync
/// Center leads with.
///
/// The priority is the whole point of this function, so it lives here and
/// nowhere else:
///
/// 1. **syncing** — a run is happening; say so before anything else.
/// 2. **needsReview** — only a human clears it, so it outranks conditions
///    that time or a retry would fix on their own.
/// 3. **offline** — while work is owed. With nothing owed there is nothing
///    the connection is blocking, and the connection chip already says it.
/// 4. **failed** — attempted, not accepted, still safe.
/// 5. **pending** — saved, not yet attempted.
/// 6. **upToDate**.
SyncOverview buildSyncOverview({
  required List<PendingOperation> operations,
  required SyncStatus status,
}) {
  var waiting = 0;
  var failed = 0;
  var review = 0;
  for (final op in operations) {
    switch (op.state) {
      case SyncState.pending:
      case SyncState.syncing:
        waiting++;
      case SyncState.failed:
        failed++;
      case SyncState.conflict:
        review++;
      case SyncState.synced:
        break;
    }
  }

  final connection = connectionFromSync(status: status, operations: operations);

  final SyncHealth health;
  if (status.isSyncing) {
    health = SyncHealth.syncing;
  } else if (review > 0) {
    health = SyncHealth.needsReview;
  } else if (connection == SyncConnection.offline && waiting + failed > 0) {
    health = SyncHealth.offline;
  } else if (failed > 0) {
    health = SyncHealth.failed;
  } else if (waiting > 0) {
    health = SyncHealth.pending;
  } else {
    health = SyncHealth.upToDate;
  }

  return SyncOverview(
    health: health,
    connection: connection,
    waitingCount: waiting,
    failedCount: failed,
    reviewCount: review,
    isSyncing: status.isSyncing,
    lastSyncedAt: status.lastSyncedAt,
  );
}

/// The Sync Center's single read model.
///
/// Keeps the outbox's `AsyncValue` shape so the screen can render a real
/// loading state instead of claiming "كل التغييرات متزامنة" while the outbox
/// is still being read, and a real error state instead of an empty page.
final syncOverviewProvider = Provider<AsyncValue<SyncOverview>>((ref) {
  final operations = ref.watch(outboxProvider);
  final status = ref.watch(syncCoordinatorProvider);
  return operations.whenData(
    (list) => buildSyncOverview(operations: list, status: status),
  );
});
