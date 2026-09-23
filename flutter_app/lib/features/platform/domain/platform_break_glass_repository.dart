import 'package:flutter/foundation.dart';

import '../../../core/result/result.dart';
import 'platform_break_glass_models.dart';

enum BreakGlassProblemCode {
  tenantNotFound('tenant_not_found'),

  /// The target is suspended or deletion pending (Point 9 FULL BLOCK).
  tenantNotEligible('tenant_not_eligible'),
  tenantAlreadyDeleted('tenant_already_deleted'),
  invalidReason('invalid_break_glass_reason'),
  invalidScope('invalid_break_glass_scope'),

  /// This session already holds a possibly-live grant. End it first.
  grantAlreadyActive('break_glass_already_active'),
  grantNotFound('break_glass_not_found'),

  /// The grant has already expired or ended.
  grantNotActive('break_glass_not_active'),
  staleTenant('stale_tenant'),
  staleGrant('stale_break_glass'),
  idempotencyConflict('idempotency_conflict'),

  /// The backend needs a fresh strong authentication before it issues a
  /// grant. Feature-owned for now; a candidate for Core if other privileged
  /// Platform commands adopt it.
  recentAuthenticationRequired('recent_authentication_required'),
  notPermitted('not_permitted');

  const BreakGlassProblemCode(this.wire);

  final String wire;

  static BreakGlassProblemCode? parse(String? wire) {
    for (final code in values) {
      if (code.wire == wire) return code;
    }
    return null;
  }
}

/// Requests a new grant. The backend chooses the grant id, `issuedAt` and
/// `expiresAt`; the client proposes nothing about duration.
@immutable
class ActivateBreakGlassCommand {
  const ActivateBreakGlassCommand({
    required this.tenantId,
    required this.expectedTenantVersion,
    required this.scopes,
    required this.reason,
    required this.idempotencyKey,
  });

  final String tenantId;

  /// The tenant lifecycle version the operator reviewed. A change since then
  /// (suspended, deletion requested/cancelled) returns `stale_tenant`.
  final int expectedTenantVersion;
  final Set<BreakGlassScope> scopes;
  final String reason;

  /// One key per activation attempt — see [breakGlassActivationIdempotencyKey].
  final String idempotencyKey;
}

@immutable
class EndBreakGlassCommand {
  const EndBreakGlassCommand({
    required this.grantId,
    required this.expectedRevision,
    required this.idempotencyKey,
  });

  final String grantId;
  final int expectedRevision;
  final String idempotencyKey;
}

/// Activation keys must be per attempt, never derived from tenant/version: a
/// second request after the first grant ended would otherwise replay the old
/// (ended) grant. [attemptId] is a fresh UUIDv7 minted when a draft is first
/// submitted and reused only for retries of that unchanged draft.
String breakGlassActivationIdempotencyKey(String attemptId) =>
    'break-glass:activate:$attemptId';

/// Ending is naturally once-only per revision, so the key is deterministic.
String breakGlassEndIdempotencyKey({
  required String grantId,
  required int expectedRevision,
}) =>
    'break-glass:end:$grantId:$expectedRevision';

/// The current grant bound to the calling session: the possibly-live one, or
/// the most recent terminal one so the UI can say how it ended, or none.
@immutable
class BreakGlassSnapshot {
  const BreakGlassSnapshot({required this.grant, required this.readAt});

  final BreakGlassGrant? grant;
  final DateTime readAt;
}

@immutable
class BreakGlassMutationResult {
  const BreakGlassMutationResult({
    required this.grant,
    required this.changed,
    this.idempotentReplay = false,
  });

  final BreakGlassGrant grant;
  final bool changed;
  final bool idempotentReplay;

  BreakGlassMutationResult asIdempotentReplay() => BreakGlassMutationResult(
        grant: grant,
        changed: false,
        idempotentReplay: true,
      );
}

/// Dedicated, backend-neutral seam for break-glass grants.
///
/// Deliberately separate from tenant operational repositories, from
/// `TenantLifecycleRepository`, `PlatformSecurityRepository`,
/// `PlatformAuditRepository` and `AuthRepository`. Every call is online-only
/// and backend-authoritative: activation and ending are never queued, and an
/// offline read never manufactures usable authority.
abstract class PlatformBreakGlassRepository {
  Future<Result<BreakGlassSnapshot>> loadCurrent();

  Future<Result<BreakGlassMutationResult>> activate(
    ActivateBreakGlassCommand command,
  );

  Future<Result<BreakGlassMutationResult>> end(EndBreakGlassCommand command);
}
