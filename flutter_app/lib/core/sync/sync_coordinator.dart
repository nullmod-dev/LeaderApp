import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../result/result.dart';
import 'conflict_review_recorder.dart';
import 'outbox_controller.dart';
import 'pending_operation.dart';
import 'sync_conflict_classifier.dart';
import 'sync_state.dart';
import 'sync_transport.dart';

/// What kicked off a sync run. **Behaviour does not branch on this** — Auto
/// Sync and Manual Sync run the exact same code over the exact same outbox
/// (roadmap §3). It is carried only so a run can be attributed in a log or a
/// test.
enum SyncTrigger { auto, manual }

/// Coarse phase of the coordinator, for the UI.
enum SyncPhase { idle, syncing }

/// The outcome of one run, for the Settings surface. No backend jargon.
enum SyncRunOutcome {
  /// Nothing was pending — a no-op run.
  nothingPending,

  /// Every pending operation reached the server.
  allSynced,

  /// Some reached the server, some are still pending.
  partial,

  /// Could not reach the server; everything stays pending (not an error).
  offline,

  /// Attempts failed for a reason other than connectivity; stays pending.
  failed,

  /// At least one operation was classified as a stale-write conflict this
  /// run (roadmap §4/§6) and now waits for a human decision — not a scary
  /// generic failure, and not retried again automatically.
  needsReview,
}

/// Immutable snapshot the Settings sync surface renders.
@immutable
class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.lastRunAt,
    this.lastSyncedAt,
    this.lastOutcome,
    this.lastTrigger,
  });

  final SyncPhase phase;

  /// When a run last finished (any outcome).
  final DateTime? lastRunAt;

  /// When a run last got at least one operation accepted by the server.
  /// PROVISIONAL — held in memory only; a durable "last successful sync"
  /// belongs with the real outbox store. See
  /// `FRONTEND-BACKEND-INTEGRATION.md` §3.
  final DateTime? lastSyncedAt;

  final SyncRunOutcome? lastOutcome;
  final SyncTrigger? lastTrigger;

  bool get isSyncing => phase == SyncPhase.syncing;

  SyncStatus copyWith({
    SyncPhase? phase,
    DateTime? lastRunAt,
    DateTime? lastSyncedAt,
    SyncRunOutcome? lastOutcome,
    SyncTrigger? lastTrigger,
  }) =>
      SyncStatus(
        phase: phase ?? this.phase,
        lastRunAt: lastRunAt ?? this.lastRunAt,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastOutcome: lastOutcome ?? this.lastOutcome,
        lastTrigger: lastTrigger ?? this.lastTrigger,
      );
}

/// Result of a single [SyncCoordinator.syncNow] call.
@immutable
class SyncRunSummary {
  const SyncRunSummary({
    required this.trigger,
    required this.outcome,
    required this.attempted,
    required this.synced,
  });

  final SyncTrigger trigger;
  final SyncRunOutcome outcome;
  final int attempted;
  final int synced;

  int get stillPending => attempted - synced;
}

/// Where a pushed operation is sent. Override in a real build.
final syncTransportProvider = Provider<SyncTransport>((ref) {
  return const OfflineSyncTransport();
});

/// The one engine behind **both** sync paths.
///
/// - **Auto Sync** (primary) calls [syncNow] with [SyncTrigger.auto] on the
///   lifecycle/connectivity conditions wired in `SyncScheduler`.
/// - **Manual Sync** (fallback) calls [syncNow] with [SyncTrigger.manual]
///   from the Settings button.
///
/// Both drain the same [outboxProvider]. The coordinator **never creates a
/// [PendingOperation]** — it reads what `enqueue` already stored and reports
/// each attempt's outcome back to the outbox with the operation's existing
/// identity, so a retry (this run, a later auto run, after a restart) keeps
/// the same `idempotencyKey`.
class SyncCoordinator extends Notifier<SyncStatus> {
  Future<SyncRunSummary>? _inFlight;

  @override
  SyncStatus build() => const SyncStatus();

  /// Requests synchronisation of everything already pending. Re-entrant
  /// calls (a manual tap while an auto run is going, connectivity flapping)
  /// join the run in progress instead of starting a second one — so this
  /// can never fan a write out twice.
  Future<SyncRunSummary> syncNow({required SyncTrigger trigger}) {
    return _inFlight ??= _run(trigger).whenComplete(() => _inFlight = null);
  }

  /// Hands a just-classified conflict to whatever the app installed as its
  /// [ConflictReviewRecorder] (nothing, by default — see that file).
  ///
  /// Deliberately best-effort. The operation is already durably
  /// [SyncState.conflict] by the time this runs and is already counted from
  /// the outbox, so failing to enrich it must not abort the run, must not
  /// re-throw into the sync loop, and cannot lose the user's work. The
  /// Needs Review inbox lists such a conflict as "details unavailable"
  /// rather than showing nothing.
  Future<void> _recordForReview(PendingOperation operation) async {
    try {
      await ref.read(conflictReviewRecorderProvider)(operation);
    } catch (error) {
      assert(() {
        debugPrint('SyncCoordinator: could not record review metadata for a '
            'conflicted operation — $error');
        return true;
      }());
    }
  }

  Future<SyncRunSummary> _run(SyncTrigger trigger) async {
    final outbox = ref.read(outboxProvider.notifier);
    final transport = ref.read(syncTransportProvider);
    final isConflict = ref.read(syncConflictClassifierProvider);

    // `isRetryable`, not `isUnsynced`: a `SyncState.conflict` operation is
    // still unsynced but must not be picked up by the ordinary retry loop —
    // it waits for a human decision (roadmap §7).
    final pending = (await ref.read(outboxProvider.future))
        .where((op) => op.isRetryable)
        .toList();

    if (pending.isEmpty) {
      final summary = SyncRunSummary(
        trigger: trigger,
        outcome: SyncRunOutcome.nothingPending,
        attempted: 0,
        synced: 0,
      );
      state = state.copyWith(
        phase: SyncPhase.idle,
        lastRunAt: DateTime.now(),
        lastOutcome: summary.outcome,
        lastTrigger: trigger,
      );
      return summary;
    }

    state = state.copyWith(phase: SyncPhase.syncing, lastTrigger: trigger);

    var synced = 0;
    var hitOffline = false;
    var hitFailure = false;
    var hitConflict = false;

    for (final op in pending) {
      await outbox.markSyncing(op.operationId);
      final Result<void> result = await transport.push(op);
      final now = DateTime.now();

      await result.when(
        success: (_, {stale = false}) async {
          synced++;
          await outbox.applyOutcome(op.operationId,
              state: SyncState.synced, attemptedAt: now);
        },
        offline: (_) async {
          hitOffline = true;
          await outbox.applyOutcome(op.operationId,
              state: SyncState.failed,
              problemCode: 'offline',
              attemptedAt: now);
        },
        failure: (message, code) async {
          if (isConflict(code)) {
            // A stale-write conflict, not a temporary failure: classify it
            // and stop — no exception, no navigation, nothing that would
            // pull the user away from whatever they are doing right now
            // (roadmap §4). The operation keeps its identity and simply
            // waits for review.
            hitConflict = true;
            await outbox.applyOutcome(op.operationId,
                state: SyncState.conflict, problemCode: code, attemptedAt: now);
            // Detection is the only moment connectivity is guaranteed, so
            // it is the only moment safe review metadata can be captured
            // for an offline-later decision (roadmap §4;
            // FRONTEND-BACKEND-INTEGRATION.md §5.4).
            await _recordForReview(op);
            return;
          }
          hitFailure = true;
          await outbox.applyOutcome(op.operationId,
              state: SyncState.failed,
              problemCode: code ?? 'network',
              attemptedAt: now);
        },
      );

      // No point pushing the rest of the queue through a dead connection.
      if (hitOffline) break;
    }

    final outcome = synced == pending.length
        ? SyncRunOutcome.allSynced
        : synced > 0
            ? SyncRunOutcome.partial
            : hitConflict
                ? SyncRunOutcome.needsReview
                : hitOffline
                    ? SyncRunOutcome.offline
                    : hitFailure
                        ? SyncRunOutcome.failed
                        : SyncRunOutcome.partial;

    final finishedAt = DateTime.now();
    state = state.copyWith(
      phase: SyncPhase.idle,
      lastRunAt: finishedAt,
      lastSyncedAt: synced > 0 ? finishedAt : null,
      lastOutcome: outcome,
      lastTrigger: trigger,
    );

    return SyncRunSummary(
      trigger: trigger,
      outcome: outcome,
      attempted: pending.length,
      synced: synced,
    );
  }
}

final syncCoordinatorProvider =
    NotifierProvider<SyncCoordinator, SyncStatus>(SyncCoordinator.new);
