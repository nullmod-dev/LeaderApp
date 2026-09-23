import 'package:flutter/foundation.dart';

import '../../../core/result/result.dart';
import 'platform_main_admin_models.dart';

/// Feature-owned problem codes for Main Admin account commands. Clients branch
/// on these only, never on message text. Global `validation` / `server` and
/// the offline transport result come from `core/problem`.
enum MainAdminProblemCode {
  tenantNotFound('tenant_not_found'),

  /// The tenant is suspended or deletion pending and the action would open,
  /// restore or extend an access path (Point 9 FULL BLOCK).
  tenantNotEligible('tenant_not_eligible'),
  tenantAlreadyDeleted('tenant_already_deleted'),

  /// The seat's state does not allow this action (e.g. suspend an account
  /// that is not active, resend when nothing is pending).
  invalidTransition('invalid_main_admin_transition'),
  invalidReason('invalid_main_admin_reason'),

  /// The designate's name/email is malformed or equals the current login.
  invalidIdentity('invalid_main_admin_identity'),

  /// The designate's email already belongs to another MTM account. The
  /// backend says only that — never which account or which tenant.
  identityUnavailable('main_admin_identity_unavailable'),
  replacementAlreadyPending('main_admin_replacement_already_pending'),

  /// The backend throttled invitation resends. **PROVISIONAL** name; the
  /// mock never produces it.
  setupResendThrottled('main_admin_setup_resend_throttled'),

  /// `expectedRevision` no longer matches the seat.
  staleMainAdmin('stale_main_admin'),
  idempotencyConflict('idempotency_conflict'),

  /// The backend needs fresh strong authentication. Flutter verifies nothing.
  recentAuthenticationRequired('recent_authentication_required'),
  notPermitted('not_permitted');

  const MainAdminProblemCode(this.wire);

  final String wire;

  static MainAdminProblemCode? parse(String? wire) {
    for (final code in values) {
      if (code.wire == wire) return code;
    }
    return null;
  }
}

/// Every command names the tenant, the seat revision the operator reviewed,
/// and an Idempotency-Key. Typed per command — there is no
/// `updateAccount(Map)`.
@immutable
sealed class MainAdminCommand {
  const MainAdminCommand({
    required this.tenantId,
    required this.expectedRevision,
    required this.idempotencyKey,
  });

  final String tenantId;
  final int expectedRevision;
  final String idempotencyKey;

  MainAdminAction get action;
}

/// Which pending invitation to re-send.
enum MainAdminSetupTarget {
  /// The current `pending_setup` account's.
  current('current'),

  /// The pending replacement designate's.
  replacement('replacement');

  const MainAdminSetupTarget(this.wire);

  final String wire;
}

/// The backend invalidates the previous invitation, issues a new one and
/// returns the new `lastSentAt`/`expiresAt`. No link, code or token returns.
class ResendMainAdminSetupCommand extends MainAdminCommand {
  const ResendMainAdminSetupCommand({
    required super.tenantId,
    required super.expectedRevision,
    required super.idempotencyKey,
    required this.target,
  });

  final MainAdminSetupTarget target;

  @override
  MainAdminAction get action => switch (target) {
        MainAdminSetupTarget.current => MainAdminAction.resendSetup,
        MainAdminSetupTarget.replacement =>
          MainAdminAction.resendReplacementSetup,
      };
}

class SuspendMainAdminCommand extends MainAdminCommand {
  const SuspendMainAdminCommand({
    required super.tenantId,
    required super.expectedRevision,
    required super.idempotencyKey,
    required this.reason,
  });

  final String reason;

  @override
  MainAdminAction get action => MainAdminAction.suspend;
}

class ReactivateMainAdminCommand extends MainAdminCommand {
  const ReactivateMainAdminCommand({
    required super.tenantId,
    required super.expectedRevision,
    required super.idempotencyKey,
  });

  @override
  MainAdminAction get action => MainAdminAction.reactivate;
}

/// The client names who; the backend decides how by the current account's
/// state ([MainAdminReplacementMode]) and assigns every id. A state change
/// since review is caught by `expectedRevision`, so the operator never gets a
/// mode they did not confirm.
class ReplaceMainAdminCommand extends MainAdminCommand {
  const ReplaceMainAdminCommand({
    required super.tenantId,
    required super.expectedRevision,
    required super.idempotencyKey,
    required this.designate,
    required this.reason,
  });

  final MainAdminDesignateIdentity designate;
  final String reason;

  @override
  MainAdminAction get action => MainAdminAction.replace;
}

class CancelMainAdminReplacementCommand extends MainAdminCommand {
  const CancelMainAdminReplacementCommand({
    required super.tenantId,
    required super.expectedRevision,
    required super.idempotencyKey,
    required this.replacementId,
  });

  final String replacementId;

  @override
  MainAdminAction get action => MainAdminAction.cancelReplacement;
}

/// One key per **attempt**: [attemptId] is a fresh UUIDv7 minted when the
/// operator first confirms a draft and reused only to retry that unchanged
/// draft. A changed draft mints a new key. Never replayed automatically.
String mainAdminIdempotencyKey(MainAdminAction action, String attemptId) =>
    'main-admin:${action.wire}:$attemptId';

@immutable
class MainAdminMutationResult {
  const MainAdminMutationResult({
    required this.snapshot,
    required this.effect,
    required this.changed,
    this.idempotentReplay = false,
  });

  /// The seat after the command, from the backend.
  final MainAdminAccountSnapshot snapshot;
  final MainAdminMutationEffect effect;
  final bool changed;
  final bool idempotentReplay;

  MainAdminMutationResult asIdempotentReplay() => MainAdminMutationResult(
        snapshot: snapshot,
        effect: effect,
        changed: false,
        idempotentReplay: true,
      );
}

/// Dedicated, backend-neutral control-plane seam for the Main Admin seat.
///
/// Deliberately separate from `AuthRepository` (the signed-in account's own
/// sessions/MFA/reset), `SaasTenantRepository`, `TenantLifecycleRepository`,
/// `PlatformBreakGlassRepository`, `PlatformAuditRepository` and every tenant
/// operational repository. Every mutation is online-only and never queued;
/// the backend authorizes each call independently of the Flutter role gate
/// and appends the Audit evidence — this client appends none.
abstract class PlatformMainAdminRepository {
  Future<Result<MainAdminAccountSnapshot>> load(String tenantId);

  Future<Result<MainAdminMutationResult>> resendSetup(
    ResendMainAdminSetupCommand command,
  );

  Future<Result<MainAdminMutationResult>> suspend(
    SuspendMainAdminCommand command,
  );

  Future<Result<MainAdminMutationResult>> reactivate(
    ReactivateMainAdminCommand command,
  );

  Future<Result<MainAdminMutationResult>> replace(
    ReplaceMainAdminCommand command,
  );

  Future<Result<MainAdminMutationResult>> cancelReplacement(
    CancelMainAdminReplacementCommand command,
  );
}
