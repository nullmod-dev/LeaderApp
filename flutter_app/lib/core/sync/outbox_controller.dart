import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'outbox_store.dart';
import 'pending_operation.dart';
import 'sync_state.dart';
import 'uuid_v7.dart';

/// Where the local write outbox is persisted. Override with a real
/// (encrypted-DB backed) [OutboxStore] in a shipping build.
final outboxStoreProvider = Provider<OutboxStore>((ref) {
  return InMemoryOutboxStore();
});

/// The id source for new operations. A test overrides this to make
/// [PendingOperation.operationId] / `idempotencyKey` deterministic; nothing
/// else should read it.
final newOperationIdProvider = Provider<String Function()>((ref) => uuidV7);

/// The live outbox: every [PendingOperation] still owed to the server.
///
/// An [AsyncNotifier] for the same reason `ThemeController` is one — the
/// stored list arrives asynchronously and the app must render in the
/// meantime. It is **the single place a write-operation identity is
/// created** ([enqueue]); the sync coordinator only ever *reads* this list
/// and reports outcomes back through [applyOutcome] / [markSynced].
class OutboxController extends AsyncNotifier<List<PendingOperation>> {
  OutboxStore get _store => ref.read(outboxStoreProvider);

  @override
  Future<List<PendingOperation>> build() => _store.readAll();

  List<PendingOperation> get _current => state.valueOrNull ?? const [];

  Future<void> _reload() async {
    state = AsyncData(await _store.readAll());
  }

  /// Registers a new logical write as pending synchronisation and returns
  /// it. Call this **after** the feature's local write has succeeded — the
  /// user has already been let go; this only records that the write still
  /// has to travel.
  ///
  /// [kind] is a namespaced tag (`inventory.movement.add`). [entityType] /
  /// [entityId] are an opaque pointer for grouping — never a payload, never
  /// a sensitive value.
  /// Re-reads the store into state.
  ///
  /// For the one case a caller cannot otherwise recover from: something
  /// changed the stored operations without going through this controller, so
  /// what is on screen no longer matches what is stored. Cheaper and far
  /// safer than invalidating the provider, which would hand a sync run in
  /// flight a different notifier than the one it started with.
  Future<void> refresh() => _reload();

  Future<PendingOperation> enqueue({
    required String kind,
    String? entityType,
    String? entityId,
  }) async {
    final op = PendingOperation.create(
      kind: kind,
      entityType: entityType,
      entityId: entityId,
      idFactory: ref.read(newOperationIdProvider),
    );
    await _store.upsert(op);
    await _reload();
    return op;
  }

  /// Marks an operation as having an attempt in flight. Used by the
  /// coordinator at the start of a push.
  Future<void> markSyncing(String operationId) =>
      _mutate(operationId, (op) => op.copyWith(state: SyncState.syncing));

  /// Records the result of one push attempt.
  ///
  /// - [SyncState.synced] removes the operation from the outbox.
  /// - [SyncState.failed] bumps the attempt counter and stores the wire
  ///   [problemCode] (code only) for backoff and a "still trying" surface.
  /// - [SyncState.conflict] also bumps the attempt counter (a real attempt
  ///   was made and produced a verdict) and stores [problemCode], but the
  ///   operation stops being [PendingOperation.isRetryable] — see
  ///   `SyncCoordinator` and `sync_conflict_classifier.dart`.
  /// - [SyncState.pending] returns it to the queue untouched otherwise.
  Future<void> applyOutcome(
    String operationId, {
    required SyncState state,
    String? problemCode,
    DateTime? attemptedAt,
  }) async {
    if (state == SyncState.synced) return markSynced(operationId);
    await _mutate(operationId, (op) {
      final attempted =
          state == SyncState.failed || state == SyncState.conflict;
      return op.copyWith(
        state: state,
        attemptCount: attempted ? op.attemptCount + 1 : op.attemptCount,
        lastAttemptAt: attemptedAt ?? DateTime.now(),
        lastProblemCode: problemCode,
        clearLastProblemCode: problemCode == null && !attempted,
      );
    });
  }

  /// Drops an operation once the server has accepted it.
  Future<void> markSynced(String operationId) async {
    await _store.remove(operationId);
    await _reload();
  }

  /// Low-level primitive: returns a [SyncState.conflict] operation to
  /// [SyncState.pending] **with its existing, unchanged**
  /// [PendingOperation.operationId] / [PendingOperation.idempotencyKey] —
  /// never a new identity. Correct only when the retried request body is
  /// known to be identical to the one already committed to that key; a
  /// `useLocal` conflict decision resubmits a **changed** body (a fresh
  /// concurrency version) and must not use this — see [supersedeConflict],
  /// which is what the conflict-resolution flow actually calls
  /// (`FRONTEND-BACKEND-INTEGRATION.md` §5.5). Kept as its own primitive
  /// because it remains the right tool for a same-body retry (a plain
  /// [SyncState.failed] operation already uses the ordinary sync loop for
  /// exactly that, without going through this method at all).
  ///
  /// A no-op (matching [_mutate]'s guard) if [operationId] is not on file —
  /// for example it was already resolved or synced elsewhere.
  Future<void> requeueAfterConflict(String operationId) => _mutate(
        operationId,
        (op) => op.copyWith(
          state: SyncState.pending,
          clearLastProblemCode: true,
        ),
      );

  /// Resolves a `useLocal` conflict decision the way
  /// `FRONTEND-BACKEND-INTEGRATION.md` §5.5 decides: a new logical operation,
  /// not a retry of the stale one.
  ///
  /// **Ordering (create-then-retire, never the reverse):**
  /// 1. [originalOperationId] must still be on file — thrown as a
  ///    [StateError] otherwise, so a caller cannot silently "resolve"
  ///    something that was already resolved or synced elsewhere out from
  ///    under it.
  /// 2. A brand-new [PendingOperation] is minted through the existing
  ///    [PendingOperation.create] factory — new `operationId`, new
  ///    `idempotencyKey`, [PendingOperation.resolvesOperationId] pointing
  ///    back at [originalOperationId], [PendingOperation.currentVersion] set
  ///    from [resolutionVersion] — and stored **durably before** the
  ///    original is touched. If this store write throws, the exception
  ///    propagates and the original operation is exactly where it was:
  ///    still [SyncState.conflict], unresolved, its identity and metadata
  ///    untouched.
  /// 3. Only once that succeeds is the original retired
  ///    ([OutboxStore.remove]). If *this* store write throws, the exception
  ///    still propagates, but the replacement is already durable — the user
  ///    is left with both operations on file, never with neither.
  ///
  /// **Repeated submission is idempotent.** If a replacement already exists
  /// for [originalOperationId] (this ran to completion before — a resumed
  /// app, a double submission after a partial failure), no second
  /// replacement is minted: the existing one is returned, and the original
  /// is retired if it is somehow still present *and still a conflict*
  /// (recovering a run that created the replacement but failed to retire
  /// the original — never touching an operation something else already
  /// moved on from).
  ///
  /// **Validation, before anything is written.** [originalOperationId] must
  /// name an operation that is still [SyncState.conflict] — a `pending`,
  /// `syncing`, `failed` or `synced` operation cannot be superseded, and
  /// this throws rather than silently mutating one. [resolutionVersion]
  /// must be non-null and non-empty — a `useLocal` decision with no
  /// concurrency version to carry forward is a caller bug, not something to
  /// paper over with a blank value on the wire. Both checks run before any
  /// [OutboxStore] call, so a rejected call never upserts or removes
  /// anything.
  Future<PendingOperation> supersedeConflict({
    required String originalOperationId,
    String? resolutionVersion,
  }) async {
    final existingReplacement = _current
        .where((op) => op.resolvesOperationId == originalOperationId)
        .firstOrNull;
    if (existingReplacement != null) {
      final original = _current
          .where((op) => op.operationId == originalOperationId)
          .firstOrNull;
      if (original != null && original.state == SyncState.conflict) {
        await _store.remove(originalOperationId);
        await _reload();
      }
      return existingReplacement;
    }

    final original = _current
        .where((op) => op.operationId == originalOperationId)
        .firstOrNull;
    if (original == null) {
      throw StateError(
        'no conflicted operation "$originalOperationId" to resolve — it may '
        'already have been resolved or synced elsewhere',
      );
    }
    if (original.state != SyncState.conflict) {
      throw StateError(
        'operation "$originalOperationId" is not a conflict '
        '(state: ${original.state.wire}) and cannot be superseded',
      );
    }
    if (resolutionVersion == null || resolutionVersion.isEmpty) {
      throw StateError(
        'supersedeConflict requires a non-empty resolutionVersion for '
        '"$originalOperationId" — a useLocal decision with no current '
        'version to carry forward cannot be resolved',
      );
    }

    final replacement = PendingOperation.create(
      kind: original.kind,
      entityType: original.entityType,
      entityId: original.entityId,
      resolvesOperationId: originalOperationId,
      currentVersion: resolutionVersion,
      idFactory: ref.read(newOperationIdProvider),
    );

    // Durably created first — an exception here leaves `original` untouched.
    await _store.upsert(replacement);
    await _reload();

    // Retired only now — an exception here leaves both operations on file.
    await _store.remove(originalOperationId);
    await _reload();

    return replacement;
  }

  /// Applies the **useCurrent** half of a conflict decision once the owning
  /// feature has already applied the current/shared record to its own local
  /// state (`features/conflict/data/conflict_outbox_resolver.dart`): the
  /// pending write is no longer owed and is dropped. This is a deliberate,
  /// reviewed removal — distinct from the silent loss the outbox must never
  /// cause on its own — and it never contacts a transport or claims the
  /// server was told anything.
  ///
  /// (There is no corresponding **reviewLater** method: leaving a
  /// [SyncState.conflict] operation untouched — calling nothing — is exactly
  /// what preserves it for later review.)
  Future<void> discardConflict(String operationId) async {
    await _store.remove(operationId);
    await _reload();
  }

  Future<void> _mutate(
    String operationId,
    PendingOperation Function(PendingOperation) f,
  ) async {
    final idx = _current.indexWhere((op) => op.operationId == operationId);
    if (idx < 0) return;
    final next = f(_current[idx]);
    await _store.upsert(next);
    await _reload();
  }
}

final outboxProvider =
    AsyncNotifierProvider<OutboxController, List<PendingOperation>>(
  OutboxController.new,
);

/// How many operations the *ordinary sync loop* still owes the server — the
/// number Settings shows as "بانتظار المزامنة". `0` while the outbox is
/// still loading. Deliberately excludes [SyncState.conflict] operations:
/// they are not waiting for a sync attempt, they are waiting for a human —
/// see [conflictOperationsCountProvider].
final pendingOperationsCountProvider = Provider<int>((ref) {
  final ops = ref.watch(outboxProvider).valueOrNull ?? const [];
  return ops.where((op) => op.isRetryable).length;
});

/// How many operations are waiting for a human conflict decision — the
/// quiet "توجد تغييرات تحتاج مراجعة" attention state in Settings (roadmap
/// §4/§5). `0` while the outbox is still loading, and always `0` in the
/// shipped app today: `sync_conflict_classifier.dart`'s default classifier
/// does recognise the agreed `stale_write` code (Task 3), but there is no
/// real `SyncTransport` yet to ever return it.
final conflictOperationsCountProvider = Provider<int>((ref) {
  final ops = ref.watch(outboxProvider).valueOrNull ?? const [];
  return ops.where((op) => op.needsReview).length;
});
