import 'package:flutter/foundation.dart';

import '../../../l10n/strings.dart';
import 'conflict_review_entry.dart';

/// One row of the Needs Review inbox: a conflicted operation joined with the
/// safe review metadata stored for it, if any.
///
/// The join is what keeps the inbox honest in both directions:
///
/// - The **outbox** is the source of truth for *what needs review* — the
///   same `SyncState.conflict` operations `conflictOperationsCountProvider`
///   counts — so the list can never disagree with the count Settings shows.
/// - The **review store** is the source of truth for *what can be shown*.
///   An operation with no stored entry is still listed (it is real, and the
///   user's work is really waiting), but as [isReviewable] `false`: the
///   screen says the details are not available on this device rather than
///   opening a differences screen with nothing to compare.
/// - A stored entry whose operation is gone is simply not joined, so a
///   resolved conflict can never reappear even if its entry outlived it.
///
/// Nothing on this row is an identifier the user may see. [conflictId] is
/// carried for routing only; the rendered surface is [title], [subtitle],
/// [recordLabel] and [detectedAt].
@immutable
class NeedsReviewItem {
  const NeedsReviewItem({
    required this.conflictId,
    required this.recordLabel,
    required this.detectedAt,
    this.entry,
  });

  /// The conflicting operation's id. **Routing only — never rendered.**
  final String conflictId;

  /// Localized fallback name for the kind of record involved, resolved from
  /// the operation's opaque tags. Used when no entry was stored, so a raw
  /// `kind` / `entityType` tag never reaches the screen.
  final String recordLabel;

  /// When the conflict was classified.
  final DateTime detectedAt;

  /// The stored review metadata, or `null` when the owning feature could not
  /// capture any at detection time.
  final ConflictReviewEntry? entry;

  /// Whether tapping this row can open the Task 1 differences screen.
  bool get isReviewable => entry != null;

  String get title => entry?.recordTitle ?? recordLabel;

  String? get subtitle => entry?.recordSubtitle;
}

/// Localized name for the kind of record a conflicted operation touches.
///
/// The outbox stores frontend-owned tags (`entityType: 'shift'`,
/// `kind: 'inventory.movement.add'`). Those are grouping metadata, not
/// product copy — showing one would put a backend-looking name on screen,
/// which the sync surfaces forbid. This maps them to real Arabic copy, with
/// a safe generic answer for anything unmapped, so a new feature's
/// operations degrade to "تغيير غير مزامن" instead of leaking their tag.
String needsReviewRecordLabel({String? entityType, required String kind}) {
  final domain = (entityType == null || entityType.isEmpty)
      ? kind.split('.').first
      : entityType;
  switch (domain) {
    case 'shift':
      return S.needsReviewRecordShift;
    case 'inventory':
    case 'inventory_item':
      return S.needsReviewRecordInventory;
    case 'team':
    case 'team_member':
      return S.needsReviewRecordMember;
    default:
      return S.needsReviewRecordGeneric;
  }
}
