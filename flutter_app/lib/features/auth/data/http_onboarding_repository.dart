import '../../../core/network/api_client.dart';
import '../../../core/network/token_vault.dart';
import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../domain/onboarding_models.dart';
import '../domain/onboarding_repository.dart';
import 'secure_auth_state_store.dart';

/// The pre-session journey against the Leader API (`docs/api/auth.md` §§
/// Identity proof, Onboarding).
///
/// Every credential lands in the shared [TokenVault] — the same secure
/// records `HttpAuthRepository` reads — so a `ready` outcome here is the full
/// session `currentUser()` answers with on its next read.
class HttpOnboardingRepository implements OnboardingRepository {
  HttpOnboardingRepository(
    this._api,
    this._authState, {
    Future<String> Function()? deviceId,
  }) : _deviceId = deviceId;

  final ApiClient _api;
  final AuthStateStore _authState;

  /// This installation's id, sent as `X-Device-Id` on `/auth/google` and the
  /// two email-entry calls only.
  final Future<String> Function()? _deviceId;

  TokenVault get _vault => _api.vault;

  @override
  Future<Result<AuthEntryState>> restore() async {
    final StoredOnboardingState? stored;
    try {
      stored = await _authState.readOnboarding();
    } catch (_) {
      return const Failure('', code: 'server');
    }
    switch (stored) {
      case null:
        return const Success(EntryNone());
      case StoredVerificationState(:final challenge):
        // No endpoint re-reads a challenge; a dead one answers
        // `verification_challenge_ended` on the next verify or resend.
        return Success(EntryVerificationPending(challenge));
      case StoredRestrictedSession(:final cachedSnapshot):
        final outcome = await _api.exchange('GET', '/auth/onboarding');
        switch (outcome) {
          case ApiUnreachable(:final offline):
            return offline
                ? Offline(cached: EntryOnboarding(cachedSnapshot, stale: true))
                : const Failure('', code: 'network');
          case ApiReply(:final ok, :final json):
            if (ok) {
              final snapshot = _snapshotOf(json);
              if (snapshot == null) return const Success(EntryInvalid());
              await _vault.updateOnboardingSnapshot(snapshot);
              return Success(EntryOnboarding(snapshot));
            }
            final code = outcome.code;
            if (code == ProblemCode.authenticationExpired.wire) {
              await _vault.clearOnboarding();
              return const Success(EntryNone(notice: EntryNotice.sessionEnded));
            }
            if (code == OnboardingProblemCode.setupAlreadyCompleted.wire) {
              await _vault.clearOnboarding();
              return const Success(
                EntryNone(notice: EntryNotice.setupCompletedElsewhere),
              );
            }
            return _failure(outcome);
        }
    }
  }

  @override
  Future<Result<VerificationChallenge>> signUpWithPassword({
    required String email,
    required String password,
    required String idempotencyKey,
  }) async {
    final outcome = await _api.exchange('POST', '/auth/sign-up',
        body: {'email': email, 'password': password},
        idempotencyKey: idempotencyKey,
        authenticated: false);
    return _challenge(outcome);
  }

  @override
  Future<Result<AuthEntryOutcome>> signInWithPassword({
    required String email,
    required String password,
  }) async {
    final outcome = await _api.exchange('POST', '/auth/sign-in',
        body: {'email': email, 'password': password}, authenticated: false);
    return _entry(outcome);
  }

  @override
  Future<Result<AuthEntryOutcome>> signInWithGoogle(
    GoogleIdentityAssertion assertion, {
    required String idempotencyKey,
  }) async {
    final outcome = await _api.exchange('POST', '/auth/google',
        body: {'idToken': assertion.idToken},
        idempotencyKey: idempotencyKey,
        authenticated: false,
        headers: await _deviceHeader());
    return _entry(outcome);
  }

  @override
  Future<Result<EmailEntryStatus>> checkEmailStatus(String email) async {
    final outcome = await _api.exchange('POST', '/auth/email-status',
        body: {'email': email},
        authenticated: false,
        headers: await _deviceHeader());
    if (outcome is! ApiReply || !outcome.ok) return _failure(outcome);
    final json = outcome.json;
    final status = json is Map<String, dynamic>
        ? EmailEntryStatus.tryParse(json['status'])
        : null;
    // Fail closed on a status this build does not know.
    if (status == null) return const Failure('', code: 'server');
    return Success(status);
  }

  @override
  Future<Result<VerificationChallenge>> requestSignInCode(String email) async {
    // No Idempotency-Key: the server answers a repeat inside the resend
    // cooldown with the same challenge, so a retry mails nothing new.
    final outcome = await _api.exchange('POST', '/auth/sign-in/code',
        body: {'email': email},
        authenticated: false,
        headers: await _deviceHeader());
    return _challenge(outcome);
  }

  /// The key of the backend's per-device budgets (failed Google sign-ins,
  /// email entry). Never the reason a call fails: without it the server keys
  /// on the IP.
  Future<Map<String, String>?> _deviceHeader() async {
    final read = _deviceId;
    if (read == null) return null;
    try {
      return {'X-Device-Id': await read()};
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Result<AuthEntryOutcome>> verifyEmail({
    required VerificationChallenge challenge,
    required String code,
    required String idempotencyKey,
  }) async {
    final outcome = await _api.exchange('POST', '/auth/verification/verify',
        body: {'challengeId': challenge.handle, 'code': code},
        idempotencyKey: idempotencyKey,
        authenticated: false);
    return _entry(outcome);
  }

  @override
  Future<Result<VerificationChallenge>> resendVerification({
    required VerificationChallenge challenge,
    required String idempotencyKey,
  }) async {
    final outcome = await _api.exchange('POST', '/auth/verification/resend',
        body: {'challengeId': challenge.handle},
        idempotencyKey: idempotencyKey,
        authenticated: false);
    return _challenge(outcome);
  }

  @override
  Future<Result<OnboardingSnapshot>> refresh() async {
    final outcome = await _api.exchange('GET', '/auth/onboarding');
    return _snapshotResult(outcome);
  }

  @override
  Future<Result<OnboardingSnapshot>> linkTeam({
    required String teamCode,
    required String idempotencyKey,
  }) async {
    final outcome = await _api.exchange('POST', '/auth/onboarding/link',
        body: {'teamCode': teamCode}, idempotencyKey: idempotencyKey);
    return _snapshotResult(outcome);
  }

  @override
  Future<Result<AuthEntryOutcome>> completeSetup({
    required String displayName,
    required String idempotencyKey,
  }) async {
    final outcome = await _api.exchange('POST', '/auth/onboarding/complete',
        body: {'displayName': displayName}, idempotencyKey: idempotencyKey);
    return _entry(outcome);
  }

  @override
  Future<Result<void>> abandon() async {
    // Best effort on the server; the device always forgets.
    try {
      final tokens = await _vault.read();
      if (tokens != null && tokens.grade == SessionGrade.onboarding) {
        await _api.exchange('POST', '/auth/sign-out');
      }
    } catch (_) {/* nothing to undo */}
    await _vault.clearOnboarding();
    return const Success(null);
  }

  // -------------------------------------------------------------------------

  /// The server's `sessionId` on an outcome, when it sent a usable one.
  static String? _sessionIdOf(Map<String, dynamic> json) {
    final id = json['sessionId'];
    return id is String && id.isNotEmpty ? id : null;
  }

  /// Decodes the outcome union and installs whatever credential it carries.
  Future<Result<AuthEntryOutcome>> _entry(ApiOutcome outcome) async {
    if (outcome is! ApiReply || !outcome.ok) return _failure(outcome);
    final json = outcome.json;
    if (json is! Map<String, dynamic>) {
      return const Failure('', code: 'server');
    }
    try {
      switch (json['outcome']) {
        case 'ready':
          await _vault.writeFull(
              json['accessToken'] as String, json['refreshToken'] as String,
              sessionId: _sessionIdOf(json));
          return const Success(EntryReady());
        case 'verification_required':
          final challenge = VerificationChallenge.fromJson(
              json['challenge'] as Map<String, dynamic>);
          await _vault.writeVerification(challenge);
          return Success(EntryVerificationRequired(challenge));
        case 'onboarding':
          final snapshot = OnboardingSnapshot.fromJson(
              json['snapshot'] as Map<String, dynamic>);
          await _vault.writeOnboarding(json['onboardingToken'] as String,
              json['onboardingRefreshToken'] as String, snapshot,
              sessionId: _sessionIdOf(json));
          return Success(EntryContinueOnboarding(snapshot));
        default:
          // Fail closed on an outcome this build does not know.
          return const Failure('', code: 'server');
      }
    } catch (_) {
      return const Failure('', code: 'server');
    }
  }

  Future<Result<VerificationChallenge>> _challenge(ApiOutcome outcome) async {
    if (outcome is! ApiReply || !outcome.ok) return _failure(outcome);
    try {
      final challenge =
          VerificationChallenge.fromJson(outcome.json as Map<String, dynamic>);
      await _vault.writeVerification(challenge);
      return Success(challenge);
    } catch (_) {
      return const Failure('', code: 'server');
    }
  }

  Future<Result<OnboardingSnapshot>> _snapshotResult(ApiOutcome outcome) async {
    if (outcome is ApiReply && outcome.ok) {
      final snapshot = _snapshotOf(outcome.json);
      if (snapshot == null) return const Failure('', code: 'server');
      try {
        await _vault.updateOnboardingSnapshot(snapshot);
      } catch (_) {
        return const Failure('', code: 'server');
      }
      return Success(snapshot);
    }
    if (outcome is ApiReply &&
        outcome.code == OnboardingProblemCode.setupAlreadyCompleted.wire) {
      await _vault.clearOnboarding();
    }
    return _failure(outcome);
  }

  static OnboardingSnapshot? _snapshotOf(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    try {
      return OnboardingSnapshot.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// A refusal: the feature's own codes become [OnboardingFailure] with the
  /// throttle/attempt metadata; everything else stays a plain `Failure`.
  static Result<T> _failure<T>(ApiOutcome outcome) {
    switch (outcome) {
      case ApiUnreachable(:final offline):
        return offline ? Offline<T>() : Failure<T>('', code: 'network');
      case ApiReply():
        final code = outcome.code;
        final own = OnboardingProblemCode.parse(code);
        if (own == null) return Failure<T>('', code: code);
        final error = outcome.error;
        final attempts = error['attemptsRemaining'];
        return OnboardingFailure<T>(
          own,
          retryAvailableAt: _retryAt(outcome),
          attemptsRemaining: attempts is int ? attempts : null,
        );
    }
  }

  static DateTime? _retryAt(ApiReply reply) {
    final error = reply.error;
    for (final key in const ['retryAvailableAt', 'resendAvailableAt']) {
      final raw = error[key];
      if (raw is String) {
        final at = DateTime.tryParse(raw);
        if (at != null) return at.toUtc();
      }
    }
    final seconds = error['retryAfterSeconds'] ??
        int.tryParse(reply.headers['retry-after'] ?? '');
    if (seconds is int) {
      return DateTime.now().toUtc().add(Duration(seconds: seconds));
    }
    return null;
  }
}
