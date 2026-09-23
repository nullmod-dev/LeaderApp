import 'package:flutter/foundation.dart';

/// The three generic outcomes a conflict screen may request.
///
/// There is deliberately no generic `merge`: a feature may add a domain-owned
/// merge flow only when that domain can define safe merge semantics.
enum ConflictResolutionIntent { useLocal, useCurrent, reviewLater }

/// Text-direction metadata for an already formatted value.
///
/// Times and similar measurements remain easier to compare left-to-right even
/// inside MTM's Arabic UI. Everything else follows the ambient RTL direction.
enum ConflictValueDirection {
  natural('natural'),
  ltr('ltr');

  const ConflictValueDirection(this.wire);

  /// The stable string a durable review entry persists, kept separate from
  /// [name] so reordering this enum can never re-point a stored row (the
  /// same rule `SyncState.wire` follows).
  final String wire;

  /// An unrecognised value resolves to [natural] — the ambient RTL
  /// direction — rather than throwing on a row written by a newer build.
  static ConflictValueDirection fromWire(String? wire) {
    for (final d in values) {
      if (d.wire == wire) return d;
    }
    return ConflictValueDirection.natural;
  }
}

/// One feature-approved field that differs between the two record versions.
///
/// The owning feature supplies the localized [label] and safe, formatted
/// values. There is no raw backend field name and no arbitrary JSON payload,
/// so this shared presentation model cannot accidentally render internal or
/// sensitive fields that a feature did not explicitly approve.
@immutable
class ConflictFieldComparison {
  const ConflictFieldComparison({
    required this.fieldId,
    required this.label,
    required this.localValue,
    required this.currentValue,
    this.valueDirection = ConflictValueDirection.natural,
  });

  /// Stable frontend-owned identity used for widget keys and tests.
  /// This is not displayed and must not be a raw API field path.
  final String fieldId;
  final String label;
  final String localValue;
  final String currentValue;
  final ConflictValueDirection valueDirection;

  /// Round-trips one already-approved, already-formatted difference so a
  /// conflict stays reviewable offline, later (Task 4). Only what the owning
  /// feature chose to display is written — the same rule that governs the
  /// in-memory model, so persisting it cannot widen what is shown.
  Map<String, dynamic> toJson() => {
        'fieldId': fieldId,
        'label': label,
        'localValue': localValue,
        'currentValue': currentValue,
        'valueDirection': valueDirection.wire,
      };

  factory ConflictFieldComparison.fromJson(Map<String, dynamic> j) =>
      ConflictFieldComparison(
        fieldId: j['fieldId'] as String,
        label: j['label'] as String,
        localValue: j['localValue'] as String,
        currentValue: j['currentValue'] as String,
        valueDirection:
            ConflictValueDirection.fromWire(j['valueDirection'] as String?),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConflictFieldComparison &&
          other.fieldId == fieldId &&
          other.label == label &&
          other.localValue == localValue &&
          other.currentValue == currentValue &&
          other.valueDirection == valueDirection;

  @override
  int get hashCode =>
      Object.hash(fieldId, label, localValue, currentValue, valueDirection);
}

/// The smallest safe view model needed to present one stale-write conflict.
///
/// It contains only opaque identities, concurrency references, a user-facing
/// record summary, and the feature-approved differences. Complete records and
/// backend payloads stay in their owning feature/repository.
@immutable
class ConflictPresentation {
  ConflictPresentation({
    required this.conflictId,
    required this.localOperationId,
    required this.entityType,
    required this.entityId,
    required this.recordTitle,
    this.recordSubtitle,
    this.baseVersion,
    this.currentVersion,
    required List<ConflictFieldComparison> differences,
  })  : assert(differences.isNotEmpty),
        differences = List.unmodifiable(differences);

  final String conflictId;

  /// The existing local operation identity. A resolution flow must keep this
  /// identity; it must not mint a replacement merely because a retry follows.
  final String localOperationId;

  /// Opaque routing/grouping metadata. Never shown by the generic screen.
  final String entityType;
  final String entityId;

  /// Feature-owned, localized context safe to display.
  final String recordTitle;
  final String? recordSubtitle;

  /// Concurrency tokens understood by the frontend but not shown as product
  /// copy. Strings allow an integer version or another future opaque token
  /// without coupling this screen to a backend storage strategy.
  final String? baseVersion;
  final String? currentVersion;

  final List<ConflictFieldComparison> differences;
}

/// A typed frontend intent emitted by the screen.
///
/// No network behaviour is implied here. The future integration owns how
/// `useLocal` and `useCurrent` are persisted/applied. [reviewLater] explicitly
/// leaves the conflict unresolved.
@immutable
class ConflictResolutionDecision {
  const ConflictResolutionDecision({
    required this.conflictId,
    required this.localOperationId,
    required this.intent,
    this.currentVersion,
  });

  factory ConflictResolutionDecision.forConflict(
    ConflictPresentation conflict,
    ConflictResolutionIntent intent,
  ) =>
      ConflictResolutionDecision(
        conflictId: conflict.conflictId,
        localOperationId: conflict.localOperationId,
        intent: intent,
        currentVersion: conflict.currentVersion,
      );

  final String conflictId;
  final String localOperationId;
  final ConflictResolutionIntent intent;

  /// Carried so a future keep-local request can be made against the latest
  /// shared version rather than replaying the original stale version.
  final String? currentVersion;

  bool get resolvesConflict => intent != ConflictResolutionIntent.reviewLater;
}

/// Why a resolution could not be applied.
///
/// The screen has to say something true and useful for each of these, and
/// "تعذّر حفظ اختيارك" is only right for the last one. Two of them mean the
/// conflict the user is looking at no longer exists in the form they saw it
/// ([alreadyResolved], [recordChanged]) — those close the screen and send the
/// user back to a refreshed list rather than leaving them to press a button
/// that can never work.
///
/// In every case the local change is preserved. Nothing here discards work.
enum ConflictResolutionFailure {
  /// The conflicted change is no longer waiting on a decision — it was
  /// resolved on this device from another surface, or the sync that carried
  /// it has since gone through.
  alreadyResolved,

  /// The record moved again after this screen was built, so the two versions
  /// on it are not the two versions that would be resolved.
  recordChanged,

  /// The record this change belongs to no longer exists.
  recordDeleted,

  /// The session may no longer make this change.
  notPermitted,

  /// The chosen resolution needed the network and could not reach it.
  offline,

  /// Anything else. The conflict stays exactly as it was.
  couldNotApply,
}

/// A resolution that did not happen, with the reason the UI needs to explain
/// it in plain language.
///
/// Extends [StateError] deliberately: every caller that already treats a
/// failed resolution as "keep the conflict, tell the user" keeps working
/// unchanged, and only the callers that want to say something more precise
/// need to look at [reason].
class ConflictResolutionException extends StateError {
  ConflictResolutionException(this.reason, String message) : super(message);

  final ConflictResolutionFailure reason;

  /// Whether the conflict as presented is gone, so the screen should close
  /// and the list refresh instead of offering the same choice again.
  bool get isStale =>
      reason == ConflictResolutionFailure.alreadyResolved ||
      reason == ConflictResolutionFailure.recordChanged;
}

typedef ConflictDecisionHandler = Future<void> Function(
  ConflictResolutionDecision decision,
);

/// Typed arguments for the root conflict route.
///
/// Manual Sync, a future Needs Review list, or a direct feature flow can all
/// push the same route with this object. Background sync must only persist an
/// attention state; it must never push the route itself.
@immutable
class ConflictResolutionRouteArgs {
  const ConflictResolutionRouteArgs({
    required this.conflict,
    required this.onDecision,
  });

  final ConflictPresentation conflict;
  final ConflictDecisionHandler onDecision;
}
