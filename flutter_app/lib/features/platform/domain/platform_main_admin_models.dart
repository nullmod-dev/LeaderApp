/// Point 14A — Main Admin account management, Platform control plane.
///
/// **What this is.** The Super Admin's view of, and a small set of
/// backend-authoritative controls over, the one account that holds a
/// `SaasTenant`'s **Main Admin seat**. It is not signup, onboarding, account
/// linking or first-login password change (all Point 17); it is not general
/// admin management (Simple Admins stay the tenant's own business); it is not
/// the tenant-side Security screen; and it never makes the Super Admin a Main
/// Admin, a tenant member, or an impersonator. See `API_CONTRACT.md` → "Main
/// Admin account management — Point 14A foundation".
///
/// **Four independent dimensions**, never collapsed into one another:
///
///  1. `SaasTenant` lifecycle (`active | suspended | deletion_pending |
///     deleted`) — the customer. Point 9; untouched here.
///  2. Subscription/commercial state — Point 7; untouched here.
///  3. **Main Admin account state** (this file) — the person's account.
///  4. Auth/session state — the backend's sessions for that account. Point 14
///     never manages sessions directly; some account actions make the backend
///     end them (see [MainAdminMutationEffect.endsSessions]).
///
/// **The seat invariant.** Every non-deleted `SaasTenant` has exactly one
/// current Main Admin account (`pending_setup`, `active` or `suspended` —
/// never `revoked`) and at most one pending replacement. Authority moves from
/// the current account to a designate only atomically, on the backend, when
/// the designate completes setup; two usable Main Admins never coexist.
///
/// **Nothing secret lives here, and there is nowhere to put it.** No
/// password, hash, temporary credential, OTP, MFA secret, backup code, reset
/// or setup token, auth/session token, device or IP. The separation group in
/// `platform_main_admin_repository_test.dart` scans these declarations to
/// keep it that way.
library;

import 'package:flutter/foundation.dart';

import '../../../core/access/saas_tenant_status.dart';
import '../../../core/text/search_key.dart';
import '../../auth/domain/auth_models.dart';
import 'saas_tenant_validation.dart';
import 'tenant_lifecycle_models.dart';

/// Mock default only. The backend owns invitation validity and returns the
/// authoritative `expiresAt` (or none, if its policy has no expiry).
/// **PROVISIONAL — BACKEND/PRODUCT DECISION REQUIRED.**
const Duration kProvisionalMainAdminSetupValidity = Duration(days: 7);

/// Same administrative-reason convention as Point 9 lifecycle reasons and the
/// Point 12 break-glass reason: whitespace-normalized, non-empty, ≤ 280,
/// Platform-only, never tenant-facing, never copied into an Audit change body.
const int kMainAdminReasonMaxLength = kTenantLifecycleReasonMaxLength;

String normalizeMainAdminReason(String raw) =>
    normalizeTenantLifecycleReason(raw);

bool isValidMainAdminReason(String normalized) =>
    normalized.isNotEmpty && normalized.length <= kMainAdminReasonMaxLength;

/// Login email in the one comparison form the platform stores: trimmed,
/// whitespace-collapsed, lower-cased. The same rule `SaasTenantDraft` applies.
String normalizeMainAdminEmail(String raw) =>
    collapseWhitespace(raw).toLowerCase();

String normalizeMainAdminName(String raw) => collapseWhitespace(raw);

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

/// The Main Admin **account's** own lifecycle, as the Platform sees it.
///
/// Wire values are the session envelope's `AccountStatus` values on purpose:
/// it is the same account, seen from the control plane instead of from its own
/// session. A tenant suspension is **not** one of these — it is dimension 1.
enum MainAdminAccountStatus {
  /// Identified by the Super Admin; has not completed first-time setup
  /// (Point 17). Holds the seat but has never had usable authority.
  pendingSetup('pending_setup'),

  /// Completed setup; signs in normally, subject to tenant lifecycle.
  active('active'),

  /// Temporarily blocked by the Platform. Reversible. Holds the seat.
  suspended('suspended'),

  /// The account's Main Admin authorization was permanently withdrawn — the
  /// state an outgoing account ends in when a replacement takes the seat.
  /// **Never** the state of a seat holder: a snapshot whose current account
  /// is `revoked` is refused as malformed.
  revoked('revoked'),

  /// A value this build does not recognise. Readable, never actionable.
  unknown('unknown');

  const MainAdminAccountStatus(this.wire);

  final String wire;

  static MainAdminAccountStatus parse(Object? wire) => values.firstWhere(
        (value) => value != unknown && value.wire == wire,
        orElse: () => unknown,
      );

  /// Whether this state may hold the seat.
  bool get holdsSeat => switch (this) {
        pendingSetup || active || suspended => true,
        revoked || unknown => false,
      };
}

/// Where an outstanding first-time-setup invitation stands. Only the state:
/// the invitation's link, code or token never reaches the Platform client.
enum MainAdminSetupStatus {
  /// Sent and still usable by the invitee.
  outstanding('outstanding'),

  /// Past its backend expiry; a resend issues a fresh one.
  expired('expired'),
  unknown('unknown');

  const MainAdminSetupStatus(this.wire);

  final String wire;

  static MainAdminSetupStatus parse(Object? wire) => values.firstWhere(
        (value) => value != unknown && value.wire == wire,
        orElse: () => unknown,
      );
}

enum MainAdminReplacementStatus {
  /// Designated and invited; the designate has not completed setup. The
  /// current account keeps the seat until they do.
  pending('pending'),
  unknown('unknown');

  const MainAdminReplacementStatus(this.wire);

  final String wire;

  static MainAdminReplacementStatus parse(Object? wire) => values.firstWhere(
        (value) => value != unknown && value.wire == wire,
        orElse: () => unknown,
      );
}

// ---------------------------------------------------------------------------
// Value objects
// ---------------------------------------------------------------------------

/// Setup-invitation facts for a `pending_setup` account or a designate.
@immutable
class MainAdminSetupState {
  MainAdminSetupState({
    required this.status,
    required DateTime lastSentAt,
    DateTime? expiresAt,
  })  : lastSentAt = lastSentAt.toUtc(),
        expiresAt = expiresAt?.toUtc() {
    if (this.expiresAt != null && !this.expiresAt!.isAfter(this.lastSentAt)) {
      throw ArgumentError('expiresAt must be after lastSentAt');
    }
  }

  final MainAdminSetupStatus status;
  final DateTime lastSentAt;

  /// Absent when backend policy has no invitation expiry.
  final DateTime? expiresAt;

  /// Fails toward "expired": an `outstanding` invitation at or after its
  /// `expiresAt` is treated as expired even before a fresh read says so.
  /// That only ever offers a resend; it never grants anything.
  MainAdminSetupStatus effectiveStatusAt(DateTime now) =>
      status == MainAdminSetupStatus.outstanding &&
              expiresAt != null &&
              !now.toUtc().isBefore(expiresAt!)
          ? MainAdminSetupStatus.expired
          : status;

  factory MainAdminSetupState.fromJson(Map<String, dynamic> json) =>
      MainAdminSetupState(
        status: MainAdminSetupStatus.parse(json['status']),
        lastSentAt: _date(json['lastSentAt']),
        expiresAt: json['expiresAt'] == null ? null : _date(json['expiresAt']),
      );

  Map<String, dynamic> toJson() => {
        'status': status.wire,
        'lastSentAt': lastSentAt.toIso8601String(),
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      };
}

/// Why and when the Platform suspended the account. The reason is
/// Platform-only: it is never delivered to the Main Admin, never placed in the
/// session envelope, and never copied into an Audit change body.
@immutable
class MainAdminSuspension {
  MainAdminSuspension({required DateTime suspendedAt, required String reason})
      : suspendedAt = suspendedAt.toUtc(),
        reason = normalizeMainAdminReason(reason) {
    if (!isValidMainAdminReason(this.reason)) {
      throw ArgumentError.value(reason, 'reason');
    }
  }

  final DateTime suspendedAt;
  final String reason;

  factory MainAdminSuspension.fromJson(Map<String, dynamic> json) =>
      MainAdminSuspension(
        suspendedAt: _date(json['suspendedAt']),
        reason: _string(json['reason']),
      );

  Map<String, dynamic> toJson() => {
        'suspendedAt': suspendedAt.toIso8601String(),
        'reason': reason,
      };
}

/// The account currently holding the seat.
///
/// Constructor invariants keep impossible combinations unrepresentable:
///
/// | status | `setup` | `activatedAt` | `suspension` |
/// | --- | --- | --- | --- |
/// | `pending_setup` | required | absent | absent |
/// | `active` | absent | required | absent |
/// | `suspended` | absent | required | required |
/// | `revoked` / `unknown` | not checked | not checked | not checked |
@immutable
class MainAdminAccount {
  MainAdminAccount({
    required this.accountId,
    required String displayName,
    required String loginEmail,
    required this.status,
    required DateTime createdAt,
    DateTime? activatedAt,
    this.setup,
    this.suspension,
  })  : displayName = normalizeMainAdminName(displayName),
        loginEmail = normalizeMainAdminEmail(loginEmail),
        createdAt = createdAt.toUtc(),
        activatedAt = activatedAt?.toUtc() {
    if (accountId.trim().isEmpty) throw ArgumentError.value(accountId);
    if (this.displayName.isEmpty) throw ArgumentError.value(displayName);
    if (validateMainAdminEmail(this.loginEmail) != null) {
      throw ArgumentError.value(loginEmail, 'loginEmail');
    }
    switch (status) {
      case MainAdminAccountStatus.pendingSetup:
        if (setup == null || this.activatedAt != null || suspension != null) {
          throw ArgumentError('pending_setup requires setup and nothing else');
        }
      case MainAdminAccountStatus.active:
        if (this.activatedAt == null || setup != null || suspension != null) {
          throw ArgumentError('active requires activatedAt only');
        }
      case MainAdminAccountStatus.suspended:
        if (this.activatedAt == null || suspension == null || setup != null) {
          throw ArgumentError('suspended requires activatedAt and suspension');
        }
      case MainAdminAccountStatus.revoked:
      case MainAdminAccountStatus.unknown:
        break;
    }
  }

  /// Opaque account id. Used as the Audit target id; never a credential.
  final String accountId;
  final String displayName;

  /// The login identity. **Immutable for this account** — there is no edit
  /// command; a different address is a different account, reached only by
  /// replacement. Rendered LTR.
  final String loginEmail;
  final MainAdminAccountStatus status;
  final DateTime createdAt;

  /// When first-time setup completed. Absent while `pending_setup`.
  final DateTime? activatedAt;
  final MainAdminSetupState? setup;
  final MainAdminSuspension? suspension;

  MainAdminAccount _withStatus(
    MainAdminAccountStatus status, {
    DateTime? activatedAt,
    MainAdminSetupState? setup,
    MainAdminSuspension? suspension,
  }) =>
      MainAdminAccount(
        accountId: accountId,
        displayName: displayName,
        loginEmail: loginEmail,
        status: status,
        createdAt: createdAt,
        activatedAt: activatedAt,
        setup: setup,
        suspension: suspension,
      );

  factory MainAdminAccount.fromJson(Map<String, dynamic> json) {
    final setup = json['setup'];
    final suspension = json['suspension'];
    if ((setup != null && setup is! Map<String, dynamic>) ||
        (suspension != null && suspension is! Map<String, dynamic>)) {
      throw const FormatException('malformed main admin account');
    }
    return MainAdminAccount(
      accountId: _string(json['accountId']),
      displayName: _string(json['displayName']),
      loginEmail: _string(json['loginEmail']),
      status: MainAdminAccountStatus.parse(json['status']),
      createdAt: _date(json['createdAt']),
      activatedAt:
          json['activatedAt'] == null ? null : _date(json['activatedAt']),
      setup: setup == null
          ? null
          : MainAdminSetupState.fromJson(setup as Map<String, dynamic>),
      suspension: suspension == null
          ? null
          : MainAdminSuspension.fromJson(suspension as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'displayName': displayName,
        'loginEmail': loginEmail,
        'status': status.wire,
        'createdAt': createdAt.toIso8601String(),
        if (activatedAt != null) 'activatedAt': activatedAt!.toIso8601String(),
        if (setup != null) 'setup': setup!.toJson(),
        if (suspension != null) 'suspension': suspension!.toJson(),
      };
}

/// The identity designated to take the seat. Always a **new** account in
/// `pending_setup`; it has no tenant authority of any kind until the backend
/// completes the replacement.
@immutable
class MainAdminDesignate {
  MainAdminDesignate({
    required this.accountId,
    required String displayName,
    required String loginEmail,
    required this.setup,
  })  : displayName = normalizeMainAdminName(displayName),
        loginEmail = normalizeMainAdminEmail(loginEmail) {
    if (accountId.trim().isEmpty) throw ArgumentError.value(accountId);
    if (this.displayName.isEmpty) throw ArgumentError.value(displayName);
    if (validateMainAdminEmail(this.loginEmail) != null) {
      throw ArgumentError.value(loginEmail, 'loginEmail');
    }
  }

  final String accountId;
  final String displayName;
  final String loginEmail;
  final MainAdminSetupState setup;

  factory MainAdminDesignate.fromJson(Map<String, dynamic> json) {
    final setup = json['setup'];
    if (setup is! Map<String, dynamic>) {
      throw const FormatException('designate requires setup');
    }
    return MainAdminDesignate(
      accountId: _string(json['accountId']),
      displayName: _string(json['displayName']),
      loginEmail: _string(json['loginEmail']),
      setup: MainAdminSetupState.fromJson(setup),
    );
  }

  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'displayName': displayName,
        'loginEmail': loginEmail,
        'setup': setup.toJson(),
      };
}

/// A replacement in progress. A typed object, never a nullable email string
/// on the account: it has its own id, status, reason and designate.
@immutable
class MainAdminReplacement {
  MainAdminReplacement({
    required this.id,
    required this.status,
    required this.designate,
    required DateTime requestedAt,
    required String reason,
  })  : requestedAt = requestedAt.toUtc(),
        reason = normalizeMainAdminReason(reason) {
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    if (!isValidMainAdminReason(this.reason)) {
      throw ArgumentError.value(reason, 'reason');
    }
  }

  final String id;
  final MainAdminReplacementStatus status;
  final MainAdminDesignate designate;
  final DateTime requestedAt;

  /// Platform-only, as [MainAdminSuspension.reason].
  final String reason;

  MainAdminReplacement _withDesignateSetup(MainAdminSetupState setup) =>
      MainAdminReplacement(
        id: id,
        status: status,
        designate: MainAdminDesignate(
          accountId: designate.accountId,
          displayName: designate.displayName,
          loginEmail: designate.loginEmail,
          setup: setup,
        ),
        requestedAt: requestedAt,
        reason: reason,
      );

  factory MainAdminReplacement.fromJson(Map<String, dynamic> json) {
    final designate = json['designate'];
    if (designate is! Map<String, dynamic>) {
      throw const FormatException('replacement requires a designate');
    }
    return MainAdminReplacement(
      id: _string(json['id']),
      status: MainAdminReplacementStatus.parse(json['status']),
      designate: MainAdminDesignate.fromJson(designate),
      requestedAt: _date(json['requestedAt']),
      reason: _string(json['reason']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status.wire,
        'designate': designate.toJson(),
        'requestedAt': requestedAt.toIso8601String(),
        'reason': reason,
      };
}

/// The minimum tenant context the page needs to decide what it may offer:
/// identity for the header and the lifecycle for the tenant-lifecycle rule.
/// No Team Code, subscription, features, limits, usage or operational data.
@immutable
class MainAdminTenantReference {
  MainAdminTenantReference({
    required this.tenantId,
    required this.displayName,
    required this.lifecycleStatus,
    required this.lifecycleVersion,
  }) {
    if (tenantId.trim().isEmpty) throw ArgumentError.value(tenantId);
    if (displayName.trim().isEmpty) throw ArgumentError.value(displayName);
    if (lifecycleVersion < 1) throw ArgumentError.value(lifecycleVersion);
  }

  final String tenantId;
  final String displayName;
  final SaasTenantStatus lifecycleStatus;
  final int lifecycleVersion;

  MainAdminTenantReference withLifecycle(
          SaasTenantStatus status, int version) =>
      MainAdminTenantReference(
        tenantId: tenantId,
        displayName: displayName,
        lifecycleStatus: status,
        lifecycleVersion: version,
      );

  /// An unknown lifecycle value makes the snapshot unreadable, exactly as it
  /// makes a `SaasTenant` unreadable: guessing a customer's lifecycle is a
  /// verdict about the customer.
  factory MainAdminTenantReference.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['lifecycleStatus'];
    final status =
        rawStatus is String ? SaasTenantStatus.parse(rawStatus) : null;
    final version = json['lifecycleVersion'];
    if (status == null || version is! num) {
      throw FormatException('malformed tenant reference', json);
    }
    return MainAdminTenantReference(
      tenantId: _string(json['tenantId']),
      displayName: _string(json['displayName']),
      lifecycleStatus: status,
      lifecycleVersion: version.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'tenantId': tenantId,
        'displayName': displayName,
        'lifecycleStatus': lifecycleStatus.wire,
        'lifecycleVersion': lifecycleVersion,
      };
}

/// One authoritative read of a tenant's Main Admin seat.
///
/// Refuses (throws) anything that breaks the seat invariant: a `revoked`
/// current account, a deleted tenant, a designate sharing the current login
/// email, a replacement whose designate is not a pending account. Unknown
/// enum values are kept and make the whole snapshot read-only
/// ([hasUnsupportedState]).
@immutable
class MainAdminAccountSnapshot {
  MainAdminAccountSnapshot({
    required this.tenant,
    required this.revision,
    required this.current,
    this.replacement,
    required DateTime readAt,
  }) : readAt = readAt.toUtc() {
    if (revision < 1) throw ArgumentError.value(revision, 'revision');
    if (tenant.lifecycleStatus == SaasTenantStatus.deleted) {
      throw ArgumentError('a deleted tenant has no Main Admin seat');
    }
    if (current.status == MainAdminAccountStatus.revoked) {
      throw ArgumentError('the seat holder can never be revoked');
    }
    final pending = replacement;
    if (pending != null && pending.designate.loginEmail == current.loginEmail) {
      throw ArgumentError('designate must be a different login identity');
    }
    if (pending != null && pending.designate.accountId == current.accountId) {
      throw ArgumentError('designate must be a different account');
    }
  }

  final MainAdminTenantReference tenant;

  /// Optimistic-concurrency token for the whole seat (current account and any
  /// replacement). Every change to either bumps it.
  final int revision;
  final MainAdminAccount current;
  final MainAdminReplacement? replacement;
  final DateTime readAt;

  bool get hasPendingReplacement => replacement != null;

  /// Any value this build does not know, anywhere in the seat. The client
  /// then shows the snapshot but offers **no** action at all.
  bool get hasUnsupportedState =>
      current.status == MainAdminAccountStatus.unknown ||
      current.setup?.status == MainAdminSetupStatus.unknown ||
      replacement?.status == MainAdminReplacementStatus.unknown ||
      replacement?.designate.setup.status == MainAdminSetupStatus.unknown;

  MainAdminAccountSnapshot copyWith({
    MainAdminTenantReference? tenant,
    int? revision,
    MainAdminAccount? current,
    MainAdminReplacement? replacement,
    bool clearReplacement = false,
    DateTime? readAt,
  }) =>
      MainAdminAccountSnapshot(
        tenant: tenant ?? this.tenant,
        revision: revision ?? this.revision,
        current: current ?? this.current,
        replacement: clearReplacement ? null : replacement ?? this.replacement,
        readAt: readAt ?? this.readAt,
      );

  factory MainAdminAccountSnapshot.fromJson(Map<String, dynamic> json) {
    final tenant = json['tenant'];
    final current = json['current'];
    final replacement = json['replacement'];
    final revision = json['revision'];
    if (tenant is! Map<String, dynamic> ||
        current is! Map<String, dynamic> ||
        (replacement != null && replacement is! Map<String, dynamic>) ||
        revision is! num) {
      throw const FormatException('malformed main admin snapshot');
    }
    try {
      return MainAdminAccountSnapshot(
        tenant: MainAdminTenantReference.fromJson(tenant),
        revision: revision.toInt(),
        current: MainAdminAccount.fromJson(current),
        replacement: replacement == null
            ? null
            : MainAdminReplacement.fromJson(
                replacement as Map<String, dynamic>),
        readAt: _date(json['readAt']),
      );
    } on ArgumentError catch (error) {
      throw FormatException('invalid main admin snapshot: ${error.message}');
    }
  }

  Map<String, dynamic> toJson() => {
        'tenant': tenant.toJson(),
        'revision': revision,
        'current': current.toJson(),
        if (replacement != null) 'replacement': replacement!.toJson(),
        'readAt': readAt.toIso8601String(),
      };
}

// ---------------------------------------------------------------------------
// Actions and the pure policy
// ---------------------------------------------------------------------------

/// The closed catalogue of Super Admin commands Point 14 supports. Nothing
/// else — no revoke-only, no password set/reset, no MFA reset, no session
/// list or per-session revoke, no email edit, no impersonation.
enum MainAdminAction {
  /// Re-send the current `pending_setup` account's invitation.
  resendSetup('resend_setup'),
  suspend('suspend'),
  reactivate('reactivate'),

  /// Designate a new identity for the seat — see [MainAdminReplacementMode].
  replace('replace'),

  /// Re-send the pending designate's invitation.
  resendReplacementSetup('resend_replacement_setup'),
  cancelReplacement('cancel_replacement');

  const MainAdminAction(this.wire);

  final String wire;

  /// Whether the action can open, restore or extend a path into tenant
  /// access. Such actions require the tenant to be `active`: Point 9's FULL
  /// BLOCK is never worked around from here. Reducing actions (suspend,
  /// cancel a replacement) stay available on any non-deleted tenant.
  bool get opensAccessPath => switch (this) {
        resendSetup || reactivate || replace || resendReplacementSetup => true,
        suspend || cancelReplacement => false,
      };

  /// Whether the backend must be handed a Platform-only reason.
  bool get requiresReason => this == suspend || this == replace;
}

/// How a `replace` takes effect, decided by the current account's state.
enum MainAdminReplacementMode {
  /// The current account never completed setup, so it holds no authority to
  /// transfer. Its outstanding invitation is invalidated **immediately** and
  /// the designate becomes the current `pending_setup` account. Fixes a wrong
  /// or obsolete address without leaving a claimable invitation live.
  immediate,

  /// The current account (active or suspended) keeps the seat until the
  /// designate completes setup; the backend then transfers it atomically.
  onDesignateSetupCompletion,
}

/// What a successful transition did. Backend-authored events (setup and
/// replacement completion) are included so one vocabulary covers the seat.
enum MainAdminMutationEffect {
  setupResent,
  suspended,
  reactivated,
  replacementStarted,

  /// The seat moved to a new account; the former account is `revoked`.
  replaced,
  replacementCancelled,

  /// Point 17 completed the current account's first-time setup.
  setupCompleted;

  /// Whether the backend must end every session of the affected account
  /// (the suspended account; the outgoing account on [replaced]; the
  /// discarded designate on [replacementCancelled]).
  bool get endsSessions => switch (this) {
        suspended || replaced || replacementCancelled => true,
        setupResent ||
        reactivated ||
        replacementStarted ||
        setupCompleted =>
          false,
      };
}

enum MainAdminTransitionProblem {
  /// The tenant lifecycle does not allow this action (FULL BLOCK rule).
  tenantNotEligible,
  tenantDeleted,

  /// The seat's state does not allow this action.
  invalidTransition,
  invalidReason,

  /// The designate's name/email is malformed or equals the current identity.
  invalidIdentity,
  replacementAlreadyPending,

  /// Something in the seat is a value this build does not know.
  unsupportedState,
}

sealed class MainAdminTransitionDecision {
  const MainAdminTransitionDecision();
}

class MainAdminTransitionAllowed extends MainAdminTransitionDecision {
  const MainAdminTransitionAllowed(
    this.snapshot,
    this.effect, {
    this.revokedAccountId,
  });

  final MainAdminAccountSnapshot snapshot;
  final MainAdminMutationEffect effect;

  /// The former seat holder, on [MainAdminMutationEffect.replaced] only.
  final String? revokedAccountId;
}

class MainAdminTransitionRefused extends MainAdminTransitionDecision {
  const MainAdminTransitionRefused(this.problem);

  final MainAdminTransitionProblem problem;
}

/// The typed designate a replacement names. Normalized by the policy.
@immutable
class MainAdminDesignateIdentity {
  const MainAdminDesignateIdentity({
    required this.displayName,
    required this.loginEmail,
  });

  final String displayName;
  final String loginEmail;

  MainAdminDesignateIdentity get normalized => MainAdminDesignateIdentity(
        displayName: normalizeMainAdminName(displayName),
        loginEmail: normalizeMainAdminEmail(loginEmail),
      );

  /// Shape only; uniqueness across the platform is the backend's.
  bool get isWellFormed =>
      validateMainAdminName(displayName) == null &&
      validateMainAdminEmail(loginEmail) == null;
}

/// The sole pure Main Admin seat state machine.
///
/// ```text
/// current:  pending_setup ──setup completed (Point 17)──▶ active
///           active ──suspend──▶ suspended ──reactivate──▶ active
///
/// replace:  current pending_setup ──replace──▶ designate is current
///             (pending_setup, fresh invitation); old account revoked
///           current active|suspended ──replace──▶ replacement pending
///             ├─ designate completes setup (backend) ─▶ designate is
///             │    current (active); old account revoked, sessions ended
///             └─ cancel ─▶ no replacement; designate discarded
/// ```
///
/// There is no stand-alone revoke: it would empty the seat. The backend runs
/// this; the mock calls it so the client and its tests hold the same rules
/// the contract documents.
abstract final class MainAdminPolicy {
  /// Tenant-lifecycle gate. Deleted: nothing, ever. Active: everything the
  /// seat allows. Suspended / deletion pending: reducing actions only.
  static MainAdminTransitionProblem? tenantGate(
    MainAdminAction action,
    SaasTenantStatus status,
  ) =>
      switch (status) {
        SaasTenantStatus.deleted => MainAdminTransitionProblem.tenantDeleted,
        SaasTenantStatus.active => null,
        SaasTenantStatus.suspended ||
        SaasTenantStatus.deletionPending =>
          action.opensAccessPath
              ? MainAdminTransitionProblem.tenantNotEligible
              : null,
      };

  /// Why [action] is refused for [snapshot] at [now], or `null` when it is
  /// allowed. Reason/identity validity is checked by the transition itself.
  static MainAdminTransitionProblem? check(
    MainAdminAction action,
    MainAdminAccountSnapshot snapshot,
    DateTime now,
  ) {
    if (snapshot.hasUnsupportedState) {
      return MainAdminTransitionProblem.unsupportedState;
    }
    final gate = tenantGate(action, snapshot.tenant.lifecycleStatus);
    if (gate != null) return gate;
    final current = snapshot.current;
    final replacement = snapshot.replacement;
    final allowed = switch (action) {
      MainAdminAction.resendSetup =>
        current.status == MainAdminAccountStatus.pendingSetup,
      MainAdminAction.suspend =>
        current.status == MainAdminAccountStatus.active,
      MainAdminAction.reactivate =>
        current.status == MainAdminAccountStatus.suspended,
      MainAdminAction.replace => current.status.holdsSeat,
      MainAdminAction.resendReplacementSetup ||
      MainAdminAction.cancelReplacement =>
        replacement?.status == MainAdminReplacementStatus.pending,
    };
    if (action == MainAdminAction.replace && replacement != null) {
      return MainAdminTransitionProblem.replacementAlreadyPending;
    }
    return allowed ? null : MainAdminTransitionProblem.invalidTransition;
  }

  static Set<MainAdminAction> availableActions(
    MainAdminAccountSnapshot snapshot,
    DateTime now,
  ) =>
      {
        for (final action in MainAdminAction.values)
          if (check(action, snapshot, now) == null) action,
      };

  static MainAdminReplacementMode replacementMode(MainAdminAccount current) =>
      current.status == MainAdminAccountStatus.pendingSetup
          ? MainAdminReplacementMode.immediate
          : MainAdminReplacementMode.onDesignateSetupCompletion;

  static MainAdminTransitionDecision resendSetup({
    required MainAdminAccountSnapshot snapshot,
    required DateTime now,
    Duration? validity = kProvisionalMainAdminSetupValidity,
  }) {
    final refused = check(MainAdminAction.resendSetup, snapshot, now);
    if (refused != null) return MainAdminTransitionRefused(refused);
    return MainAdminTransitionAllowed(
      snapshot.copyWith(
        revision: snapshot.revision + 1,
        current: snapshot.current._withStatus(
          MainAdminAccountStatus.pendingSetup,
          setup: _freshSetup(now, validity),
        ),
      ),
      MainAdminMutationEffect.setupResent,
    );
  }

  static MainAdminTransitionDecision resendReplacementSetup({
    required MainAdminAccountSnapshot snapshot,
    required DateTime now,
    Duration? validity = kProvisionalMainAdminSetupValidity,
  }) {
    final refused =
        check(MainAdminAction.resendReplacementSetup, snapshot, now);
    if (refused != null) return MainAdminTransitionRefused(refused);
    return MainAdminTransitionAllowed(
      snapshot.copyWith(
        revision: snapshot.revision + 1,
        replacement: snapshot.replacement!
            ._withDesignateSetup(_freshSetup(now, validity)),
      ),
      MainAdminMutationEffect.setupResent,
    );
  }

  static MainAdminTransitionDecision suspend({
    required MainAdminAccountSnapshot snapshot,
    required String reason,
    required DateTime now,
  }) {
    final normalized = normalizeMainAdminReason(reason);
    if (!isValidMainAdminReason(normalized)) {
      return const MainAdminTransitionRefused(
        MainAdminTransitionProblem.invalidReason,
      );
    }
    final refused = check(MainAdminAction.suspend, snapshot, now);
    if (refused != null) return MainAdminTransitionRefused(refused);
    final current = snapshot.current;
    return MainAdminTransitionAllowed(
      snapshot.copyWith(
        revision: snapshot.revision + 1,
        current: current._withStatus(
          MainAdminAccountStatus.suspended,
          activatedAt: current.activatedAt,
          suspension: MainAdminSuspension(suspendedAt: now, reason: normalized),
        ),
      ),
      MainAdminMutationEffect.suspended,
    );
  }

  static MainAdminTransitionDecision reactivate({
    required MainAdminAccountSnapshot snapshot,
    required DateTime now,
  }) {
    final refused = check(MainAdminAction.reactivate, snapshot, now);
    if (refused != null) return MainAdminTransitionRefused(refused);
    final current = snapshot.current;
    return MainAdminTransitionAllowed(
      snapshot.copyWith(
        revision: snapshot.revision + 1,
        current: current._withStatus(
          MainAdminAccountStatus.active,
          activatedAt: current.activatedAt,
        ),
      ),
      MainAdminMutationEffect.reactivated,
    );
  }

  /// [designateAccountId] and [replacementId] are backend-assigned; the
  /// client never constructs either.
  static MainAdminTransitionDecision replace({
    required MainAdminAccountSnapshot snapshot,
    required MainAdminDesignateIdentity designate,
    required String reason,
    required String designateAccountId,
    required String replacementId,
    required DateTime now,
    Duration? validity = kProvisionalMainAdminSetupValidity,
  }) {
    final normalized = normalizeMainAdminReason(reason);
    if (!isValidMainAdminReason(normalized)) {
      return const MainAdminTransitionRefused(
        MainAdminTransitionProblem.invalidReason,
      );
    }
    final identity = designate.normalized;
    if (!identity.isWellFormed ||
        identity.loginEmail == snapshot.current.loginEmail) {
      return const MainAdminTransitionRefused(
        MainAdminTransitionProblem.invalidIdentity,
      );
    }
    final refused = check(MainAdminAction.replace, snapshot, now);
    if (refused != null) return MainAdminTransitionRefused(refused);

    final setup = _freshSetup(now, validity);
    switch (replacementMode(snapshot.current)) {
      case MainAdminReplacementMode.immediate:
        return MainAdminTransitionAllowed(
          snapshot.copyWith(
            revision: snapshot.revision + 1,
            current: MainAdminAccount(
              accountId: designateAccountId,
              displayName: identity.displayName,
              loginEmail: identity.loginEmail,
              status: MainAdminAccountStatus.pendingSetup,
              createdAt: now,
              setup: setup,
            ),
          ),
          MainAdminMutationEffect.replaced,
          revokedAccountId: snapshot.current.accountId,
        );
      case MainAdminReplacementMode.onDesignateSetupCompletion:
        return MainAdminTransitionAllowed(
          snapshot.copyWith(
            revision: snapshot.revision + 1,
            replacement: MainAdminReplacement(
              id: replacementId,
              status: MainAdminReplacementStatus.pending,
              designate: MainAdminDesignate(
                accountId: designateAccountId,
                displayName: identity.displayName,
                loginEmail: identity.loginEmail,
                setup: setup,
              ),
              requestedAt: now,
              reason: normalized,
            ),
          ),
          MainAdminMutationEffect.replacementStarted,
        );
    }
  }

  static MainAdminTransitionDecision cancelReplacement({
    required MainAdminAccountSnapshot snapshot,
    required DateTime now,
  }) {
    final refused = check(MainAdminAction.cancelReplacement, snapshot, now);
    if (refused != null) return MainAdminTransitionRefused(refused);
    return MainAdminTransitionAllowed(
      snapshot.copyWith(
        revision: snapshot.revision + 1,
        clearReplacement: true,
      ),
      MainAdminMutationEffect.replacementCancelled,
    );
  }

  /// **Backend-owned event, not a Super Admin command.** The designate
  /// finished Point 17 setup: the seat transfers atomically — the designate
  /// becomes the `active` current account and the former holder is revoked
  /// with all sessions ended. Refused unless the tenant is `active` and the
  /// designate's invitation is still effectively outstanding.
  static MainAdminTransitionDecision completeReplacement({
    required MainAdminAccountSnapshot snapshot,
    required DateTime now,
  }) {
    if (snapshot.hasUnsupportedState) {
      return const MainAdminTransitionRefused(
        MainAdminTransitionProblem.unsupportedState,
      );
    }
    if (snapshot.tenant.lifecycleStatus != SaasTenantStatus.active) {
      return const MainAdminTransitionRefused(
        MainAdminTransitionProblem.tenantNotEligible,
      );
    }
    final replacement = snapshot.replacement;
    if (replacement == null ||
        replacement.designate.setup.effectiveStatusAt(now) !=
            MainAdminSetupStatus.outstanding) {
      return const MainAdminTransitionRefused(
        MainAdminTransitionProblem.invalidTransition,
      );
    }
    final designate = replacement.designate;
    return MainAdminTransitionAllowed(
      snapshot.copyWith(
        revision: snapshot.revision + 1,
        current: MainAdminAccount(
          accountId: designate.accountId,
          displayName: designate.displayName,
          loginEmail: designate.loginEmail,
          status: MainAdminAccountStatus.active,
          createdAt: replacement.requestedAt,
          activatedAt: now,
        ),
        clearReplacement: true,
      ),
      MainAdminMutationEffect.replaced,
      revokedAccountId: snapshot.current.accountId,
    );
  }

  /// **Backend-owned event (Point 17).** The current `pending_setup` account
  /// completed first-time setup. Same tenant/invitation preconditions as
  /// [completeReplacement].
  static MainAdminTransitionDecision completeSetup({
    required MainAdminAccountSnapshot snapshot,
    required DateTime now,
  }) {
    if (snapshot.hasUnsupportedState) {
      return const MainAdminTransitionRefused(
        MainAdminTransitionProblem.unsupportedState,
      );
    }
    if (snapshot.tenant.lifecycleStatus != SaasTenantStatus.active) {
      return const MainAdminTransitionRefused(
        MainAdminTransitionProblem.tenantNotEligible,
      );
    }
    final current = snapshot.current;
    if (current.status != MainAdminAccountStatus.pendingSetup ||
        current.setup!.effectiveStatusAt(now) !=
            MainAdminSetupStatus.outstanding) {
      return const MainAdminTransitionRefused(
        MainAdminTransitionProblem.invalidTransition,
      );
    }
    return MainAdminTransitionAllowed(
      snapshot.copyWith(
        revision: snapshot.revision + 1,
        current: current._withStatus(
          MainAdminAccountStatus.active,
          activatedAt: now,
        ),
      ),
      MainAdminMutationEffect.setupCompleted,
    );
  }

  static MainAdminSetupState _freshSetup(DateTime now, Duration? validity) {
    if (validity != null && validity <= Duration.zero) {
      throw ArgumentError.value(validity, 'validity');
    }
    final at = now.toUtc();
    return MainAdminSetupState(
      status: MainAdminSetupStatus.outstanding,
      lastSentAt: at,
      expiresAt: validity == null ? null : at.add(validity),
    );
  }
}

// ---------------------------------------------------------------------------
// What the page may offer — the one derived answer Point 14B reads
// ---------------------------------------------------------------------------

enum MainAdminFreshness {
  /// A fresh authoritative read. The only freshness that offers actions.
  confirmed,

  /// Served from cache after a failed refresh. Read-only.
  stale,

  /// No connection; cached copy. Read-only; mutations are never queued.
  offline,
}

@immutable
class MainAdminManagementView {
  const MainAdminManagementView({
    required this.snapshot,
    required this.freshness,
    required this.actions,
    required this.replacementMode,
  });

  final MainAdminAccountSnapshot snapshot;
  final MainAdminFreshness freshness;

  /// Empty unless the session is `super_admin`, the read is confirmed and
  /// the snapshot holds no unknown value.
  final Set<MainAdminAction> actions;

  /// How a `replace` would take effect now, for the right confirmation copy.
  final MainAdminReplacementMode replacementMode;

  bool can(MainAdminAction action) => actions.contains(action);

  bool get isReadOnly => freshness != MainAdminFreshness.confirmed;

  /// Show "account state unavailable" and no actions.
  bool get isUnsupported => snapshot.hasUnsupportedState;

  /// Access-restoring actions are withheld because the *tenant* is blocked,
  /// not because of the account — the page must say so rather than silently
  /// hide them.
  bool get tenantBlocksAccessPaths =>
      snapshot.tenant.lifecycleStatus != SaasTenantStatus.active;
}

abstract final class MainAdminManagementPolicy {
  /// Order: surface first, then freshness, then unknown values, then the pure
  /// seat/tenant policy. Any failed step removes every action.
  static MainAdminManagementView evaluate({
    required AuthRole? sessionRole,
    required MainAdminAccountSnapshot snapshot,
    required MainAdminFreshness freshness,
    required DateTime now,
  }) {
    final actionable = sessionRole == AuthRole.superAdmin &&
        freshness == MainAdminFreshness.confirmed &&
        !snapshot.hasUnsupportedState;
    return MainAdminManagementView(
      snapshot: snapshot,
      freshness: freshness,
      actions: actionable
          ? MainAdminPolicy.availableActions(snapshot, now)
          : const <MainAdminAction>{},
      replacementMode: MainAdminPolicy.replacementMode(snapshot.current),
    );
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
