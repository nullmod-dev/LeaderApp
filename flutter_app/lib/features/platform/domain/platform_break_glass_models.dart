/// Point 12A — Break-glass (emergency access) domain.
///
/// A break-glass grant is an **exceptional, temporary, single-tenant, read-only
/// authorization attached to one Super Admin session**. It is not a role, not a
/// tenant account, not a tenant `Cap` grant, and not a Platform permission: the
/// signed-in `AuthUser` stays `super_admin` with no `saasTenantId` and no
/// capabilities for the whole life of a grant. The backend issues, enforces,
/// ends and audits grants; this file only models what it returns and the pure
/// rules the client applies to fail closed. See `API_CONTRACT.md` → "Break-glass
/// emergency access (Point 12A)".
library;

import 'package:flutter/foundation.dart';

import '../../../core/access/saas_tenant_status.dart';
import '../../auth/domain/auth_models.dart';
import 'tenant_lifecycle_models.dart';

/// A deterministic mock default only. The backend reads the effective duration
/// from platform policy and returns the authoritative `expiresAt`.
const Duration kProvisionalBreakGlassGrantDuration = Duration(hours: 1);

/// Presentation threshold only: when the remaining time falls to this window
/// the active-context indicator says the grant is about to end. It never
/// extends or shortens a grant.
const Duration kBreakGlassNearExpiryWindow = Duration(minutes: 10);

/// Same administrative-reason convention as Point 9 lifecycle reasons.
const int kBreakGlassReasonMaxLength = kTenantLifecycleReasonMaxLength;

String normalizeBreakGlassReason(String raw) =>
    normalizeTenantLifecycleReason(raw);

bool isValidBreakGlassReason(String normalized) =>
    normalized.isNotEmpty && normalized.length <= kBreakGlassReasonMaxLength;

/// What a grant may be used for. A closed catalogue: the backend never infers
/// a broader scope, and a value this build does not know confers nothing.
enum BreakGlassScope {
  /// Read-only access to the target tenant's operational records, still
  /// bounded by that tenant's Feature Flags. Never Platform commercial
  /// configuration, accounts, credentials, or the Team Code.
  tenantOperationalRead('tenant_operational_read');

  const BreakGlassScope(this.wire);

  final String wire;

  /// No scope in this catalogue authorizes a write, a create, or a delete.
  /// A future write scope would be a new value with its own backend policy.
  bool get permitsWrites => false;

  static BreakGlassScope? tryParse(Object? wire) {
    for (final scope in values) {
      if (scope.wire == wire) return scope;
    }
    return null;
  }
}

enum BreakGlassGrantStatus {
  active('active'),
  expired('expired'),
  ended('ended'),

  /// A state this build does not recognise. Never usable.
  unknown('unknown');

  const BreakGlassGrantStatus(this.wire);

  final String wire;

  static BreakGlassGrantStatus parse(Object? wire) => values.firstWhere(
        (value) => value != unknown && value.wire == wire,
        orElse: () => unknown,
      );
}

/// Why an [BreakGlassGrantStatus.ended] grant ended before its expiry.
enum BreakGlassEndReason {
  /// The initiating Super Admin ended it.
  endedByInitiator('ended_by_initiator'),

  /// The session the grant was bound to signed out, expired, or was revoked.
  sessionEnded('session_ended'),

  /// The target tenant left `active` (suspended, deletion pending, deleted).
  tenantUnavailable('tenant_unavailable'),

  /// Platform authority other than the initiator ended it.
  revokedByPlatform('revoked_by_platform'),
  unknown('unknown');

  const BreakGlassEndReason(this.wire);

  final String wire;

  static BreakGlassEndReason parse(Object? wire) => values.firstWhere(
        (value) => value != unknown && value.wire == wire,
        orElse: () => unknown,
      );
}

/// The minimum tenant identity needed to target and display a grant. No Team
/// Code, Main Admin, subscription, feature, limit, or operational data.
@immutable
class BreakGlassTenantReference {
  BreakGlassTenantReference({
    required this.tenantId,
    required this.displayName,
  }) {
    if (tenantId.trim().isEmpty) throw ArgumentError.value(tenantId);
    if (displayName.trim().isEmpty) throw ArgumentError.value(displayName);
  }

  final String tenantId;
  final String displayName;

  factory BreakGlassTenantReference.fromJson(Map<String, dynamic> json) =>
      BreakGlassTenantReference(
        tenantId: _string(json['tenantId']),
        displayName: _string(json['displayName']),
      );

  Map<String, dynamic> toJson() => {
        'tenantId': tenantId,
        'displayName': displayName,
      };
}

/// Historical snapshot of the Super Admin who requested the grant: id and
/// display name only, never email, session, device, or credential material.
@immutable
class BreakGlassInitiator {
  BreakGlassInitiator({required this.accountId, required this.displayName}) {
    if (accountId.trim().isEmpty) throw ArgumentError.value(accountId);
    if (displayName.trim().isEmpty) throw ArgumentError.value(displayName);
  }

  final String accountId;
  final String displayName;

  factory BreakGlassInitiator.fromJson(Map<String, dynamic> json) =>
      BreakGlassInitiator(
        accountId: _string(json['accountId']),
        displayName: _string(json['displayName']),
      );

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'displayName': displayName,
      };
}

/// One backend-issued grant. Immutable; a change is a new revision.
///
/// Constructor invariants keep impossible combinations unrepresentable: an
/// active or expired grant carries no end metadata, an ended grant always
/// carries both `endedAt` and `endReason`, and `expiresAt` is after
/// `issuedAt`. An [BreakGlassGrantStatus.unknown] grant is readable (so it is
/// never invisible) but never usable.
@immutable
class BreakGlassGrant {
  BreakGlassGrant({
    required this.id,
    required this.revision,
    required this.tenant,
    required Set<BreakGlassScope> scopes,
    required String reason,
    required this.initiator,
    required DateTime issuedAt,
    required DateTime expiresAt,
    required this.status,
    this.hasUnsupportedScope = false,
    DateTime? endedAt,
    this.endReason,
  })  : scopes = Set.unmodifiable(scopes),
        reason = normalizeBreakGlassReason(reason),
        issuedAt = issuedAt.toUtc(),
        expiresAt = expiresAt.toUtc(),
        endedAt = endedAt?.toUtc() {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    if (revision < 1) throw ArgumentError.value(revision, 'revision');
    if (!isValidBreakGlassReason(this.reason)) {
      throw ArgumentError.value(reason, 'reason');
    }
    if (!this.expiresAt.isAfter(this.issuedAt)) {
      throw ArgumentError('expiresAt must be after issuedAt');
    }
    switch (status) {
      case BreakGlassGrantStatus.active:
      case BreakGlassGrantStatus.expired:
        if (this.endedAt != null || endReason != null) {
          throw ArgumentError('${status.wire} grant cannot carry end metadata');
        }
      case BreakGlassGrantStatus.ended:
        if (this.endedAt == null || endReason == null) {
          throw ArgumentError('ended grant requires endedAt and endReason');
        }
        if (this.endedAt!.isBefore(this.issuedAt)) {
          throw ArgumentError('endedAt must not precede issuedAt');
        }
      case BreakGlassGrantStatus.unknown:
        break;
    }
  }

  final String id;

  /// Optimistic-concurrency token for grant commands only.
  final int revision;
  final BreakGlassTenantReference tenant;

  /// Known scopes only. Unrecognised wire scopes are dropped and flagged by
  /// [hasUnsupportedScope]; they never widen what the client treats as allowed.
  final Set<BreakGlassScope> scopes;
  final bool hasUnsupportedScope;

  /// Platform-only administrative justification. Never tenant-facing, never a
  /// credential, never copied into a Platform Audit change body.
  final String reason;
  final BreakGlassInitiator initiator;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final BreakGlassGrantStatus status;
  final DateTime? endedAt;
  final BreakGlassEndReason? endReason;

  /// The status at [now], failing closed: an `active` grant at or after
  /// `expiresAt` is expired even if no fresh read has said so yet.
  BreakGlassGrantStatus effectiveStatusAt(DateTime now) =>
      status == BreakGlassGrantStatus.active && !now.toUtc().isBefore(expiresAt)
          ? BreakGlassGrantStatus.expired
          : status;

  bool isActiveAt(DateTime now) =>
      effectiveStatusAt(now) == BreakGlassGrantStatus.active;

  /// Whether the backend might still treat this grant as live at [now]. Used
  /// only for awareness (never usability): an unknown status before its
  /// expiry is surfaced rather than hidden.
  bool isPossiblyLiveAt(DateTime now) =>
      isActiveAt(now) ||
      (status == BreakGlassGrantStatus.unknown &&
          now.toUtc().isBefore(expiresAt));

  Duration remainingAt(DateTime now) {
    if (!isActiveAt(now)) return Duration.zero;
    return expiresAt.difference(now.toUtc());
  }

  BreakGlassGrant _copy({
    required int revision,
    required BreakGlassGrantStatus status,
    DateTime? endedAt,
    BreakGlassEndReason? endReason,
  }) =>
      BreakGlassGrant(
        id: id,
        revision: revision,
        tenant: tenant,
        scopes: scopes,
        hasUnsupportedScope: hasUnsupportedScope,
        reason: reason,
        initiator: initiator,
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        status: status,
        endedAt: endedAt,
        endReason: endReason,
      );

  /// Parses a backend grant. Malformed identity, timestamps, reason or end
  /// metadata throw [FormatException] (an unreadable grant is a failed read,
  /// not a usable one); unknown status/scope/end-reason values fail closed.
  factory BreakGlassGrant.fromJson(Map<String, dynamic> json) {
    final rawScopes = json['scopes'];
    if (rawScopes is! List) {
      throw FormatException('scopes must be a list', rawScopes);
    }
    final known = <BreakGlassScope>{};
    var unsupported = false;
    for (final raw in rawScopes) {
      final scope = BreakGlassScope.tryParse(raw);
      if (scope == null) {
        unsupported = true;
      } else {
        known.add(scope);
      }
    }
    final tenant = json['tenant'];
    final initiator = json['initiator'];
    final revision = json['revision'];
    if (tenant is! Map<String, dynamic> ||
        initiator is! Map<String, dynamic> ||
        revision is! num) {
      throw const FormatException('malformed break-glass grant');
    }
    try {
      return BreakGlassGrant(
        id: _string(json['id']),
        revision: revision.toInt(),
        tenant: BreakGlassTenantReference.fromJson(tenant),
        scopes: known,
        hasUnsupportedScope: unsupported,
        reason: _string(json['reason']),
        initiator: BreakGlassInitiator.fromJson(initiator),
        issuedAt: _date(json['issuedAt']),
        expiresAt: _date(json['expiresAt']),
        status: BreakGlassGrantStatus.parse(json['status']),
        endedAt: json['endedAt'] == null ? null : _date(json['endedAt']),
        endReason: json['endReason'] == null
            ? null
            : BreakGlassEndReason.parse(json['endReason']),
      );
    } on ArgumentError catch (error) {
      throw FormatException('invalid break-glass grant: ${error.message}');
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'revision': revision,
        'tenant': tenant.toJson(),
        'scopes': [for (final scope in scopes) scope.wire],
        'reason': reason,
        'initiator': initiator.toJson(),
        'issuedAt': issuedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'status': status.wire,
        if (endedAt != null) 'endedAt': endedAt!.toIso8601String(),
        if (endReason != null) 'endReason': endReason!.wire,
      };
}

enum BreakGlassTenantEligibility { eligible, notFound, notEligible, deleted }

enum BreakGlassTransitionProblem {
  tenantNotFound,
  tenantNotEligible,
  tenantDeleted,
  invalidReason,
  invalidScope,
  grantAlreadyActive,
  grantNotActive,
}

sealed class BreakGlassTransitionDecision {
  const BreakGlassTransitionDecision();
}

class BreakGlassTransitionAllowed extends BreakGlassTransitionDecision {
  const BreakGlassTransitionAllowed(this.grant);

  final BreakGlassGrant grant;
}

class BreakGlassTransitionRefused extends BreakGlassTransitionDecision {
  const BreakGlassTransitionRefused(this.problem);

  final BreakGlassTransitionProblem problem;
}

/// The sole pure grant state machine.
///
/// ```text
/// (none) ──activate──▶ active ──end (initiator)──────────▶ ended
///                        │   ──backend invalidation──────▶ ended
///                        └── now ≥ expiresAt ────────────▶ expired
/// ended, expired: terminal. Renewed access is a new grant with a new reason.
/// ```
///
/// In production the backend runs this; the mock repository calls it so the
/// client and its tests exercise the same rules the contract documents.
abstract final class BreakGlassPolicy {
  /// Point 9 precedence: only an `active` tenant may be targeted. Suspension
  /// and deletion pending are FULL BLOCK and break-glass is not a way around
  /// them; a deleted tenant is terminal and is never reconstructed.
  static BreakGlassTenantEligibility tenantEligibility(
    SaasTenantStatus? status,
  ) =>
      switch (status) {
        null => BreakGlassTenantEligibility.notFound,
        SaasTenantStatus.active => BreakGlassTenantEligibility.eligible,
        SaasTenantStatus.suspended ||
        SaasTenantStatus.deletionPending =>
          BreakGlassTenantEligibility.notEligible,
        SaasTenantStatus.deleted => BreakGlassTenantEligibility.deleted,
      };

  static BreakGlassTransitionDecision activate({
    required String grantId,
    required BreakGlassTenantReference? tenant,
    required SaasTenantStatus? tenantStatus,
    required Set<BreakGlassScope> scopes,
    required String reason,
    required BreakGlassInitiator initiator,
    required DateTime now,
    BreakGlassGrant? current,
    Duration duration = kProvisionalBreakGlassGrantDuration,
  }) {
    final normalizedReason = normalizeBreakGlassReason(reason);
    if (!isValidBreakGlassReason(normalizedReason)) {
      return const BreakGlassTransitionRefused(
        BreakGlassTransitionProblem.invalidReason,
      );
    }
    if (scopes.isEmpty) {
      return const BreakGlassTransitionRefused(
        BreakGlassTransitionProblem.invalidScope,
      );
    }
    switch (tenantEligibility(tenantStatus)) {
      case BreakGlassTenantEligibility.notFound:
        return const BreakGlassTransitionRefused(
          BreakGlassTransitionProblem.tenantNotFound,
        );
      case BreakGlassTenantEligibility.notEligible:
        return const BreakGlassTransitionRefused(
          BreakGlassTransitionProblem.tenantNotEligible,
        );
      case BreakGlassTenantEligibility.deleted:
        return const BreakGlassTransitionRefused(
          BreakGlassTransitionProblem.tenantDeleted,
        );
      case BreakGlassTenantEligibility.eligible:
        break;
    }
    if (tenant == null) {
      return const BreakGlassTransitionRefused(
        BreakGlassTransitionProblem.tenantNotFound,
      );
    }
    if (current != null && current.isPossiblyLiveAt(now)) {
      return const BreakGlassTransitionRefused(
        BreakGlassTransitionProblem.grantAlreadyActive,
      );
    }
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration');
    }
    final at = now.toUtc();
    return BreakGlassTransitionAllowed(BreakGlassGrant(
      id: grantId,
      revision: 1,
      tenant: tenant,
      scopes: scopes,
      reason: normalizedReason,
      initiator: initiator,
      issuedAt: at,
      expiresAt: at.add(duration),
      status: BreakGlassGrantStatus.active,
    ));
  }

  /// The initiator ends their own grant early.
  static BreakGlassTransitionDecision end({
    required BreakGlassGrant grant,
    required DateTime now,
  }) =>
      terminate(
        grant: grant,
        reason: BreakGlassEndReason.endedByInitiator,
        now: now,
      );

  /// Ends an effectively active grant for [reason]. Backend-side invalidation
  /// (session end, tenant leaving `active`, platform revocation) uses this.
  static BreakGlassTransitionDecision terminate({
    required BreakGlassGrant grant,
    required BreakGlassEndReason reason,
    required DateTime now,
  }) {
    if (reason == BreakGlassEndReason.unknown) {
      throw ArgumentError.value(reason, 'reason');
    }
    if (!grant.isActiveAt(now)) {
      return const BreakGlassTransitionRefused(
        BreakGlassTransitionProblem.grantNotActive,
      );
    }
    return BreakGlassTransitionAllowed(grant._copy(
      revision: grant.revision + 1,
      status: BreakGlassGrantStatus.ended,
      endedAt: now.toUtc(),
      endReason: reason,
    ));
  }

  /// Records time-based expiry: an `active` grant at or after `expiresAt`
  /// becomes `expired` with a new revision. Anything else is returned as is.
  static BreakGlassGrant settle(BreakGlassGrant grant, DateTime now) =>
      grant.status == BreakGlassGrantStatus.active &&
              grant.effectiveStatusAt(now) == BreakGlassGrantStatus.expired
          ? grant._copy(
              revision: grant.revision + 1,
              status: BreakGlassGrantStatus.expired,
            )
          : grant;
}

/// What the client may do with the current grant, derived purely.
enum BreakGlassAccessState {
  /// No grant, or no Super Admin session to attach one to.
  none,

  /// Confirmed by a fresh authoritative read, active, target tenant active.
  usable,

  /// Possibly active but not confirmed (offline or stale read). Shown, never
  /// usable.
  unverified,
  expired,
  ended,

  /// Active on paper but the target tenant is no longer `active`.
  tenantUnavailable,

  /// Unknown status or no scope this build recognises. Never usable.
  unsupported,
}

@immutable
class BreakGlassAccessDecision {
  const BreakGlassAccessDecision({
    required this.state,
    this.grant,
    this.isPossiblyLive = false,
    this.isNearExpiry = false,
  });

  static const none = BreakGlassAccessDecision(
    state: BreakGlassAccessState.none,
  );

  final BreakGlassAccessState state;
  final BreakGlassGrant? grant;

  /// Drives the persistent active-context indicator: shown whenever the
  /// backend might still consider the grant live, even when it is unusable.
  final bool isPossiblyLive;
  final bool isNearExpiry;

  bool get isUsable => state == BreakGlassAccessState.usable;

  /// Whether [scope] may be exercised now. Always read-only; nothing in the
  /// catalogue permits a write.
  bool permits(BreakGlassScope scope) =>
      isUsable && grant!.scopes.contains(scope);
}

abstract final class BreakGlassAccessPolicy {
  /// Order is deliberate: session/surface first, then grant state, then
  /// scope, then target tenant lifecycle, then freshness. Any failed step
  /// denies; none of them can be skipped by a later one.
  static BreakGlassAccessDecision evaluate({
    required AuthRole? sessionRole,
    required BreakGlassGrant? grant,
    required bool confirmed,
    required SaasTenantStatus? targetTenantStatus,
    required DateTime now,
    Duration nearExpiryWindow = kBreakGlassNearExpiryWindow,
  }) {
    if (sessionRole != AuthRole.superAdmin || grant == null) {
      return BreakGlassAccessDecision.none;
    }
    final live = grant.isPossiblyLiveAt(now);
    BreakGlassAccessDecision decide(BreakGlassAccessState state) =>
        BreakGlassAccessDecision(
          state: state,
          grant: grant,
          isPossiblyLive: live,
          isNearExpiry: live &&
              grant.isActiveAt(now) &&
              grant.remainingAt(now) <= nearExpiryWindow,
        );
    switch (grant.effectiveStatusAt(now)) {
      case BreakGlassGrantStatus.expired:
        return decide(BreakGlassAccessState.expired);
      case BreakGlassGrantStatus.ended:
        return decide(BreakGlassAccessState.ended);
      case BreakGlassGrantStatus.unknown:
        return decide(BreakGlassAccessState.unsupported);
      case BreakGlassGrantStatus.active:
        break;
    }
    if (grant.scopes.isEmpty) {
      return decide(BreakGlassAccessState.unsupported);
    }
    if (targetTenantStatus != SaasTenantStatus.active) {
      return decide(BreakGlassAccessState.tenantUnavailable);
    }
    if (!confirmed) return decide(BreakGlassAccessState.unverified);
    return decide(BreakGlassAccessState.usable);
  }
}

String _string(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) {
    throw FormatException('expected a non-empty string', raw);
  }
  return raw;
}

DateTime _date(Object? raw) {
  if (raw is! String) throw const FormatException('timestamp must be a string');
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('invalid timestamp', raw);
  return parsed.toUtc();
}
