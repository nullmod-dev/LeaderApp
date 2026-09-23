import 'package:flutter/foundation.dart';

import 'sync_state.dart';
import 'uuid_v7.dart';

/// One logical local write, waiting to reach the server.
///
/// ## The identity rule (roadmap §5)
///
/// [idempotencyKey] belongs to the **logical operation**, not to an HTTP
/// attempt. It is minted once, here, when the operation is created, and it
/// is the value a future transport puts in `Idempotency-Key`. A retry —
/// automatic, manual, after a restart — reuses the record and therefore the
/// same key, until the operation is [SyncState.synced] or a human resolves
/// it out of [SyncState.conflict]. A `useCurrent` decision retires the
/// operation outright (`OutboxController.discardConflict`); a `useLocal`
/// decision does **not** reuse this identity — it mints a brand-new
/// operation that references this one through [resolvesOperationId]
/// (`OutboxController.supersedeConflict`,
/// `FRONTEND-BACKEND-INTEGRATION.md` §5.5). Nothing else regenerates it.
///
/// ## What this record deliberately does NOT hold
///
/// The write's **payload**. Attendance rows, stock movements and the like
/// are domain data (some of it sensitive — `DATA-NEEDS.md` §3.3) and they
/// stay with the feature's own local storage / the future SQLCipher tables.
/// This record is pure sync metadata: an identity, a kind, a coarse
/// reference for grouping and de-duplication, and attempt bookkeeping.
/// Keeping it payload-free is what lets it live anywhere and what stops
/// sensitive fields being copied into a second place. [resolvesOperationId]
/// and [currentVersion] are sync metadata in the same sense — an opaque
/// reference and an opaque concurrency token, never the edited fields
/// themselves.
@immutable
class PendingOperation {
  const PendingOperation({
    required this.operationId,
    required this.idempotencyKey,
    required this.kind,
    required this.createdAt,
    this.entityType,
    this.entityId,
    this.state = SyncState.pending,
    this.attemptCount = 0,
    this.lastAttemptAt,
    this.lastProblemCode,
    this.resolvesOperationId,
    this.currentVersion,
  });

  /// Creates a brand-new operation with a fresh identity. `idFactory` is
  /// injectable so a test can pin the value; production passes nothing and
  /// gets [uuidV7].
  ///
  /// [resolvesOperationId] / [currentVersion] are set when this call builds
  /// the **replacement** operation for a `useLocal` conflict decision
  /// (`OutboxController.supersedeConflict`) — an ordinary `enqueue` leaves
  /// both `null`.
  factory PendingOperation.create({
    required String kind,
    String? entityType,
    String? entityId,
    String? resolvesOperationId,
    String? currentVersion,
    DateTime Function()? clock,
    String Function()? idFactory,
  }) {
    final id = (idFactory ?? uuidV7)();
    return PendingOperation(
      operationId: id,
      // Same value, named separately: `operationId` is how the client
      // refers to the row; `idempotencyKey` is what goes on the wire. They
      // coincide today; a future contract could diverge them without
      // touching callers.
      idempotencyKey: id,
      kind: kind,
      entityType: entityType,
      entityId: entityId,
      resolvesOperationId: resolvesOperationId,
      currentVersion: currentVersion,
      createdAt: (clock ?? DateTime.now)(),
    );
  }

  /// Local row identity (UUIDv7).
  final String operationId;

  /// The value a future `Idempotency-Key` header carries. Stable for the
  /// life of the operation.
  final String idempotencyKey;

  /// A namespaced tag the owning feature chooses, e.g.
  /// `inventory.movement.add`, `shift.attendance.mark`. Used to route the
  /// operation to the right transport later and to describe it to the user
  /// ("waiting to sync") — never the payload itself.
  final String kind;

  /// Coarse pointer to the affected record, for UI grouping and so a second
  /// write to the same entity can be recognised. Both halves optional; no
  /// sensitive value belongs here (an opaque id only).
  final String? entityType;
  final String? entityId;

  final DateTime createdAt;

  final SyncState state;

  /// How many sync attempts this operation has had. Drives backoff in the
  /// coordinator; shown to the user only as a coarse "still trying".
  final int attemptCount;
  final DateTime? lastAttemptAt;

  /// The *wire code* of the last failed attempt (e.g. `offline`, `server`),
  /// for diagnostics and backoff. Never the server `detail` text, never a
  /// payload — see `FRONTEND-BACKEND-INTEGRATION.md` §2 / §16.
  final String? lastProblemCode;

  /// Set only on a `useLocal` replacement operation
  /// (`OutboxController.supersedeConflict`): the `operationId` of the
  /// original conflicted operation this one resolves. `null` for every
  /// ordinary operation. A backend/audit log can stitch "this write resolves
  /// that conflict" together from this field alone
  /// (`FRONTEND-BACKEND-INTEGRATION.md` §5.5.2).
  final String? resolvesOperationId;

  /// Set only on a `useLocal` replacement operation: the
  /// `ConflictPresentation.currentVersion`-equivalent concurrency token the
  /// decision was made against, carried so the future real resolution write
  /// can send `version: <currentVersion>` in its request body instead of the
  /// stale value the original operation was minted against
  /// (`FRONTEND-BACKEND-INTEGRATION.md` §5.5). Opaque — never parsed or
  /// compared here, exactly like `ConflictPresentation.currentVersion`.
  final String? currentVersion;

  /// True for a `useLocal` replacement operation — see [resolvesOperationId].
  bool get isConflictResolution => resolvesOperationId != null;

  bool get isUnsynced => state.isUnsynced;

  /// True when the ordinary sync loop (auto or manual) may push this
  /// operation again. `false` for [SyncState.conflict] — see
  /// [SyncState.isRetryable].
  bool get isRetryable => state.isRetryable;

  /// True only while [state] is [SyncState.conflict] — this operation is
  /// waiting for a human decision, not another automatic retry.
  bool get needsReview => state.needsReview;

  PendingOperation copyWith({
    SyncState? state,
    int? attemptCount,
    DateTime? lastAttemptAt,
    String? lastProblemCode,
    bool clearLastProblemCode = false,
  }) =>
      PendingOperation(
        operationId: operationId,
        idempotencyKey: idempotencyKey,
        kind: kind,
        createdAt: createdAt,
        entityType: entityType,
        entityId: entityId,
        state: state ?? this.state,
        attemptCount: attemptCount ?? this.attemptCount,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        lastProblemCode: clearLastProblemCode
            ? null
            : (lastProblemCode ?? this.lastProblemCode),
        resolvesOperationId: resolvesOperationId,
        currentVersion: currentVersion,
      );

  Map<String, dynamic> toJson() => {
        'operationId': operationId,
        'idempotencyKey': idempotencyKey,
        'kind': kind,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (entityType != null) 'entityType': entityType,
        if (entityId != null) 'entityId': entityId,
        'state': state.wire,
        'attemptCount': attemptCount,
        if (lastAttemptAt != null)
          'lastAttemptAt': lastAttemptAt!.toUtc().toIso8601String(),
        if (lastProblemCode != null) 'lastProblemCode': lastProblemCode,
        if (resolvesOperationId != null)
          'resolvesOperationId': resolvesOperationId,
        if (currentVersion != null) 'currentVersion': currentVersion,
      };

  /// Round-trips a stored operation. [resolvesOperationId] / [currentVersion]
  /// are read as `null` when absent — a record written before this pair of
  /// fields existed still decodes as an ordinary, non-resolution operation,
  /// never an error.
  factory PendingOperation.fromJson(Map<String, dynamic> j) => PendingOperation(
        operationId: j['operationId'] as String,
        idempotencyKey: j['idempotencyKey'] as String,
        kind: j['kind'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
        entityType: j['entityType'] as String?,
        entityId: j['entityId'] as String?,
        state: SyncState.fromWire(j['state'] as String?),
        attemptCount: (j['attemptCount'] as num?)?.toInt() ?? 0,
        lastAttemptAt: j['lastAttemptAt'] == null
            ? null
            : DateTime.parse(j['lastAttemptAt'] as String).toLocal(),
        lastProblemCode: j['lastProblemCode'] as String?,
        resolvesOperationId: j['resolvesOperationId'] as String?,
        currentVersion: j['currentVersion'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingOperation &&
          other.operationId == operationId &&
          other.idempotencyKey == idempotencyKey &&
          other.kind == kind &&
          other.createdAt == createdAt &&
          other.entityType == entityType &&
          other.entityId == entityId &&
          other.state == state &&
          other.attemptCount == attemptCount &&
          other.lastAttemptAt == lastAttemptAt &&
          other.lastProblemCode == lastProblemCode &&
          other.resolvesOperationId == resolvesOperationId &&
          other.currentVersion == currentVersion;

  @override
  int get hashCode => Object.hash(
        operationId,
        idempotencyKey,
        kind,
        createdAt,
        entityType,
        entityId,
        state,
        attemptCount,
        lastAttemptAt,
        lastProblemCode,
        resolvesOperationId,
        currentVersion,
      );

  @override
  String toString() =>
      'PendingOperation($kind, ${state.wire}, attempts: $attemptCount)';
}
