/// Point 17A — the typed pre-session journey of a tenant administrator.
///
/// **Five questions, five models — never one `isOnboarded` flag.**
///
/// | Machine | Question | Where it lives |
/// | --- | --- | --- |
/// | A. Authentication | who is this identity? | [AuthMethod], [AuthEntryOutcome] |
/// | B. Email verification | does this identity own its login address? | [VerificationChallenge] |
/// | C. Tenant link | which `SaasTenant`, if any, may it administer? | [TenantLinkStatus], [LinkedTenant] |
/// | D. Account setup | has it finished first use? | [AccountSetupStatus] |
/// | E. Session / startup | which surface opens now? | [AuthEntryState] → `resolveStartup` |
///
/// Account lifecycle is not a sixth machine: it is the existing
/// [AccountStatus] from the session envelope, reused here so the same account
/// never has two lifecycle vocabularies.
///
/// ## Trust transitions (the only ones there are)
///
/// ```text
/// signed out
///   ├─ sign up (email+password) ─────────▶ verification pending   (no session)
///   ├─ sign in, address unverified ──────▶ verification pending   (no session)
///   ├─ sign in, verified, not ready ─────▶ onboarding session     (restricted)
///   └─ sign in, verified, ready ─────────▶ full session           (AuthUser)
/// verification pending ── correct code ──▶ onboarding session | full session
/// onboarding session
///   ├─ Team Code + matching authorization ▶ linked, setup required
///   └─ complete setup (backend activates)  ▶ full session
/// ```
///
/// Every arrow is a **server** decision. Flutter submits evidence (a
/// password, a Google assertion, a code, a Team Code, a display name) and
/// renders the answer; it never concludes verification, a link, a role, a
/// capability or a seat activation on its own.
///
/// ## What never lives here
///
/// Passwords, verification codes, Team Codes and Google tokens are **call
/// arguments only**. No model in this file stores one, no `toString` prints
/// one, and [AuthEntryState] — the one thing that outlives a call — carries
/// none. The verification challenge's opaque handle is the single
/// backend-issued value kept between calls, and its `toString` redacts it.
library;

import 'package:flutter/foundation.dart';

import '../../../core/access/saas_tenant_status.dart';
import '../../../core/text/search_key.dart';
import '../../platform/domain/saas_tenant_validation.dart'
    show
        SaasTenantFieldError,
        kMainAdminEmailMaxLength,
        kMainAdminNameMaxLength,
        validateMainAdminEmail;
import '../../platform/domain/team_code.dart';
import 'auth_models.dart';
import 'session_access.dart';

// ---------------------------------------------------------------------------
// A. Authentication methods
// ---------------------------------------------------------------------------

/// The two ways an administrator proves who they are. Exactly two in Point 17
/// — Apple, phone, magic link, passkeys and anonymous sign-in are future scope
/// and deliberately have no value here.
enum AuthMethod {
  password('password'),
  google('google');

  const AuthMethod(this.wire);

  final String wire;

  /// `null` for a method this build does not know. Methods are *metadata*
  /// about an account, not a gate, so an unknown one is dropped by the parser
  /// rather than failing the whole snapshot closed.
  static AuthMethod? tryParse(String wire) {
    for (final method in values) {
      if (method.wire == wire) return method;
    }
    return null;
  }
}

/// A Google identity assertion obtained by the Google SDK on the device.
///
/// **Evidence, not identity.** Flutter never reads a claim out of it — not the
/// email, not `email_verified`, not the name. The backend verifies the token's
/// signature, issuer and audience and decides everything that follows,
/// including whether this Google identity maps to an existing MTM account.
@immutable
class GoogleIdentityAssertion {
  const GoogleIdentityAssertion(this.idToken);

  /// Secret for as long as it lives. Sent once, never stored, never logged.
  final String idToken;

  @override
  String toString() => 'GoogleIdentityAssertion(<redacted>)';
}

// ---------------------------------------------------------------------------
// Input normalization — courtesy checks; the backend re-validates everything
// ---------------------------------------------------------------------------

const int kLoginEmailMaxLength = kMainAdminEmailMaxLength;

enum LoginEmailError { empty, tooLong, malformed }

/// The login address in comparison form.
///
/// **The same normalization as `normalizeMainAdminEmail`** on purpose: an
/// invitation provisioned from the Platform is matched against the address a
/// person signs up with, and two normalizations would make that match depend
/// on which screen typed the address. A test pins the two equal. No
/// provider-specific folding (Gmail dots, `+tags`) — that is backend policy.
String normalizeLoginEmail(String raw) => collapseWhitespace(raw).toLowerCase();

/// Shape only, through the one email rule the app already has
/// (`validateMainAdminEmail`). Whether the address exists, or is taken, is
/// never a client fact — and is never *told* to the client either (see the
/// account-enumeration policy in `API_CONTRACT.md`).
LoginEmailError? validateLoginEmail(String raw) =>
    switch (validateMainAdminEmail(raw)) {
      null => null,
      SaasTenantFieldError.required => LoginEmailError.empty,
      SaasTenantFieldError.tooLong => LoginEmailError.tooLong,
      _ => LoginEmailError.malformed,
    };

/// **PROVISIONAL — BACKEND DECISION REQUIRED.** A courtesy floor so a form
/// can say "too short" before a round trip. It mirrors the existing reset
/// flow's mock floor; the backend's password policy is authoritative and may
/// refuse a longer password (`password_rejected`) for reasons the client
/// cannot see (breached, common, too long).
const int kPasswordAdvisoryMinLength = 8;

enum PasswordInputError { empty, belowAdvisoryMinimum }

/// Never trims: a space can be part of a password.
PasswordInputError? checkPasswordInput(String raw) {
  if (raw.isEmpty) return PasswordInputError.empty;
  if (raw.length < kPasswordAdvisoryMinLength) {
    return PasswordInputError.belowAdvisoryMinimum;
  }
  return null;
}

/// **PROVISIONAL — BACKEND DECISION REQUIRED.** Used only when a challenge
/// arrives without `codeLength`. Matches the six-digit codes the existing
/// MFA and password-reset contracts already use.
const int kDefaultVerificationCodeLength = 6;

enum VerificationCodeError { empty, malformed }

/// A typed or pasted code in submission form: Arabic-Indic and Persian
/// digits folded to ASCII, spaces and hyphens removed.
String normalizeVerificationCode(String raw) =>
    foldDigitsToAscii(raw).replaceAll(RegExp(r'[\s\-]'), '');

/// Numeric, exactly [length] digits. Anything else is refused before a
/// request — which also keeps a typo from spending a server-side attempt.
VerificationCodeError? validateVerificationCode(
  String raw, {
  int length = kDefaultVerificationCodeLength,
}) {
  final code = normalizeVerificationCode(raw);
  if (code.isEmpty) return VerificationCodeError.empty;
  if (code.length != length || !RegExp(r'^[0-9]+$').hasMatch(code)) {
    return VerificationCodeError.malformed;
  }
  return null;
}

/// A typed Team Code in canonical form (`MTM-XXXX-XXXX`).
///
/// Adds to the Platform's [normalizeTeamCode] exactly two things a person
/// joining a team needs: Arabic-Indic digits are folded first (the Platform
/// rule would silently strip them), and the `MTM` prefix may be omitted when
/// the eight body characters are typed alone. Anything else passes through
/// for [validateTeamCodeInput] to refuse.
String normalizeTeamCodeInput(String raw) {
  final bare =
      foldDigitsToAscii(raw).toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
  const bodyLength = kTeamCodeGroupSize * kTeamCodeGroups;
  final prefixed = bare.length == bodyLength ? '$kTeamCodePrefix$bare' : bare;
  return normalizeTeamCode(prefixed);
}

/// Format only — **not** a security control. The alphabet and shape are
/// public; the server resolves, rate-limits and refuses. A malformed code is
/// refused locally so it never spends the account's server-side attempts.
TeamCodeError? validateTeamCodeInput(String raw) {
  if (raw.trim().isEmpty) return TeamCodeError.empty;
  return validateTeamCode(normalizeTeamCodeInput(raw));
}

const int kDisplayNameMaxLength = kMainAdminNameMaxLength;

enum DisplayNameError { empty, tooLong }

/// Display name policy (Point 17A):
///
/// - **Origin.** Suggested by the backend at setup — the name the inviter
///   entered on the authorization first, else the Google profile name the
///   backend read from the verified token, else nothing. Flutter never reads
///   a Google claim itself.
/// - **Editable** at setup; whitespace-collapsed; 1–[kDisplayNameMaxLength].
/// - **Not identity-critical.** Two admins may share one. It never keys a
///   record, never matches an invitation and never drives authorization.
String normalizeDisplayName(String raw) => collapseWhitespace(raw);

DisplayNameError? validateDisplayName(String raw) {
  final value = normalizeDisplayName(raw);
  if (value.isEmpty) return DisplayNameError.empty;
  if (value.length > kDisplayNameMaxLength) return DisplayNameError.tooLong;
  return null;
}

// ---------------------------------------------------------------------------
// B. Email verification
// ---------------------------------------------------------------------------

/// A backend-issued email-ownership challenge. **Not a session.**
///
/// Issued by sign-up (always — whether or not the address already had an
/// account, see the enumeration policy), by a password sign-in to an
/// unverified account, and by a Google sign-in whose token does not assert a
/// verified address. Holding one grants nothing: only [handle] plus the code
/// mailed to the address turns into a session.
@immutable
class VerificationChallenge {
  VerificationChallenge({
    required this.handle,
    required this.maskedEmail,
    this.codeLength = kDefaultVerificationCodeLength,
    DateTime? expiresAt,
    DateTime? resendAvailableAt,
    this.attemptsRemaining,
  })  : expiresAt = expiresAt?.toUtc(),
        resendAvailableAt = resendAvailableAt?.toUtc() {
    if (handle.trim().isEmpty) throw ArgumentError('handle is empty');
    if (maskedEmail.trim().isEmpty) throw ArgumentError('maskedEmail is empty');
    if (codeLength < 4 || codeLength > 10) {
      throw ArgumentError.value(codeLength, 'codeLength');
    }
    if (attemptsRemaining != null && attemptsRemaining! < 0) {
      throw ArgumentError.value(attemptsRemaining, 'attemptsRemaining');
    }
  }

  /// Opaque, backend-issued, short-lived. Kept only in secure storage (so a
  /// relaunch returns to the code screen) and discarded on success, on
  /// abandon and when the challenge ends. Never logged — see [toString].
  final String handle;

  /// The destination as the **server** masked it (`h***@nabd-team.org`).
  /// The client never re-derives a mask from a full address it does not have.
  final String maskedEmail;

  final int codeLength;

  /// When the current code stops being accepted. Server time; absent when the
  /// backend does not disclose it.
  final DateTime? expiresAt;

  /// When a resend will next be accepted. Server time; absent means now.
  final DateTime? resendAvailableAt;

  /// Wrong-code attempts left on this challenge, when the backend discloses it.
  final int? attemptsRemaining;

  /// Fails toward "expired" at the instant itself.
  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !now.toUtc().isBefore(expiresAt!);

  /// The cooldown to show before "resend" is offered again. Display only —
  /// the backend enforces the throttle whatever this says.
  Duration resendCooldownAt(DateTime now) {
    final at = resendAvailableAt;
    if (at == null) return Duration.zero;
    final left = at.difference(now.toUtc());
    return left.isNegative ? Duration.zero : left;
  }

  bool canResendAt(DateTime now) => resendCooldownAt(now) == Duration.zero;

  VerificationChallenge copyWith({
    DateTime? expiresAt,
    DateTime? resendAvailableAt,
    int? attemptsRemaining,
  }) =>
      VerificationChallenge(
        handle: handle,
        maskedEmail: maskedEmail,
        codeLength: codeLength,
        expiresAt: expiresAt ?? this.expiresAt,
        resendAvailableAt: resendAvailableAt ?? this.resendAvailableAt,
        attemptsRemaining: attemptsRemaining ?? this.attemptsRemaining,
      );

  /// Strict: a challenge without a handle or a masked destination is not a
  /// challenge, and a malformed timestamp is refused rather than guessed.
  factory VerificationChallenge.fromJson(Map<String, dynamic> j) {
    final handle = j['challengeId'];
    final masked = j['maskedEmail'];
    final length = j['codeLength'] ?? kDefaultVerificationCodeLength;
    final attempts = j['attemptsRemaining'];
    if (handle is! String || handle.trim().isEmpty) {
      throw const FormatException('VerificationChallenge.challengeId');
    }
    if (masked is! String || masked.trim().isEmpty) {
      throw const FormatException('VerificationChallenge.maskedEmail');
    }
    if (length is! int || length < 4 || length > 10) {
      throw const FormatException('VerificationChallenge.codeLength');
    }
    if (attempts != null && (attempts is! int || attempts < 0)) {
      throw const FormatException('VerificationChallenge.attemptsRemaining');
    }
    return VerificationChallenge(
      handle: handle,
      maskedEmail: masked,
      codeLength: length,
      expiresAt: parseOnboardingInstant(j['expiresAt'], 'expiresAt'),
      resendAvailableAt:
          parseOnboardingInstant(j['resendAvailableAt'], 'resendAvailableAt'),
      attemptsRemaining: attempts as int?,
    );
  }

  /// For the secure-storage record only. Never for a log or an analytics
  /// payload.
  Map<String, dynamic> toJson() => {
        'challengeId': handle,
        'maskedEmail': maskedEmail,
        'codeLength': codeLength,
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        if (resendAvailableAt != null)
          'resendAvailableAt': resendAvailableAt!.toIso8601String(),
        if (attemptsRemaining != null) 'attemptsRemaining': attemptsRemaining,
      };

  @override
  bool operator ==(Object other) =>
      other is VerificationChallenge &&
      other.handle == handle &&
      other.maskedEmail == maskedEmail &&
      other.codeLength == codeLength &&
      other.expiresAt == expiresAt &&
      other.resendAvailableAt == resendAvailableAt &&
      other.attemptsRemaining == attemptsRemaining;

  @override
  int get hashCode => Object.hash(handle, maskedEmail, codeLength, expiresAt,
      resendAvailableAt, attemptsRemaining);

  @override
  String toString() => 'VerificationChallenge(<redacted>, $maskedEmail, '
      'expires: $expiresAt, resend: $resendAvailableAt, '
      'attempts: $attemptsRemaining)';
}

/// RFC 3339 with an explicit offset, or `null` when absent. The same rule
/// `SessionAccess` applies to `sessionExpiresAt`: a local timestamp would
/// expire at different instants on different devices, so it is refused.
DateTime? parseOnboardingInstant(Object? raw, String field) {
  if (raw == null) return null;
  if (raw is String && RegExp(r'(?:[zZ]|[+-]\d{2}:\d{2})$').hasMatch(raw)) {
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toUtc();
  }
  throw FormatException('$field is not an RFC 3339 instant', raw);
}

// ---------------------------------------------------------------------------
// C. Tenant link
// ---------------------------------------------------------------------------

/// Whether this account is attached to a `SaasTenant`.
///
/// ```text
/// unlinked ──Team Code + matching authorization──▶ linked
/// linked (setup pending) ──authorization cancelled/replaced/tenant deleted──▶ withdrawn
/// withdrawn ──another valid Team Code + authorization──▶ linked
/// ```
///
/// One account, **at most one tenant** — ever, in Point 17. A linked account
/// never becomes unlinked: once setup completes its exits are the account
/// lifecycle (`suspended`, `revoked`), not a link change. Multi-tenant
/// membership and tenant switching are future scope and nothing here models
/// them.
enum TenantLinkStatus {
  unlinked('unlinked'),
  linked('linked'),

  /// A link that existed before setup completed and was withdrawn by the
  /// backend — the invitation was cancelled, the Main Admin seat went to
  /// someone else, or the tenant was deleted. Told apart from [unlinked] only
  /// so the link screen can say so; it routes identically.
  withdrawn('withdrawn');

  const TenantLinkStatus(this.wire);

  final String wire;

  static TenantLinkStatus? tryParse(String wire) {
    for (final status in values) {
      if (status.wire == wire) return status;
    }
    return null;
  }
}

/// The **safe confirmation** of the tenant a link names — what the link and
/// setup screens may show before the account is inside that tenant.
///
/// Display name, the role the backend assigned, the tenant's lifecycle. No
/// tenant id, no Team Code, no counts, no Main Admin identity, no operational
/// datum: the account is not inside this tenant until setup completes.
@immutable
class LinkedTenant {
  const LinkedTenant({
    required this.displayName,
    required this.role,
    required this.status,
  });

  final String displayName;

  /// Assigned by the backend from the authorization (seat designation or
  /// admin invitation). **Never** from anything the client sent. Display
  /// only — capabilities still arrive with the full session.
  final AuthRole role;

  final SaasTenantStatus status;

  @override
  bool operator ==(Object other) =>
      other is LinkedTenant &&
      other.displayName == displayName &&
      other.role == role &&
      other.status == status;

  @override
  int get hashCode => Object.hash(displayName, role, status);
}

// ---------------------------------------------------------------------------
// D. Account setup
// ---------------------------------------------------------------------------

/// First-use setup: confirming the display name and **accepting the role in
/// the named tenant**. Completion is the backend event that activates the
/// account — and, for a Main Admin authorization, runs the Point 14 seat
/// transition (`MainAdminPolicy.completeSetup` / `.completeReplacement`).
///
/// No temporary password, no forced password change and no terms acceptance
/// in Point 17A: the person set their own password at sign-up (or uses
/// Google), and Privacy/Terms are deferred until the backend finalizes them.
enum AccountSetupStatus {
  required('required'),
  completed('completed');

  const AccountSetupStatus(this.wire);

  final String wire;

  static AccountSetupStatus? tryParse(String wire) {
    for (final status in values) {
      if (status.wire == wire) return status;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// The onboarding snapshot — what a restricted session reads
// ---------------------------------------------------------------------------

/// A gating field of [OnboardingSnapshot]. A value this build cannot
/// interpret in any of these fails the whole journey closed
/// (`StartupDestination.unsupportedAccessState`) — the same rule, for the same
/// reason, as `AccessLifecycleField`.
enum OnboardingField {
  accountStatus('accountStatus'),
  linkStatus('linkStatus'),
  role('role'),
  tenantStatus('tenantStatus'),
  setupStatus('setupStatus');

  const OnboardingField(this.wire);

  final String wire;
}

/// The authoritative state of an account that holds a **restricted
/// onboarding session** — verified, but not yet a full tenant session.
///
/// Read from the backend on every restore and refresh; never assembled by the
/// client out of what it last sent. Everything here is a server statement.
@immutable
class OnboardingSnapshot {
  OnboardingSnapshot({
    required this.accountId,
    required this.email,
    required Set<AuthMethod> methods,
    required this.account,
    required this.link,
    this.tenant,
    required this.setup,
    this.displayNameSuggestion,
    DateTime? authorizationExpiresAt,
    Map<OnboardingField, String> unsupported = const {},
  })  : methods = Set.unmodifiable(methods),
        authorizationExpiresAt = authorizationExpiresAt?.toUtc(),
        unsupported = Map.unmodifiable(unsupported) {
    if (accountId.trim().isEmpty) throw ArgumentError('accountId is empty');
    if (email.trim().isEmpty) throw ArgumentError('email is empty');
    // Structural invariants hold only for fields this build could read; an
    // unsupported field already fails the snapshot closed.
    if (hasUnsupportedState) return;
    if ((link == TenantLinkStatus.linked) != (tenant != null)) {
      throw ArgumentError('a tenant is present exactly when linked');
    }
    if (link != TenantLinkStatus.linked &&
        setup == AccountSetupStatus.completed) {
      throw ArgumentError('setup cannot be complete without a link');
    }
    if (tenant != null && !tenant!.role.belongsToSaasTenant) {
      throw ArgumentError('super_admin is never onboarded into a tenant');
    }
  }

  /// The canonical backend account id. Independent of every auth method and
  /// of the email: it is what stays the same when a method is linked later.
  final String accountId;

  /// The account's own normalized login address. Shown back to its owner on
  /// the link screen ("signed in as …") — never anyone else's.
  final String email;

  /// Which methods can sign this account in. Metadata; unknown ones dropped.
  final Set<AuthMethod> methods;

  /// The account lifecycle, in the session envelope's own vocabulary.
  /// `pending_setup` is the ordinary value during onboarding.
  final AccountStatus account;

  final TenantLinkStatus link;

  /// Present exactly when [link] is [TenantLinkStatus.linked].
  final LinkedTenant? tenant;

  final AccountSetupStatus setup;

  /// See [normalizeDisplayName] for its origin. A suggestion, never a fact.
  final String? displayNameSuggestion;

  /// When the linked authorization (invitation / seat designation) stops
  /// being completable. Server time; display only.
  final DateTime? authorizationExpiresAt;

  /// Gating fields whose value this build does not know, with the raw value.
  final Map<OnboardingField, String> unsupported;

  bool get hasUnsupportedState => unsupported.isNotEmpty;

  /// Everything the backend needs is done: the server owes a full session.
  bool get isComplete =>
      !hasUnsupportedState &&
      link == TenantLinkStatus.linked &&
      setup == AccountSetupStatus.completed;

  OnboardingSnapshot copyWith({
    AccountStatus? account,
    TenantLinkStatus? link,
    LinkedTenant? tenant,
    bool clearTenant = false,
    AccountSetupStatus? setup,
    String? displayNameSuggestion,
    Set<AuthMethod>? methods,
  }) =>
      OnboardingSnapshot(
        accountId: accountId,
        email: email,
        methods: methods ?? this.methods,
        account: account ?? this.account,
        link: link ?? this.link,
        tenant: clearTenant ? null : (tenant ?? this.tenant),
        setup: setup ?? this.setup,
        displayNameSuggestion:
            displayNameSuggestion ?? this.displayNameSuggestion,
        authorizationExpiresAt: authorizationExpiresAt,
        unsupported: unsupported,
      );

  /// Three outcomes per gating field, exactly as `SessionAccess.fromJson`:
  /// absent → default, known → itself, anything else → [unsupported]. Missing
  /// identity or a structural contradiction throws [FormatException] — that
  /// is an invalid payload, not an unfamiliar one.
  factory OnboardingSnapshot.fromJson(Map<String, dynamic> j) {
    final unsupported = <OnboardingField, String>{};

    T read<T>(
      Map<String, dynamic> source,
      OnboardingField field,
      T fallback,
      T? Function(String) parse, {
      bool required = false,
    }) {
      final raw = source[field.wire];
      if (raw == null) {
        if (required) throw FormatException('${field.wire} is required');
        return fallback;
      }
      if (raw is! String) {
        unsupported[field] = raw.toString();
        return fallback;
      }
      final parsed = parse(raw);
      if (parsed == null) {
        unsupported[field] = raw;
        return fallback;
      }
      return parsed;
    }

    final accountId = j['accountId'];
    final email = j['email'];
    if (accountId is! String || accountId.trim().isEmpty) {
      throw const FormatException('OnboardingSnapshot.accountId');
    }
    if (email is! String || email.trim().isEmpty) {
      throw const FormatException('OnboardingSnapshot.email');
    }

    final account = read(j, OnboardingField.accountStatus,
        AccountStatus.pendingSetup, AccountStatus.tryParse);
    final link = read(j, OnboardingField.linkStatus, TenantLinkStatus.unlinked,
        TenantLinkStatus.tryParse,
        required: true);
    final setup = read(j, OnboardingField.setupStatus,
        AccountSetupStatus.required, AccountSetupStatus.tryParse);

    LinkedTenant? tenant;
    final rawTenant = j['tenant'];
    if (rawTenant != null) {
      if (rawTenant is! Map<String, dynamic>) {
        throw const FormatException('OnboardingSnapshot.tenant');
      }
      final name = rawTenant['displayName'];
      if (name is! String || name.trim().isEmpty) {
        throw const FormatException('OnboardingSnapshot.tenant.displayName');
      }
      final role = read<AuthRole?>(
          rawTenant, OnboardingField.role, null, AuthRole.parse,
          required: true);
      final status = read(rawTenant, OnboardingField.tenantStatus,
          SaasTenantStatus.active, SaasTenantStatus.tryParse,
          required: true);
      if (role != null) {
        tenant = LinkedTenant(displayName: name, role: role, status: status);
      }
    }

    final methods = <AuthMethod>{
      for (final raw in (j['methods'] as List?) ?? const [])
        if (raw is String)
          if (AuthMethod.tryParse(raw) case final method?) method,
    };

    final suggestion = j['displayNameSuggestion'];
    try {
      return OnboardingSnapshot(
        accountId: accountId,
        email: normalizeLoginEmail(email),
        methods: methods,
        account: account,
        link: link,
        tenant: tenant,
        setup: setup,
        displayNameSuggestion: suggestion is String && suggestion.isNotEmpty
            ? normalizeDisplayName(suggestion)
            : null,
        authorizationExpiresAt: parseOnboardingInstant(
            j['authorizationExpiresAt'], 'authorizationExpiresAt'),
        unsupported: unsupported,
      );
    } on ArgumentError catch (e) {
      throw FormatException('OnboardingSnapshot: ${e.message}');
    }
  }

  /// Round-trips; an unsupported value is written back as it arrived so
  /// serialising cannot launder a refused state into an accepted one.
  Map<String, dynamic> toJson() => {
        'accountId': accountId,
        'email': email,
        'methods': [for (final m in methods) m.wire],
        OnboardingField.accountStatus.wire:
            unsupported[OnboardingField.accountStatus] ?? account.wire,
        OnboardingField.linkStatus.wire:
            unsupported[OnboardingField.linkStatus] ?? link.wire,
        OnboardingField.setupStatus.wire:
            unsupported[OnboardingField.setupStatus] ?? setup.wire,
        if (tenant != null)
          'tenant': {
            'displayName': tenant!.displayName,
            OnboardingField.role.wire:
                unsupported[OnboardingField.role] ?? tenant!.role.wire,
            OnboardingField.tenantStatus.wire:
                unsupported[OnboardingField.tenantStatus] ??
                    tenant!.status.wire,
          },
        if (displayNameSuggestion != null)
          'displayNameSuggestion': displayNameSuggestion,
        if (authorizationExpiresAt != null)
          'authorizationExpiresAt': authorizationExpiresAt!.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is OnboardingSnapshot &&
      other.accountId == accountId &&
      other.email == email &&
      setEquals(other.methods, methods) &&
      other.account == account &&
      other.link == link &&
      other.tenant == tenant &&
      other.setup == setup &&
      other.displayNameSuggestion == displayNameSuggestion &&
      other.authorizationExpiresAt == authorizationExpiresAt &&
      mapEquals(other.unsupported, unsupported);

  @override
  int get hashCode => Object.hash(accountId, email, account, link, tenant,
      setup, displayNameSuggestion, authorizationExpiresAt);

  @override
  String toString() => 'OnboardingSnapshot($accountId, ${account.wire}, '
      '${link.wire}, ${setup.wire}, tenant: ${tenant?.status.wire}'
      '${hasUnsupportedState ? ', unsupported: $unsupported' : ''})';
}

// ---------------------------------------------------------------------------
// A → E. What an entry call answers, and what the startup decision reads
// ---------------------------------------------------------------------------

/// What a sign-in, a Google exchange, a verification or a setup completion
/// concluded. Refusals are not outcomes — they are `Failure` results carrying
/// an `OnboardingProblemCode`.
@immutable
sealed class AuthEntryOutcome {
  const AuthEntryOutcome();
}

/// The backend issued a **full session**. The account is verified, linked
/// and set up; the existing `AuthRepository.currentUser` read now answers,
/// and the ordinary startup classifier takes over (role, lifecycle, grant).
final class EntryReady extends AuthEntryOutcome {
  const EntryReady();
}

/// No session. Prove ownership of the address first.
final class EntryVerificationRequired extends AuthEntryOutcome {
  const EntryVerificationRequired(this.challenge);

  final VerificationChallenge challenge;
}

/// A restricted onboarding session exists; this is where the account stands.
final class EntryContinueOnboarding extends AuthEntryOutcome {
  const EntryContinueOnboarding(this.snapshot);

  final OnboardingSnapshot snapshot;
}

/// One line the sign-in screen may show after the journey was closed under
/// the person — so a dead challenge or an ended session is explained rather
/// than silently turning into a blank login form.
enum EntryNotice {
  /// The verification challenge ended (too many attempts, or it expired).
  verificationEnded,

  /// The restricted onboarding session is no longer valid.
  sessionEnded,

  /// Setup completed on another device (or earlier) and this onboarding
  /// session was already exchanged for a full one. Sign in again.
  setupCompletedElsewhere,
}

/// **Machine E's input** — the pre-session state the startup classifier
/// consults whenever there is no full session.
///
/// Holds no secret. The challenge handle and the onboarding token live in
/// secure storage; this is what the app concluded from them.
@immutable
sealed class AuthEntryState {
  const AuthEntryState();

  /// Whether any pre-session identity exists on this device.
  bool get isActive => this is! EntryNone;
}

/// Nothing is in progress. The ordinary sign-in form, when there is no full
/// session either.
final class EntryNone extends AuthEntryState {
  const EntryNone({this.notice});

  final EntryNotice? notice;

  @override
  bool operator ==(Object other) =>
      other is EntryNone && other.notice == notice;

  @override
  int get hashCode => Object.hash(EntryNone, notice);
}

/// The stored challenge/token has not been read yet (a cold start). Holds the
/// loading surface — never the sign-in form, which would flash first.
final class EntryRestoring extends AuthEntryState {
  const EntryRestoring();
}

final class EntryVerificationPending extends AuthEntryState {
  const EntryVerificationPending(this.challenge);

  final VerificationChallenge challenge;

  @override
  bool operator ==(Object other) =>
      other is EntryVerificationPending && other.challenge == challenge;

  @override
  int get hashCode => challenge.hashCode;
}

final class EntryOnboarding extends AuthEntryState {
  const EntryOnboarding(this.snapshot, {this.stale = false});

  final OnboardingSnapshot snapshot;

  /// Served from the last read after a refresh could not reach the server.
  /// Routes the same; the screen shows it read-only and offers no mutation.
  final bool stale;

  @override
  bool operator ==(Object other) =>
      other is EntryOnboarding &&
      other.snapshot == snapshot &&
      other.stale == stale;

  @override
  int get hashCode => Object.hash(snapshot, stale);
}

/// The backend answered with an onboarding payload this client refuses (a
/// structural contradiction). Fails closed onto the invalid-session screen.
final class EntryInvalid extends AuthEntryState {
  const EntryInvalid();
}
