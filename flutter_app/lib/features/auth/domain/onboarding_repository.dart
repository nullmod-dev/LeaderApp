/// Point 17A — the onboarding repository seam and its error taxonomy.
///
/// **Two repositories, split by trust stage, not by screen.**
///
/// - `AuthRepository` (existing) owns the **full session**: the account read
///   (`currentUser`), sign-out, MFA, the password-reset flow and the session
///   list. Unchanged by 17A.
/// - [OnboardingRepository] owns every trust transition **before** a full
///   session exists: sign-up, credential and Google entry, email
///   verification, the Team Code link, setup completion, and the restricted
///   onboarding session they run on.
///
/// Both read the same token vault in a real build (secure storage): a full
/// session and an onboarding session are never held at once, and the backend
/// decides which one a credential produces.
///
/// **Online-only, every method.** No trust transition is queued, retried in
/// the background or written to the operational outbox. Offline answers
/// `Offline`, and the caller shows an unavailable state.
library;

import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import 'onboarding_models.dart';

/// Feature-owned problem codes for the onboarding journey. Branch on these,
/// never on message text; the global codes (`validation`,
/// `authentication_expired`, `server`, `network`, `offline`) stay in
/// [ProblemCode].
///
/// **Deliberately absent: "account exists".** Sign-up never tells anyone that
/// an address is registered (see the enumeration policy in `API_CONTRACT.md`),
/// so there is no code for a client to render it with.
enum OnboardingProblemCode {
  /// Wrong address or password, no such account, or an account with no
  /// password method — one code for all three, on purpose.
  invalidCredentials('invalid_credentials'),

  /// The backend's password policy refused the password.
  passwordRejected('password_rejected'),

  /// Wrong code. `attemptsRemaining` may accompany it.
  verificationCodeInvalid('verification_code_invalid'),

  /// The current code expired; a resend issues a new one on the same
  /// challenge.
  verificationCodeExpired('verification_code_expired'),

  /// The challenge itself is over (attempts exhausted, lifetime ended, or an
  /// unknown handle). Start again from sign-in or sign-up.
  verificationChallengeEnded('verification_challenge_ended'),

  /// A resend came before the cooldown ended. `retryAvailableAt` accompanies.
  verificationResendThrottled('verification_resend_throttled'),

  /// The Google token could not be verified by the backend (expired, wrong
  /// audience, revoked). Try Google again.
  googleAssertionRejected('google_assertion_rejected'),

  /// The address Google verified already belongs to an MTM account that
  /// signs in with a password. The backend does **not** merge automatically:
  /// sign in with the password. Safe to say specifically — the person has
  /// just proved they own the address.
  authMethodLinkRequired('auth_method_link_required'),

  /// The backend has this method switched off (or does not know it).
  unsupportedAuthMethod('unsupported_auth_method'),

  /// Refused locally before any request: not shaped like a Team Code.
  teamCodeMalformed('team_code_malformed'),

  /// **One code for every "no"** a person without a matching authorization
  /// could receive: unknown code, retired/disabled code, or no invitation or
  /// seat for this verified address in that tenant. So a guessed code is
  /// never distinguishable from a real one without an invitation.
  teamLinkRefused('team_link_refused'),

  /// The code and this address matched an authorization, and the
  /// authorization has expired. Only ever said to the invitee.
  invitationExpired('invitation_expired'),

  /// This account is already linked to a different tenant (one account, one
  /// tenant). The other tenant is never named.
  accountAlreadyLinked('account_already_linked'),

  /// Matched, but the tenant is suspended or deletion pending: nothing that
  /// opens access completes while it is not active (Point 9/14 rule).
  tenantUnavailable('tenant_unavailable'),

  /// Setup cannot run: the account is not linked, or its authorization was
  /// withdrawn underneath it. Refresh and follow the new state.
  setupUnavailable('setup_unavailable'),

  /// This onboarding session was already exchanged for a full session. Sign
  /// in again.
  setupAlreadyCompleted('setup_already_completed'),

  /// The account was suspended or revoked mid-journey. Refresh.
  accountUnavailable('account_unavailable'),

  /// A full-session endpoint was called with an onboarding session. The
  /// backend's enforcement of the restricted scope, seen from the client.
  onboardingRequired('onboarding_required'),

  /// Throttled (sign-in, sign-up, Team Code). `retryAvailableAt` may
  /// accompany it.
  rateLimited('rate_limited'),

  idempotencyConflict('idempotency_conflict');

  const OnboardingProblemCode(this.wire);

  final String wire;

  static OnboardingProblemCode? parse(String? wire) {
    for (final code in values) {
      if (code.wire == wire) return code;
    }
    return null;
  }

  /// Whether the answer means "the state moved under you": the caller must
  /// re-read the authoritative snapshot rather than invent a recovery.
  bool get requiresRefresh => switch (this) {
        accountAlreadyLinked ||
        tenantUnavailable ||
        setupUnavailable ||
        accountUnavailable ||
        invitationExpired =>
          true,
        _ => false,
      };
}

/// A `Failure` that can also carry the throttle and attempt metadata a
/// backend attaches to an onboarding refusal.
///
/// A subclass rather than a new result type, so every existing `Result`
/// consumer (`when`, `problemOrNull`) keeps working unchanged. The message is
/// diagnostic only and **must never echo an input** — no code, no Team Code,
/// no password, no token.
///
/// Global refusals (`validation`, `authentication_expired`, …) stay plain
/// `Failure`s with the global code.
class OnboardingFailure<T> extends Failure<T> {
  const OnboardingFailure(
    this.problem, {
    String message = '',
    this.retryAvailableAt,
    this.attemptsRemaining,
  }) : super(message);

  final OnboardingProblemCode problem;

  /// Server instant after which a retry will be accepted (converted from a
  /// `Retry-After` at receipt). Display only.
  final DateTime? retryAvailableAt;

  final int? attemptsRemaining;

  /// The wire code, so every `Result.when` consumer sees it as usual.
  @override
  String get code => problem.wire;

  /// The code and the metadata — never the message, which is server text.
  @override
  String toString() => 'OnboardingFailure(${problem.wire}'
      '${retryAvailableAt == null ? '' : ', retry: $retryAvailableAt'}'
      '${attemptsRemaining == null ? '' : ', attempts: $attemptsRemaining'})';
}

/// The user-facing categories 17B maps to Arabic copy. **Presentation never
/// sees a wire code** — it sees one of these.
///
/// Verification-required and setup-required are not here: they are states
/// ([AuthEntryState]), routed by the startup classifier, not errors.
enum OnboardingErrorKind {
  invalidCredentials,
  passwordRejected,
  invalidInput,
  verificationCodeInvalid,
  verificationCodeExpired,
  verificationEnded,
  resendThrottled,
  googleRetry,

  /// Google identity cannot be offered by **this build on this device** —
  /// the provider is not configured, or the platform has no account chooser
  /// to show. Distinct from [googleRetry], which means the attempt itself
  /// failed: "try again" is the wrong instruction when trying again cannot
  /// work, and it is the sentence that sends a person round the same loop.
  googleUnavailable,
  methodLinkRequired,
  unsupportedMethod,
  teamCodeMalformed,
  teamCodeRejected,
  invitationExpired,
  accountAlreadyLinked,
  tenantUnavailable,
  setupUnavailable,
  setupAlreadyCompleted,
  accountUnavailable,
  sessionEnded,
  rateLimited,
  offline,
  temporaryFailure,
  unknown;

  /// Whether the same action may simply be tried again as-is.
  bool get retryable => switch (this) {
        offline || temporaryFailure || googleRetry => true,
        _ => false,
      };
}

/// The one mapping from a result to a category. `null` for a success.
///
/// An unknown wire code is [OnboardingErrorKind.unknown] — rendered with the
/// generic sentence, never with the raw code.
OnboardingErrorKind? onboardingErrorKindOf(Result<Object?> result) {
  if (result is Success) return null;
  if (result is Offline) return OnboardingErrorKind.offline;
  final code = (result as Failure).code;
  final own = result is OnboardingFailure
      ? result.problem
      : OnboardingProblemCode.parse(code);
  if (own != null) {
    return switch (own) {
      OnboardingProblemCode.invalidCredentials =>
        OnboardingErrorKind.invalidCredentials,
      OnboardingProblemCode.passwordRejected =>
        OnboardingErrorKind.passwordRejected,
      OnboardingProblemCode.verificationCodeInvalid =>
        OnboardingErrorKind.verificationCodeInvalid,
      OnboardingProblemCode.verificationCodeExpired =>
        OnboardingErrorKind.verificationCodeExpired,
      OnboardingProblemCode.verificationChallengeEnded =>
        OnboardingErrorKind.verificationEnded,
      OnboardingProblemCode.verificationResendThrottled =>
        OnboardingErrorKind.resendThrottled,
      OnboardingProblemCode.googleAssertionRejected =>
        OnboardingErrorKind.googleRetry,
      OnboardingProblemCode.authMethodLinkRequired =>
        OnboardingErrorKind.methodLinkRequired,
      OnboardingProblemCode.unsupportedAuthMethod =>
        OnboardingErrorKind.unsupportedMethod,
      OnboardingProblemCode.teamCodeMalformed =>
        OnboardingErrorKind.teamCodeMalformed,
      OnboardingProblemCode.teamLinkRefused =>
        OnboardingErrorKind.teamCodeRejected,
      OnboardingProblemCode.invitationExpired =>
        OnboardingErrorKind.invitationExpired,
      OnboardingProblemCode.accountAlreadyLinked =>
        OnboardingErrorKind.accountAlreadyLinked,
      OnboardingProblemCode.tenantUnavailable =>
        OnboardingErrorKind.tenantUnavailable,
      OnboardingProblemCode.setupUnavailable =>
        OnboardingErrorKind.setupUnavailable,
      OnboardingProblemCode.setupAlreadyCompleted =>
        OnboardingErrorKind.setupAlreadyCompleted,
      OnboardingProblemCode.accountUnavailable =>
        OnboardingErrorKind.accountUnavailable,
      OnboardingProblemCode.onboardingRequired =>
        OnboardingErrorKind.sessionEnded,
      OnboardingProblemCode.rateLimited => OnboardingErrorKind.rateLimited,
      // The same key with a different body is a client bug, not a user
      // situation; the generic sentence is the honest one.
      OnboardingProblemCode.idempotencyConflict => OnboardingErrorKind.unknown,
    };
  }
  return switch (ProblemCode.parse(code)) {
    ProblemCode.validation => OnboardingErrorKind.invalidInput,
    ProblemCode.authenticationExpired => OnboardingErrorKind.sessionEnded,
    ProblemCode.offline => OnboardingErrorKind.offline,
    ProblemCode.network ||
    ProblemCode.server =>
      OnboardingErrorKind.temporaryFailure,
    _ => OnboardingErrorKind.unknown,
  };
}

/// The typed seam. Every method is online-only and returns a [Result]; every
/// mutation carries an `Idempotency-Key` so a repeated tap or a network retry
/// can never create a second account, a second challenge or a second link.
///
/// Nothing here takes a role, a tenant id or a capability: the backend derives
/// all three from provisioning and invitations. There is no parameter through
/// which a client could ask for them.
abstract class OnboardingRepository {
  /// Reads what this device holds — a pending challenge (no network needed)
  /// or an onboarding session (re-read from the backend). [EntryNone] when
  /// neither. `Offline` carries the last snapshot when one was kept.
  Future<Result<AuthEntryState>> restore();

  /// Creates an account (or, for an already-registered address, silently
  /// does not) and answers **the same way in both cases**: a challenge for
  /// the address. No session is issued by sign-up.
  Future<Result<VerificationChallenge>> signUpWithPassword({
    required String email,
    required String password,
    required String idempotencyKey,
  });

  Future<Result<AuthEntryOutcome>> signInWithPassword({
    required String email,
    required String password,
  });

  /// Exchanges a Google assertion. The backend maps it to the canonical
  /// account; the client merges nothing.
  Future<Result<AuthEntryOutcome>> signInWithGoogle(
    GoogleIdentityAssertion assertion, {
    required String idempotencyKey,
  });

  Future<Result<AuthEntryOutcome>> verifyEmail({
    required VerificationChallenge challenge,
    required String code,
    required String idempotencyKey,
  });

  /// A new code on the same challenge; answers the refreshed challenge
  /// (new expiry, new cooldown).
  Future<Result<VerificationChallenge>> resendVerification({
    required VerificationChallenge challenge,
    required String idempotencyKey,
  });

  /// Re-reads the authoritative snapshot under the onboarding session.
  Future<Result<OnboardingSnapshot>> refresh();

  /// Presents a Team Code. The backend resolves the tenant, matches this
  /// verified address to an authorization in it, and links — or refuses.
  /// [teamCode] is sent once in canonical form and kept nowhere.
  Future<Result<OnboardingSnapshot>> linkTeam({
    required String teamCode,
    required String idempotencyKey,
  });

  /// Confirms the display name and accepts the linked role. On success the
  /// backend activates the account (running the Main Admin seat transition
  /// where the authorization is a seat) and issues the full session.
  Future<Result<AuthEntryOutcome>> completeSetup({
    required String displayName,
    required String idempotencyKey,
  });

  /// Ends the pre-session journey on this device: discards the challenge
  /// handle and revokes the onboarding session. Best effort on the server;
  /// always clears locally.
  Future<Result<void>> abandon();
}
