import 'package:flutter/foundation.dart';

import 'conflict_models.dart';

/// The durable, **safe** review metadata for one detected stale-write
/// conflict — everything the Needs Review inbox and the Task 1 differences
/// screen need to work later, offline, without a server.
///
/// ## Why this exists
///
/// `PendingOperation` is deliberately payload-free (see
/// `core/sync/pending_operation.dart`): it knows an operation conflicted,
/// but not what the record is called or which fields differ. The moment a
/// `409 stale_write` arrives is the only moment connectivity is guaranteed,
/// so that is when the owning feature must capture what a later review will
/// need (`FRONTEND-BACKEND-INTEGRATION.md` §5.4).
///
/// ## What may be in here — and what may not
///
/// Only values the owning feature already chose to **display**: a localized
/// record title/subtitle and the feature-approved
/// [ConflictFieldComparison]s, all formatted before they got here. This
/// record therefore cannot widen what the conflict screen shows; it is the
/// same approved surface, written down.
///
/// It must never carry a raw server body, a stack trace, an internal
/// identifier distinct from the entity's own public id, or any "who changed
/// this" field invented for the conflict surface (§5.4, "What must never be
/// persisted"). Being persistable, it belongs in the encrypted local store,
/// never in plaintext preferences (`DATA-NEEDS.md` §3.3) — see
/// [ConflictReviewStore].
///
/// ## Identity and lifetime
///
/// [conflictId] **is** the conflicting `PendingOperation.operationId` (§5.4,
/// "Identity" — one fact, not two to keep in sync), which is why
/// [toPresentation] can set `localOperationId` from it. One entry per
/// conflicted operation: a later attempt that conflicts again *supersedes*
/// the stored entry rather than stacking a second "current" state next to
/// it. The entry dies with the operation — resolving through `useLocal` or
/// `useCurrent` removes both; `reviewLater` removes neither, which is the
/// entire point of `reviewLater`.
@immutable
class ConflictReviewEntry {
  ConflictReviewEntry({
    required this.conflictId,
    required this.entityType,
    required this.entityId,
    required this.recordTitle,
    required this.detectedAt,
    this.recordSubtitle,
    this.baseVersion,
    this.currentVersion,
    required List<ConflictFieldComparison> differences,
  })  : assert(differences.isNotEmpty),
        differences = List.unmodifiable(differences);

  /// Builds the durable entry directly from the in-memory [ConflictPresentation]
  /// a feature composer already assembled (e.g.
  /// `presentShiftConflict`) — the two shapes carry exactly the same
  /// feature-approved fields; this only adds [detectedAt] and drops the
  /// screen-only `localOperationId` duplicate of [conflictId] (§5.4:
  /// "one identity, not two").
  factory ConflictReviewEntry.fromPresentation(
    ConflictPresentation presentation, {
    required DateTime detectedAt,
  }) =>
      ConflictReviewEntry(
        conflictId: presentation.conflictId,
        entityType: presentation.entityType,
        entityId: presentation.entityId,
        recordTitle: presentation.recordTitle,
        recordSubtitle: presentation.recordSubtitle,
        detectedAt: detectedAt,
        baseVersion: presentation.baseVersion,
        currentVersion: presentation.currentVersion,
        differences: presentation.differences,
      );

  /// Same value as the conflicting `PendingOperation.operationId`.
  final String conflictId;

  /// Opaque routing/grouping metadata. Never rendered.
  final String entityType;
  final String entityId;

  /// Feature-owned, localized, already-formatted context safe to display.
  final String recordTitle;
  final String? recordSubtitle;

  /// When the conflict was classified. Shown only as a coarse relative time
  /// ("قبل ٥ دقائق"), never as a wire timestamp.
  final DateTime detectedAt;

  /// Opaque concurrency tokens, carried so a later resolution can be made
  /// against the version that was current at detection. Never displayed.
  final String? baseVersion;
  final String? currentVersion;

  final List<ConflictFieldComparison> differences;

  /// Rebuilds the Task 1 view model from stored metadata, so the inbox opens
  /// the *same* differences-first screen a live conflict would.
  ConflictPresentation toPresentation() => ConflictPresentation(
        conflictId: conflictId,
        // §5.4: the outbox path always sets these equal.
        localOperationId: conflictId,
        entityType: entityType,
        entityId: entityId,
        recordTitle: recordTitle,
        recordSubtitle: recordSubtitle,
        baseVersion: baseVersion,
        currentVersion: currentVersion,
        differences: differences,
      );

  Map<String, dynamic> toJson() => {
        'conflictId': conflictId,
        'entityType': entityType,
        'entityId': entityId,
        'recordTitle': recordTitle,
        if (recordSubtitle != null) 'recordSubtitle': recordSubtitle,
        'detectedAt': detectedAt.toUtc().toIso8601String(),
        if (baseVersion != null) 'baseVersion': baseVersion,
        if (currentVersion != null) 'currentVersion': currentVersion,
        'differences': [for (final d in differences) d.toJson()],
      };

  factory ConflictReviewEntry.fromJson(Map<String, dynamic> j) =>
      ConflictReviewEntry(
        conflictId: j['conflictId'] as String,
        entityType: j['entityType'] as String,
        entityId: j['entityId'] as String,
        recordTitle: j['recordTitle'] as String,
        recordSubtitle: j['recordSubtitle'] as String?,
        detectedAt: DateTime.parse(j['detectedAt'] as String).toLocal(),
        baseVersion: j['baseVersion'] as String?,
        currentVersion: j['currentVersion'] as String?,
        differences: [
          for (final d in (j['differences'] as List))
            ConflictFieldComparison.fromJson(
              Map<String, dynamic>.from(d as Map),
            ),
        ],
      );

  @override
  String toString() =>
      'ConflictReviewEntry($entityType, ${differences.length} differences)';
}
