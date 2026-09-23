import 'package:flutter/foundation.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/saas_tenant_status.dart';
import '../../../core/env/build_mode.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/secure_store.dart';
import '../domain/auth_models.dart';
import '../domain/onboarding_models.dart';
import '../domain/onboarding_repository.dart';
import '../domain/session_access.dart';
import 'dev_test_credentials.dart';
import 'secure_auth_state_store.dart';

// ---------------------------------------------------------------------------
// Mock-only constants. **None of these is a policy.** Code length, expiry,
// cooldown, attempt budgets and lockouts are PROVISIONAL — BACKEND DECISION
// REQUIRED; these values exist so the development build and the tests can
// exercise every branch deterministically.
// ---------------------------------------------------------------------------

/// The one code the mock mails. Development data, like a persona address.
const String kMockVerificationCode = '246810';
const Duration kMockCodeValidity = Duration(minutes: 10);
const Duration kMockResendCooldown = Duration(seconds: 60);
const int kMockVerificationAttempts = 5;

/// Refusals an address (sign-in) or an account (Team Code) may collect
/// before the mock throttles it, and for how long.
const int kMockFailureBudget = 5;
const Duration kMockLockout = Duration(minutes: 15);

/// The password every seeded fixture account signs in with.
const String kMockFixturePassword = 'mtm-fixture-pass';

/// A Google assertion the mock accepts: `mock-google:<email>` (the address is
/// verified by "Google") or `mock-google-unverified:<email>`. Anything else is
/// refused as an unverifiable token. The real backend verifies a signed ID
/// token; nothing in the client ever parses one.
const String kMockGoogleVerifiedPrefix = 'mock-google:';
const String kMockGoogleUnverifiedPrefix = 'mock-google-unverified:';

/// Which Point 14 seat event a Main Admin authorization completes.
enum MainAdminAuthorizationKind {
  /// The tenant's first Main Admin, `pending_setup` since registration.
  initialSeat,

  /// The designate of a pending replacement; completion transfers the seat.
  replacementDesignate,
}

/// The backend's Point 14 seat transition, as the mock reaches it when a Main
/// Admin authorization completes setup. `null` means the transition was
/// applied; a code is the refusal to answer the setup request with.
///
/// A function rather than a dependency on the Platform repository, so the
/// onboarding mock never imports the control plane. Tests wire it to
/// `MockPlatformMainAdminRepository.simulateSetupCompleted` /
/// `.simulateReplacementSetupCompleted` to prove the two agree.
typedef MainAdminSeatActivation = OnboardingProblemCode? Function(
  String tenantId,
  MainAdminAuthorizationKind kind,
);

/// The moment a pre-session identity becomes a **full session** — a ready
/// sign-in for an account that already finished setup, or setup completing
/// for the first time.
///
/// A callback, not a dependency on `AuthRepository`: the onboarding mock must
/// not import the auth mock, exactly as it must not import the Platform
/// repository (see [MainAdminSeatActivation]). 17B wires this to
/// `MockAuthRepository.installOnboardedSession` so `currentUser()` answers
/// with the account the journey just produced — the "one secure token vault"
/// `HANDOFF.md` "POINT 17A" §L describes, modelled here as one call instead of
/// a shared store.
typedef OnboardingSessionIssued = Future<void> Function(AuthUser user);

/// Point 18B — the authorization side of the setup transaction.
///
/// Called **inside** a successful `completeSetup`, in the same step that
/// marks the authorization consumed and before the full session is issued,
/// so the issuer's record can never be left `pending` after its invitee
/// finished setup. An idempotent replay returns the recorded result and never
/// calls it again. Synchronous and a callback for the same reason as
/// [OnboardingSessionIssued]: the onboarding mock must not import the Simple
/// Admin store it reports to.
typedef OnboardingAuthorizationConsumed = void Function(
  MockAuthorization authorization, {
  required String accountId,
  required String displayName,
});

@immutable
class MockOnboardingTenant {
  const MockOnboardingTenant({
    required this.id,
    required this.displayName,
    required this.teamCode,
    this.status = SaasTenantStatus.active,
  });

  final String id;
  final String displayName;

  /// Canonical form.
  final String teamCode;
  final SaasTenantStatus status;
}

/// A backend authorization: the only thing that makes an address eligible to
/// link to a tenant, and the only source of the linked role.
@immutable
class MockAuthorization {
  const MockAuthorization({
    required this.id,
    required this.tenantId,
    required this.email,
    required this.role,
    required this.suggestedName,
    this.capabilities = Capabilities.none,
    this.mainAdminKind,
    this.expiresIn,
  });

  final String id;
  final String tenantId;
  final String email;
  final AuthRole role;
  final String suggestedName;
  final Capabilities capabilities;

  /// Set exactly for a Main Admin seat authorization.
  final MainAdminAuthorizationKind? mainAdminKind;

  /// Validity from the repository's first clock reading; negative = already
  /// expired; `null` = the backend's policy has no expiry.
  final Duration? expiresIn;
}

/// A seeded account (or a provisioned, not yet claimed, one).
@immutable
class MockOnboardingAccount {
  const MockOnboardingAccount({
    required this.accountId,
    required this.email,
    this.password,
    this.google = false,
    this.verified = false,
    this.status = AccountStatus.pendingSetup,
    this.linkedAuthorizationId,
    this.setupCompleted = false,
  });

  final String accountId;
  final String email;
  final String? password;
  final bool google;
  final bool verified;
  final AccountStatus status;
  final String? linkedAuthorizationId;
  final bool setupCompleted;
}

/// Deterministic development data. Tenant ids, names, Team Codes and Main
/// Admin addresses match `platform_tenant_fixtures.dart` and
/// `MainAdminFixtures`, so the onboarding side and the Platform side describe
/// the same people. No real person, address or credential.
abstract final class OnboardingFixtures {
  static const nabdTenantId = 'saas_nabd';
  static const najdTenantId = 'saas_najd';
  static const hilalTenantId = 'saas_hilal';
  static const ruknTenantId = 'saas_rukn';

  static const nabdCode = 'MTM-5JQX-2TWD';
  static const najdCode = 'MTM-9WCT-3H5R';
  static const hilalCode = 'MTM-4K7P-QX92';
  static const ruknCode = 'MTM-8SVZ-4CQR';

  /// Well-formed, resolves to nothing.
  static const unknownCode = 'MTM-2222-3333';

  /// Point 14 fixtures: `saas_nabd`'s pending initial Main Admin and
  /// `saas_najd`'s pending replacement designate. Provisioned by the Platform
  /// (account ids as `MainAdminFixtures.accountIdFor`), not yet claimed.
  static const nabdMainAdminEmail = 'huda@nabd-team.org';
  static const nabdMainAdminAccountId = 'ma_nabd';
  static const najdDesignateEmail = 'reem@najd-response.sa';
  static const najdDesignateAccountId = 'ma_najd_2';

  /// Simple Admin invitations (issued inside the tenant by an `admin.manage`
  /// holder — the issuing UI is future scope).
  static const hilalInviteeEmail = 'noura@hilal-medical.org';
  static const hilalExpiredInviteeEmail = 'late@hilal-medical.org';
  static const ruknInviteeEmail = 'majed@rukn-medical.org';

  /// Seeded self-registered accounts, each standing at one step.
  static const unverifiedEmail = 'unverified@mtm.test';
  static const verifiedUnlinkedEmail = 'unlinked@mtm.test';
  static const linkedSetupEmail = 'setup.pending@mtm.test';
  static const readyEmail = 'ready@mtm.test';
  static const googleOnlyEmail = 'google.only@mtm.test';
  static const suspendedEmail = 'suspended@mtm.test';

  static const tenants = <MockOnboardingTenant>[
    MockOnboardingTenant(
        id: nabdTenantId, displayName: 'فريق نبض التطوعي', teamCode: nabdCode),
    MockOnboardingTenant(
        id: najdTenantId,
        displayName: 'فريق نجد للاستجابة',
        teamCode: najdCode),
    MockOnboardingTenant(
        id: hilalTenantId,
        displayName: 'فرق الهلال الطبية',
        teamCode: hilalCode),
    MockOnboardingTenant(
        id: ruknTenantId,
        displayName: 'فريق الركن الطبي',
        teamCode: ruknCode,
        status: SaasTenantStatus.suspended),
  ];

  static const authorizations = <MockAuthorization>[
    MockAuthorization(
      id: 'az_nabd_seat',
      tenantId: nabdTenantId,
      email: nabdMainAdminEmail,
      role: AuthRole.mainAdmin,
      suggestedName: 'هدى الشمري',
      capabilities: Capabilities(global: Cap.all),
      mainAdminKind: MainAdminAuthorizationKind.initialSeat,
      expiresIn: Duration(days: 3),
    ),
    MockAuthorization(
      id: 'az_najd_designate',
      tenantId: najdTenantId,
      email: najdDesignateEmail,
      role: AuthRole.mainAdmin,
      suggestedName: 'ريم القحطاني',
      capabilities: Capabilities(global: Cap.all),
      mainAdminKind: MainAdminAuthorizationKind.replacementDesignate,
      expiresIn: Duration(days: 6),
    ),
    MockAuthorization(
      id: 'az_hilal_admin',
      tenantId: hilalTenantId,
      email: hilalInviteeEmail,
      role: AuthRole.admin,
      suggestedName: 'نورة الدوسري',
      capabilities: Capabilities(global: {
        Cap.detachmentView,
        Cap.memberView,
        Cap.memberContactView,
        Cap.memberInvite,
        Cap.memberEdit,
        Cap.memberRoleAssign,
        Cap.shiftManage,
        Cap.shiftAssign,
        Cap.shiftPublish,
        Cap.shiftAttendanceRecord,
        Cap.shiftOccurrenceManage,
        Cap.inventoryAdjust,
        Cap.inventoryItemManage,
        Cap.workshopCreate,
        Cap.workshopEdit,
        Cap.workshopPeopleManage,
        Cap.workshopAttendanceRecord,
        Cap.workshopSectionManage,
        Cap.statsView,
        Cap.announcementPublish,
      }),
      expiresIn: Duration(days: 7),
    ),
    MockAuthorization(
      id: 'az_hilal_expired',
      tenantId: hilalTenantId,
      email: hilalExpiredInviteeEmail,
      role: AuthRole.admin,
      suggestedName: 'متأخر',
      expiresIn: Duration(days: -1),
    ),
    MockAuthorization(
      id: 'az_rukn_admin',
      tenantId: ruknTenantId,
      email: ruknInviteeEmail,
      role: AuthRole.admin,
      suggestedName: 'ماجد',
      expiresIn: Duration(days: 7),
    ),
    MockAuthorization(
      id: 'az_hilal_setup_pending',
      tenantId: hilalTenantId,
      email: linkedSetupEmail,
      role: AuthRole.admin,
      suggestedName: 'مشرف قيد الإعداد',
    ),
    MockAuthorization(
      id: 'az_hilal_ready',
      tenantId: hilalTenantId,
      email: readyEmail,
      role: AuthRole.admin,
      suggestedName: 'مشرف جاهز',
    ),
  ];

  static const accounts = <MockOnboardingAccount>[
    MockOnboardingAccount(
        accountId: nabdMainAdminAccountId, email: nabdMainAdminEmail),
    MockOnboardingAccount(
        accountId: najdDesignateAccountId, email: najdDesignateEmail),
    MockOnboardingAccount(
        accountId: 'acc_unverified',
        email: unverifiedEmail,
        password: kMockFixturePassword),
    MockOnboardingAccount(
        accountId: 'acc_unlinked',
        email: verifiedUnlinkedEmail,
        password: kMockFixturePassword,
        verified: true),
    MockOnboardingAccount(
        accountId: 'acc_setup_pending',
        email: linkedSetupEmail,
        password: kMockFixturePassword,
        verified: true,
        linkedAuthorizationId: 'az_hilal_setup_pending'),
    MockOnboardingAccount(
        accountId: 'acc_ready',
        email: readyEmail,
        password: kMockFixturePassword,
        verified: true,
        status: AccountStatus.active,
        linkedAuthorizationId: 'az_hilal_ready',
        setupCompleted: true),
    MockOnboardingAccount(
        accountId: 'acc_google_only',
        email: googleOnlyEmail,
        google: true,
        verified: true),
    MockOnboardingAccount(
        accountId: 'acc_suspended',
        email: suspendedEmail,
        password: kMockFixturePassword,
        verified: true,
        status: AccountStatus.suspended),
  ];
}

class _Account {
  _Account(MockOnboardingAccount seed)
      : accountId = seed.accountId,
        email = seed.email,
        password = seed.password,
        google = seed.google,
        verified = seed.verified,
        status = seed.status,
        linkedAuthorizationId = seed.linkedAuthorizationId,
        setupCompleted = seed.setupCompleted;

  final String accountId;
  final String email;
  String? password;
  bool google;
  bool verified;
  AccountStatus status;
  String? linkedAuthorizationId;
  bool linkWithdrawn = false;
  bool setupCompleted;
  String? displayName;

  bool get hasCredential => password != null || google;
}

class _Authorization {
  _Authorization(this.seed, DateTime origin)
      : expiresAt = seed.expiresIn == null ? null : origin.add(seed.expiresIn!);

  final MockAuthorization seed;
  final DateTime? expiresAt;
  bool withdrawn = false;
  bool consumed = false;
}

class _Challenge {
  _Challenge({
    required this.accountId,
    required this.expiresAt,
    required this.resendAt,
  });

  /// `null` for a decoy (sign-up with an already-registered address): the
  /// challenge looks identical and can never be satisfied.
  final String? accountId;
  DateTime expiresAt;
  DateTime resendAt;
  int attemptsLeft = kMockVerificationAttempts;
}

class _Budget {
  int failures = 0;
  DateTime? lockedUntil;
}

/// The authoritative half of the development onboarding service.
///
/// Sharing this object while replacing repositories models a real backend
/// surviving an app-process death. Device credentials never live here; only
/// server-side account/challenge/session state does.
class MockOnboardingServer {
  final Map<String, MockOnboardingTenant> tenants = {};
  final Map<String, _Authorization> _authorizationsById = {};
  final Map<String, _Account> _accountsById = {};
  final Map<String, _Challenge> _challengesByHandle = {};
  final Map<String, ({int fingerprint, Result<Object?> result})> ledger = {};
  final Map<String, _Budget> _budgetsByKey = {};
  final Set<String> exchanged = {};
  final Map<String, String> restrictedSessions = {};

  bool initialized = false;
  int sequence = 0;
  int serverCalls = 0;
  int fullSessionsIssued = 0;

  /// Test hook for expiry/revocation after a process-kill restore.
  void revokeRestrictedSession(String token) {
    restrictedSessions.remove(token);
  }
}

/// Process-memory stand-in for the backend's onboarding service. Device
/// credentials are held separately by [AuthStateStore], which is backed by
/// platform secure storage in the application provider graph.
///
/// Holds no secret beyond what the "server" half must: fixture passwords, and
/// a hash (never the value) of each idempotent request. Logs nothing.
class MockOnboardingRepository implements OnboardingRepository {
  MockOnboardingRepository({
    required DateTime Function() clock,
    bool enabled = demoAccountsAllowed,
    bool Function()? online,
    this.latency = Duration.zero,
    this.seatActivation,
    this.sessionIssued,
    this.authorizationConsumed,
    this.additionalAuthorizations = const [],
    this.excludedAuthorizationIds = const {},
    MockOnboardingServer? server,
    AuthStateStore? authState,
    bool seed = true,
  })  : _clock = clock,
        _server = server ?? MockOnboardingServer(),
        _authState = authState ?? SecureAuthStateStore(InMemorySecureStore()),
        _enabled = enabled && demoAccountsAllowed,
        _online = online ?? (() => true) {
    final origin = clock().toUtc();
    if (!_server.initialized && seed) {
      for (final t in OnboardingFixtures.tenants) {
        _tenants[t.id] = t;
      }
      for (final a in OnboardingFixtures.authorizations) {
        if (!excludedAuthorizationIds.contains(a.id)) {
          _authorizations[a.id] = _Authorization(a, origin);
        }
      }
      for (final a in OnboardingFixtures.accounts) {
        _accounts[a.accountId] = _Account(a);
      }
    }
    _server.initialized = true;
    for (final a in additionalAuthorizations) {
      _authorizations[a.id] = _Authorization(a, origin);
    }
    // The server outlives this instance — a rebuilt provider is the same
    // backend — so an exclusion must reach a record it already holds, not
    // only a first seed. One the server does not itself consider expired was
    // cancelled by its issuer: withdraw it, or it would still auto-link.
    for (final id in excludedAuthorizationIds) {
      final a = _authorizations[id];
      if (a == null || a.withdrawn || a.consumed) continue;
      final expiresAt = a.expiresAt;
      if (expiresAt != null && !_now.isBefore(expiresAt)) continue;
      withdrawAuthorization(id);
    }
  }

  final DateTime Function() _clock;
  final MockOnboardingServer _server;
  final AuthStateStore _authState;
  final bool _enabled;
  final bool Function() _online;
  final Duration latency;
  final MainAdminSeatActivation? seatActivation;
  final OnboardingSessionIssued? sessionIssued;
  final OnboardingAuthorizationConsumed? authorizationConsumed;
  final List<MockAuthorization> additionalAuthorizations;
  final Set<String> excludedAuthorizationIds;

  Map<String, MockOnboardingTenant> get _tenants => _server.tenants;
  Map<String, _Authorization> get _authorizations =>
      _server._authorizationsById;
  Map<String, _Account> get _accounts => _server._accountsById;
  Map<String, _Challenge> get _challenges => _server._challengesByHandle;
  Map<String, ({int fingerprint, Result<Object?> result})> get _ledger =>
      _server.ledger;
  Map<String, _Budget> get _budgets => _server._budgetsByKey;
  Set<String> get _exchanged => _server.exchanged;

  // The device half.
  VerificationChallenge? _heldChallenge;
  String? _sessionAccountId;
  String? _restrictedSessionToken;
  AuthUser? _pendingFullSessionUser;

  int get _seq => _server.sequence;
  set _seq(int value) => _server.sequence = value;

  /// How many requests reached the "server". Offline calls never do.
  int get serverCalls => _server.serverCalls;
  set serverCalls(int value) => _server.serverCalls = value;

  /// Full sessions issued (ready sign-in, setup completion).
  int get fullSessionsIssued => _server.fullSessionsIssued;
  set fullSessionsIssued(int value) => _server.fullSessionsIssued = value;

  String? get restrictedSessionToken => _restrictedSessionToken;

  DateTime get _now => _clock().toUtc();

  /// The grant bound to an authorization. It is never read from onboarding
  /// input and is not exposed by the restricted-session snapshot.
  Capabilities? capabilitiesForAuthorization(String id) =>
      _authorizations[id]?.seed.capabilities;

  // -------------------------------------------------------------------------
  // Test hooks — backend-side events. Not on the interface.
  // -------------------------------------------------------------------------

  String? accountIdFor(String email) =>
      _byEmail(normalizeLoginEmail(email))?.accountId;

  void setTenantStatus(String tenantId, SaasTenantStatus status) {
    final t = _tenants[tenantId]!;
    _tenants[tenantId] = MockOnboardingTenant(
        id: t.id,
        displayName: t.displayName,
        teamCode: t.teamCode,
        status: status);
  }

  /// Final deletion: the Team Code stops resolving and every authorization in
  /// the tenant is withdrawn (an in-setup link becomes `withdrawn`).
  void deleteTenant(String tenantId) {
    setTenantStatus(tenantId, SaasTenantStatus.deleted);
    for (final a in _authorizations.values) {
      if (a.seed.tenantId == tenantId) withdrawAuthorization(a.seed.id);
    }
  }

  /// An invitation cancelled, or a Main Admin seat handed to someone else,
  /// before setup completed.
  void withdrawAuthorization(String authorizationId) {
    _authorizations[authorizationId]!.withdrawn = true;
    for (final account in _accounts.values) {
      if (account.linkedAuthorizationId == authorizationId &&
          !account.setupCompleted) {
        account
          ..linkedAuthorizationId = null
          ..linkWithdrawn = true;
      }
    }
  }

  void setAccountStatus(String email, AccountStatus status) =>
      _byEmail(normalizeLoginEmail(email))!.status = status;

  /// Another device verified the address: every open challenge for the
  /// account ends.
  void verifyElsewhere(String email) {
    final account = _byEmail(normalizeLoginEmail(email))!..verified = true;
    _challenges.removeWhere((_, c) => c.accountId == account.accountId);
  }

  /// Another device finished setup and holds the full session.
  void completeSetupElsewhere(String email) {
    final account = _byEmail(normalizeLoginEmail(email))!
      ..setupCompleted = true
      ..status = AccountStatus.active;
    _exchanged.add(account.accountId);
  }

  // -------------------------------------------------------------------------

  Future<Result<T>?> _gate<T>() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (!_enabled) return Failure<T>('غير متاح.', code: 'not_permitted');
    if (!_online()) return Offline<T>();
    serverCalls++;
    return null;
  }

  _Account? _byEmail(String email) {
    for (final a in _accounts.values) {
      if (a.email == email) return a;
    }
    return null;
  }

  Result<T> _idempotent<T>(
    String key,
    List<Object?> parts,
    Result<T> Function() body,
  ) {
    if (key.trim().isEmpty) return Failure<T>('', code: 'validation');
    final fingerprint = Object.hashAll(parts);
    final hit = _ledger[key];
    if (hit != null) {
      if (hit.fingerprint != fingerprint) {
        return OnboardingFailure<T>(OnboardingProblemCode.idempotencyConflict);
      }
      return hit.result as Result<T>;
    }
    final result = body();
    _ledger[key] = (fingerprint: fingerprint, result: result);
    return result;
  }

  OnboardingFailure<T>? _throttled<T>(String bucket) {
    final until = _budgets[bucket]?.lockedUntil;
    if (until != null && _now.isBefore(until)) {
      return OnboardingFailure<T>(OnboardingProblemCode.rateLimited,
          retryAvailableAt: until);
    }
    return null;
  }

  void _spend(String bucket) {
    final budget = _budgets.putIfAbsent(bucket, _Budget.new);
    budget.failures++;
    if (budget.failures >= kMockFailureBudget) {
      budget
        ..failures = 0
        ..lockedUntil = _now.add(kMockLockout);
    }
  }

  _Account _newAccount(String email) {
    final id = 'acc_${++_seq}';
    return _accounts[id] =
        _Account(MockOnboardingAccount(accountId: id, email: email));
  }

  static String _mask(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return '***';
    return '${email[0]}***${email.substring(at)}';
  }

  VerificationChallenge _issueChallenge(String? accountId, String email) {
    final handle = 'vc_${++_seq}';
    final c = _Challenge(
      accountId: accountId,
      expiresAt: _now.add(kMockCodeValidity),
      resendAt: _now.add(kMockResendCooldown),
    );
    _challenges[handle] = c;
    final challenge = VerificationChallenge(
      handle: handle,
      maskedEmail: _mask(email),
      expiresAt: c.expiresAt,
      resendAvailableAt: c.resendAt,
      attemptsRemaining: c.attemptsLeft,
    );
    _heldChallenge = challenge;
    _clearRestrictedSession();
    _sessionAccountId = null;
    return challenge;
  }

  void _clearRestrictedSession() {
    final token = _restrictedSessionToken;
    if (token != null) _server.restrictedSessions.remove(token);
    _restrictedSessionToken = null;
  }

  void _installRestrictedSession(String accountId) {
    _clearRestrictedSession();
    final token = 'mock_onboarding_session_${++_seq}';
    _server.restrictedSessions[token] = accountId;
    _restrictedSessionToken = token;
    _sessionAccountId = accountId;
  }

  OnboardingSnapshot _snapshot(_Account a) {
    final auth = a.linkedAuthorizationId == null
        ? null
        : _authorizations[a.linkedAuthorizationId];
    final tenant = auth == null ? null : _tenants[auth.seed.tenantId];
    final snapshot = OnboardingSnapshot(
      accountId: a.accountId,
      email: a.email,
      methods: {
        if (a.password != null) AuthMethod.password,
        if (a.google) AuthMethod.google,
      },
      account: a.status,
      link: auth != null
          ? TenantLinkStatus.linked
          : a.linkWithdrawn
              ? TenantLinkStatus.withdrawn
              : TenantLinkStatus.unlinked,
      tenant: auth == null
          ? null
          : LinkedTenant(
              displayName: tenant!.displayName,
              role: auth.seed.role,
              status: tenant.status,
            ),
      setup: a.setupCompleted
          ? AccountSetupStatus.completed
          : AccountSetupStatus.required,
      displayNameSuggestion: a.displayName ?? auth?.seed.suggestedName,
      authorizationExpiresAt: auth?.expiresAt,
    );
    return snapshot;
  }

  /// The one place a verified credential becomes a session.
  AuthEntryOutcome _enter(_Account a) {
    _heldChallenge = null;
    _autoLinkInvitation(a);
    if (a.setupCompleted) {
      _clearRestrictedSession();
      _sessionAccountId = null;
      return _issueFullSession(a);
    }
    _installRestrictedSession(a.accountId);
    return EntryContinueOnboarding(_snapshot(a));
  }

  /// Point 17B — the invitation-bound link path.
  ///
  /// A Simple Admin invitation already names both the tenant and this exact
  /// address, so the backend links it the moment the address is proved —
  /// **no Team Code** ever reaches this recipient (`HANDOFF.md` "POINT 17B"
  /// §4.3, refining Point 17A's "invitation + Team Code" model). A Main
  /// Admin **seat** authorization is deliberately excluded: Team Code stays
  /// the deliberate second channel there (Point 17A "F. Team Code";
  /// `mainAdminKind != null` marks a seat).
  ///
  /// Runs on every authoritative read of a verified account — sign-in,
  /// verification, restore and refresh — so an invitee who verified before
  /// the invitation existed is linked as soon as it does.
  ///
  /// Silently does nothing when no such authorization matches, is already
  /// withdrawn/consumed, has expired, or its tenant is not active — each of
  /// those is still reachable through an explicit `linkTeam` call, which
  /// reports the precise refusal (`invitationExpired`, `tenantUnavailable`,
  /// …) that a no-op here must not swallow.
  void _autoLinkInvitation(_Account a) {
    if (a.linkedAuthorizationId != null) return;
    for (final entry in _authorizations.entries) {
      final auth = entry.value;
      if (auth.seed.mainAdminKind != null) continue;
      if (auth.seed.email != a.email) continue;
      if (auth.withdrawn || auth.consumed) continue;
      final expiresAt = auth.expiresAt;
      if (expiresAt != null && !_now.isBefore(expiresAt)) continue;
      if (_tenants[auth.seed.tenantId]?.status != SaasTenantStatus.active) {
        continue;
      }
      a
        ..linkedAuthorizationId = entry.key
        ..linkWithdrawn = false;
      return;
    }
  }

  /// Builds the full-session [AuthUser] from the account's (consumed)
  /// authorization and hands it to [sessionIssued], so `currentUser()` on the
  /// auth side answers with the account this journey just produced.
  ///
  /// Every field comes from the authorization or the account itself — never
  /// from anything typed on a form — matching the repository interface's own
  /// rule that no method here takes a role, a tenant id or a capability.
  AuthEntryOutcome _issueFullSession(_Account a) {
    fullSessionsIssued++;
    final authId = a.linkedAuthorizationId;
    final auth = authId == null ? null : _authorizations[authId];
    final tenant = auth == null ? null : _tenants[auth.seed.tenantId];
    if (auth != null && tenant != null) {
      _pendingFullSessionUser = AuthUser(
        id: a.accountId,
        name: a.displayName ?? auth.seed.suggestedName,
        email: a.email,
        role: auth.seed.role,
        saasTenantId: tenant.id,
        capabilities: auth.seed.capabilities,
        orgName: tenant.displayName,
      );
    }
    return const EntryReady();
  }

  Future<Result<AuthEntryOutcome>> _persistEntry(
    Result<AuthEntryOutcome> result,
  ) async {
    try {
      if (result case Success(:final data)) {
        switch (data) {
          case EntryVerificationRequired(:final challenge):
            await _authState.writeVerification(challenge);
          case EntryContinueOnboarding(:final snapshot):
            final token = _restrictedSessionToken;
            if (token == null) {
              return const Failure('', code: 'server');
            }
            await _authState.writeRestricted(
              token: token,
              cachedSnapshot: snapshot,
            );
          case EntryReady():
            final user = _pendingFullSessionUser;
            _pendingFullSessionUser = null;
            if (user != null && sessionIssued != null) {
              await sessionIssued!(user);
            } else {
              await _authState.clearOnboarding();
            }
        }
      }
      return result;
    } catch (_) {
      // Never leak a platform-storage exception or report a restorable state
      // that was not durably installed.
      return const Failure('', code: 'server');
    }
  }

  Future<Result<VerificationChallenge>> _persistChallenge(
    Result<VerificationChallenge> result,
  ) async {
    try {
      if (result case Success(:final data)) {
        await _authState.writeVerification(data);
      }
      return result;
    } catch (_) {
      return const Failure('', code: 'server');
    }
  }

  Future<Result<OnboardingSnapshot>> _persistSnapshot(
    Result<OnboardingSnapshot> result,
  ) async {
    try {
      if (result case Success(:final data)) {
        final token = _restrictedSessionToken;
        if (token == null) return const Failure('', code: 'server');
        await _authState.writeRestricted(
          token: token,
          cachedSnapshot: data,
        );
      }
      return result;
    } catch (_) {
      return const Failure('', code: 'server');
    }
  }

  // -------------------------------------------------------------------------
  // OnboardingRepository
  // -------------------------------------------------------------------------

  @override
  Future<Result<AuthEntryState>> restore() async {
    if (!_enabled) return const Success(EntryNone());
    try {
      final stored = await _authState.readOnboarding();
      _heldChallenge = null;
      _sessionAccountId = null;
      _restrictedSessionToken = null;
      switch (stored) {
        case null:
          return const Success(EntryNone());
        case StoredVerificationState(:final challenge):
          if (!_online()) {
            return Offline(cached: EntryVerificationPending(challenge));
          }
          serverCalls++;
          final serverChallenge = _challenges[challenge.handle];
          if (serverChallenge == null) {
            await _authState.clearOnboarding();
            return const Success(
              EntryNone(notice: EntryNotice.verificationEnded),
            );
          }
          final refreshed = VerificationChallenge(
            handle: challenge.handle,
            maskedEmail: challenge.maskedEmail,
            codeLength: challenge.codeLength,
            expiresAt: serverChallenge.expiresAt,
            resendAvailableAt: serverChallenge.resendAt,
            attemptsRemaining: serverChallenge.attemptsLeft,
          );
          _heldChallenge = refreshed;
          await _authState.writeVerification(refreshed);
          return Success(EntryVerificationPending(refreshed));
        case StoredRestrictedSession(:final token, :final cachedSnapshot):
          _restrictedSessionToken = token;
          if (!_online()) {
            return Offline(
              cached: EntryOnboarding(cachedSnapshot, stale: true),
            );
          }
          serverCalls++;
          final accountId = _server.restrictedSessions[token];
          final account = accountId == null ? null : _accounts[accountId];
          if (account == null) {
            await _authState.clearOnboarding();
            _restrictedSessionToken = null;
            return const Success(
              EntryNone(notice: EntryNotice.sessionEnded),
            );
          }
          _sessionAccountId = accountId;
          if (_exchanged.contains(accountId) || account.setupCompleted) {
            _clearRestrictedSession();
            await _authState.clearOnboarding();
            return const Success(
              EntryNone(notice: EntryNotice.setupCompletedElsewhere),
            );
          }
          _autoLinkInvitation(account);
          final snapshot = _snapshot(account);
          await _authState.writeRestricted(
            token: token,
            cachedSnapshot: snapshot,
          );
          return Success(EntryOnboarding(snapshot));
      }
    } catch (_) {
      return const Failure('', code: 'server');
    }
  }

  @override
  Future<Result<VerificationChallenge>> signUpWithPassword({
    required String email,
    required String password,
    required String idempotencyKey,
  }) async {
    final gated = await _gate<VerificationChallenge>();
    if (gated != null) return gated;
    final e = normalizeLoginEmail(email);
    final result = _idempotent<VerificationChallenge>(
        idempotencyKey, ['signup', e, password], () {
      if (validateLoginEmail(email) != null) {
        return const Failure('', code: 'validation');
      }
      final throttled = _throttled<VerificationChallenge>('signup:$e');
      if (throttled != null) return throttled;
      if (checkPasswordInput(password) != null) {
        return const OnboardingFailure(OnboardingProblemCode.passwordRejected);
      }
      final existing = _byEmail(e);
      if (existing != null && existing.verified && existing.hasCredential) {
        // Anti-enumeration: the same answer as a fresh sign-up, a challenge
        // that can never be satisfied. The real owner is told by email. Not
        // even the throttle may differ, or it becomes the oracle.
        return Success(_issueChallenge(null, e));
      }
      final account = existing ?? _newAccount(e);
      // An unverified credential proved nothing, so a new sign-up replaces it
      // — the defence against someone pre-registering another's address.
      account.password = password;
      return Success(_issueChallenge(account.accountId, e));
    });
    return _persistChallenge(result);
  }

  @override
  Future<Result<AuthEntryOutcome>> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final gated = await _gate<AuthEntryOutcome>();
    if (gated != null) return gated;
    final e = normalizeLoginEmail(email);
    final throttled = _throttled<AuthEntryOutcome>('login:$e');
    if (throttled != null) return throttled;
    // The normal Login fields are also the only development entry point.
    // This branch is compile-time absent outside debug and exact-password
    // only; it never provisions an account or consults onboarding input for
    // role, tenant, or capabilities.
    if (demoAccountsAllowed && _enabled) {
      final credential = DevTestCredentials.forEmail(e);
      if (credential != null) {
        if (!credential.matchesPassword(password)) {
          _spend('login:$e');
          return const OnboardingFailure(
            OnboardingProblemCode.invalidCredentials,
          );
        }
        _budgets.remove('login:$e');
        _heldChallenge = null;
        _clearRestrictedSession();
        _sessionAccountId = null;
        fullSessionsIssued++;
        _pendingFullSessionUser = credential.user;
        return _persistEntry(const Success(EntryReady()));
      }
    }
    final account = _byEmail(e);
    if (account == null ||
        account.password == null ||
        account.password != password) {
      _spend('login:$e');
      return const OnboardingFailure(OnboardingProblemCode.invalidCredentials);
    }
    _budgets.remove('login:$e');
    if (!account.verified) {
      return _persistEntry(Success(
        EntryVerificationRequired(_issueChallenge(account.accountId, e)),
      ));
    }
    return _persistEntry(Success(_enter(account)));
  }

  @override
  Future<Result<AuthEntryOutcome>> signInWithGoogle(
    GoogleIdentityAssertion assertion, {
    required String idempotencyKey,
  }) async {
    final gated = await _gate<AuthEntryOutcome>();
    if (gated != null) return gated;
    final token = assertion.idToken;
    final result =
        _idempotent<AuthEntryOutcome>(idempotencyKey, ['google', token], () {
      final bool emailVerified;
      final String raw;
      if (token.startsWith(kMockGoogleUnverifiedPrefix)) {
        emailVerified = false;
        raw = token.substring(kMockGoogleUnverifiedPrefix.length);
      } else if (token.startsWith(kMockGoogleVerifiedPrefix)) {
        emailVerified = true;
        raw = token.substring(kMockGoogleVerifiedPrefix.length);
      } else {
        return const OnboardingFailure(
            OnboardingProblemCode.googleAssertionRejected);
      }
      if (validateLoginEmail(raw) != null) {
        return const OnboardingFailure(
            OnboardingProblemCode.googleAssertionRejected);
      }
      final e = normalizeLoginEmail(raw);
      var account = _byEmail(e);
      if (account == null) {
        account = _newAccount(e)..google = true;
      } else if (!account.google) {
        if (account.password != null && account.verified) {
          // Never merged automatically: prove the password first.
          return const OnboardingFailure(
              OnboardingProblemCode.authMethodLinkRequired);
        }
        // Unclaimed (provisioned) or unverified-password: Google's verified
        // assertion is the stronger claim; an unverified password is dropped.
        account
          ..password = null
          ..google = true;
      }
      if (emailVerified) account.verified = true;
      if (!account.verified) {
        return Success(
            EntryVerificationRequired(_issueChallenge(account.accountId, e)));
      }
      return Success(_enter(account));
    });
    return _persistEntry(result);
  }

  @override
  Future<Result<AuthEntryOutcome>> verifyEmail({
    required VerificationChallenge challenge,
    required String code,
    required String idempotencyKey,
  }) async {
    final gated = await _gate<AuthEntryOutcome>();
    if (gated != null) return gated;
    final handle = challenge.handle;
    final result = _idempotent<AuthEntryOutcome>(
        idempotencyKey, ['verify', handle, code], () {
      final c = _challenges[handle];
      if (c == null) {
        if (_heldChallenge?.handle == handle) _heldChallenge = null;
        return const OnboardingFailure(
            OnboardingProblemCode.verificationChallengeEnded);
      }
      if (!_now.isBefore(c.expiresAt)) {
        return const OnboardingFailure(
            OnboardingProblemCode.verificationCodeExpired);
      }
      final accountId = c.accountId;
      if (accountId == null || code != kMockVerificationCode) {
        c.attemptsLeft--;
        if (c.attemptsLeft <= 0) {
          _challenges.remove(handle);
          if (_heldChallenge?.handle == handle) _heldChallenge = null;
          return const OnboardingFailure(
              OnboardingProblemCode.verificationChallengeEnded);
        }
        if (_heldChallenge?.handle == handle) {
          _heldChallenge =
              _heldChallenge!.copyWith(attemptsRemaining: c.attemptsLeft);
        }
        return OnboardingFailure(OnboardingProblemCode.verificationCodeInvalid,
            attemptsRemaining: c.attemptsLeft);
      }
      _challenges.remove(handle);
      final account = _accounts[accountId]!..verified = true;
      return Success(_enter(account));
    });
    if (result
        case OnboardingFailure(
          problem: OnboardingProblemCode.verificationChallengeEnded
        )) {
      await _authState.clearOnboarding();
    }
    return _persistEntry(result);
  }

  @override
  Future<Result<VerificationChallenge>> resendVerification({
    required VerificationChallenge challenge,
    required String idempotencyKey,
  }) async {
    final gated = await _gate<VerificationChallenge>();
    if (gated != null) return gated;
    final result = _idempotent<VerificationChallenge>(
        idempotencyKey, ['resend', challenge.handle], () {
      final c = _challenges[challenge.handle];
      if (c == null) {
        return const OnboardingFailure(
            OnboardingProblemCode.verificationChallengeEnded);
      }
      if (_now.isBefore(c.resendAt)) {
        return OnboardingFailure(
            OnboardingProblemCode.verificationResendThrottled,
            retryAvailableAt: c.resendAt);
      }
      c
        ..expiresAt = _now.add(kMockCodeValidity)
        ..resendAt = _now.add(kMockResendCooldown)
        ..attemptsLeft = kMockVerificationAttempts;
      final updated = challenge.copyWith(
        expiresAt: c.expiresAt,
        resendAvailableAt: c.resendAt,
        attemptsRemaining: c.attemptsLeft,
      );
      _heldChallenge = updated;
      return Success(updated);
    });
    if (result
        case OnboardingFailure(
          problem: OnboardingProblemCode.verificationChallengeEnded
        )) {
      await _authState.clearOnboarding();
    }
    return _persistChallenge(result);
  }

  /// The onboarding session's account, or the refusal that stands for it.
  Failure<T>? _sessionRefusal<T>() {
    final id = _sessionAccountId;
    if (id == null) return Failure<T>('', code: 'authentication_expired');
    final account = _accounts[id]!;
    if (_exchanged.contains(id) || account.setupCompleted) {
      return OnboardingFailure<T>(OnboardingProblemCode.setupAlreadyCompleted);
    }
    if (account.status == AccountStatus.suspended ||
        account.status == AccountStatus.revoked) {
      return OnboardingFailure<T>(OnboardingProblemCode.accountUnavailable);
    }
    return null;
  }

  @override
  Future<Result<OnboardingSnapshot>> refresh() async {
    final gated = await _gate<OnboardingSnapshot>();
    if (gated != null) return gated;
    final id = _sessionAccountId;
    if (id == null) return const Failure('', code: 'authentication_expired');
    final account = _accounts[id]!;
    if (_exchanged.contains(id) || account.setupCompleted) {
      _clearRestrictedSession();
      _sessionAccountId = null;
      await _authState.clearOnboarding();
      return const OnboardingFailure(
          OnboardingProblemCode.setupAlreadyCompleted);
    }
    // An invitation issued (or reissued, or whose tenant resumed) after the
    // address was verified links on the next authoritative read — the
    // invitee's way off `/link-team` without a Team Code.
    _autoLinkInvitation(account);
    // A suspended or revoked account still reads its own state, so the
    // classifier can route it to the right blocking screen.
    return _persistSnapshot(Success(_snapshot(account)));
  }

  @override
  Future<Result<OnboardingSnapshot>> linkTeam({
    required String teamCode,
    required String idempotencyKey,
  }) async {
    final gated = await _gate<OnboardingSnapshot>();
    if (gated != null) return gated;
    final canonical = normalizeTeamCodeInput(teamCode);
    final result = _idempotent<OnboardingSnapshot>(
        idempotencyKey, ['link', canonical], () {
      final refused = _sessionRefusal<OnboardingSnapshot>();
      if (refused != null) return refused;
      final account = _accounts[_sessionAccountId]!;
      final bucket = 'link:${account.accountId}';
      final throttled = _throttled<OnboardingSnapshot>(bucket);
      if (throttled != null) return throttled;
      if (validateTeamCodeInput(teamCode) != null) {
        return const OnboardingFailure(OnboardingProblemCode.teamCodeMalformed);
      }
      MockOnboardingTenant? tenant;
      for (final t in _tenants.values) {
        if (t.teamCode == canonical && t.status != SaasTenantStatus.deleted) {
          tenant = t;
        }
      }
      // Already linked is answered before the code is evaluated, so a linked
      // account learns nothing about a code it did not use.
      final current = account.linkedAuthorizationId;
      if (current != null) {
        return _authorizations[current]!.seed.tenantId == tenant?.id
            ? Success(_snapshot(account))
            : const OnboardingFailure(
                OnboardingProblemCode.accountAlreadyLinked);
      }
      _Authorization? auth;
      if (tenant != null) {
        for (final a in _authorizations.values) {
          if (a.seed.tenantId == tenant.id &&
              a.seed.email == account.email &&
              !a.withdrawn &&
              !a.consumed) {
            auth = a;
          }
        }
      }
      if (tenant == null || auth == null) {
        _spend(bucket);
        return const OnboardingFailure(OnboardingProblemCode.teamLinkRefused);
      }
      final expiresAt = auth.expiresAt;
      if (expiresAt != null && !_now.isBefore(expiresAt)) {
        return const OnboardingFailure(OnboardingProblemCode.invitationExpired);
      }
      if (tenant.status != SaasTenantStatus.active) {
        return const OnboardingFailure(OnboardingProblemCode.tenantUnavailable);
      }
      account
        ..linkedAuthorizationId = auth.seed.id
        ..linkWithdrawn = false;
      _budgets.remove(bucket);
      return Success(_snapshot(account));
    });
    return _persistSnapshot(result);
  }

  @override
  Future<Result<AuthEntryOutcome>> completeSetup({
    required String displayName,
    required String idempotencyKey,
  }) async {
    final gated = await _gate<AuthEntryOutcome>();
    if (gated != null) return gated;
    final name = normalizeDisplayName(displayName);
    final result =
        _idempotent<AuthEntryOutcome>(idempotencyKey, ['setup', name], () {
      final refused = _sessionRefusal<AuthEntryOutcome>();
      if (refused != null) return refused;
      final account = _accounts[_sessionAccountId]!;
      if (validateDisplayName(displayName) != null) {
        return const Failure('', code: 'validation');
      }
      final authId = account.linkedAuthorizationId;
      final auth = authId == null ? null : _authorizations[authId];
      if (auth == null || auth.withdrawn) {
        return const OnboardingFailure(OnboardingProblemCode.setupUnavailable);
      }
      final expiresAt = auth.expiresAt;
      if (expiresAt != null && !_now.isBefore(expiresAt)) {
        return const OnboardingFailure(OnboardingProblemCode.invitationExpired);
      }
      if (_tenants[auth.seed.tenantId]!.status != SaasTenantStatus.active) {
        return const OnboardingFailure(OnboardingProblemCode.tenantUnavailable);
      }
      final kind = auth.seed.mainAdminKind;
      final activate = seatActivation;
      if (kind != null && activate != null) {
        // The backend's atomic seat transition (Point 14). Refused here means
        // nothing below runs: no activation, no session.
        final problem = activate(auth.seed.tenantId, kind);
        if (problem != null) return OnboardingFailure(problem);
      }
      account
        ..setupCompleted = true
        ..status = AccountStatus.active
        ..displayName = name;
      auth.consumed = true;
      authorizationConsumed?.call(
        auth.seed,
        accountId: account.accountId,
        displayName: name,
      );
      _exchanged.add(account.accountId);
      _clearRestrictedSession();
      _sessionAccountId = null;
      return Success(_issueFullSession(account));
    });
    return _persistEntry(result);
  }

  @override
  Future<Result<void>> abandon() async {
    // Discarding the device's handle and token never needs the network and
    // never fails; the server-side revoke is best effort.
    _heldChallenge = null;
    _clearRestrictedSession();
    _sessionAccountId = null;
    await _authState.clearOnboarding();
    return const Success(null);
  }
}
