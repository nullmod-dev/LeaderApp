import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../../../core/sync/outbox_controller.dart' show newOperationIdProvider;
import '../../../core/time/clock.dart';
import '../../admin_management/data/simple_admin_providers.dart';
import '../../admin_management/domain/simple_admin_models.dart';
import '../domain/auth_models.dart';
import '../domain/onboarding_models.dart';
import '../domain/onboarding_repository.dart';
import 'auth_providers.dart';
import 'mock_auth_repository.dart';
import 'mock_onboarding_repository.dart';

final mockOnboardingServerProvider = Provider<MockOnboardingServer>((ref) {
  return MockOnboardingServer();
});

/// Swap this override in a real build for the network-backed repository.
///
/// The development mock is refused wholesale in a release configuration (the
/// same two gates as `MockAuthRepository`), so a shipping build that forgot
/// the override onboards nobody rather than onboarding against fixtures.
final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  ref.watch(simpleAdminRevisionProvider);
  final now = ref.watch(clockProvider)().toUtc();
  final managedInvitations =
      ref.watch(simpleAdminStoreProvider).invitations.values;
  final issued = managedInvitations
      .where((invitation) =>
          invitation.effectiveStatus(now) ==
          SimpleAdminInvitationStatus.pending)
      .map(
        (invitation) => MockAuthorization(
          id: invitation.id,
          tenantId: invitation.tenantId,
          email: invitation.email,
          role: AuthRole.admin,
          suggestedName: invitation.suggestedName,
          capabilities: invitation.capabilities,
          expiresIn: invitation.expiresAt?.difference(now),
        ),
      )
      .toList(growable: false);
  final excluded = managedInvitations
      .where((invitation) =>
          invitation.effectiveStatus(now) !=
          SimpleAdminInvitationStatus.pending)
      .map((invitation) => invitation.id)
      .toSet();
  final authRepo = ref.watch(authRepositoryProvider);
  // Captured now, not read from `ref` later: the callback runs inside a
  // setup call that can outlive this provider's current build.
  final simpleAdminStore = ref.watch(simpleAdminStoreProvider);
  final simpleAdminRevision = ref.read(simpleAdminRevisionProvider.notifier);
  final clock = ref.watch(clockProvider);
  return MockOnboardingRepository(
    clock: ref.watch(clockProvider),
    server: ref.watch(mockOnboardingServerProvider),
    authState: ref.watch(authStateStoreProvider),
    enabled: ref.watch(demoAccountsEnabledProvider),
    latency: const Duration(milliseconds: 350),
    additionalAuthorizations: issued,
    excludedAuthorizationIds: excluded,
    // The mock's half of "one secure token vault" — see
    // `OnboardingSessionIssued`. Absent for a non-mock `AuthRepository`
    // override, which owns its own full-session issuance.
    sessionIssued: authRepo is MockAuthRepository
        ? authRepo.installOnboardedSession
        : null,
    // Point 18B — the invitation is consumed in the setup transaction itself.
    authorizationConsumed: (authorization,
        {required accountId, required displayName}) {
      if (authorization.role != AuthRole.admin) return;
      final changed = simpleAdminStore.acceptInvitation(
        invitationId: authorization.id,
        accountId: accountId,
        displayName: displayName,
        now: clock().toUtc(),
      );
      if (changed) simpleAdminRevision.changed();
    },
  );
});

/// The pre-session state, as the startup classifier reads it.
///
/// A plain view of [onboardingControllerProvider] so nothing but the
/// controller can write it.
final authEntryStateProvider = Provider<AuthEntryState>((ref) {
  return ref.watch(onboardingControllerProvider);
});

final onboardingControllerProvider =
    NotifierProvider<OnboardingController, AuthEntryState>(
  OnboardingController.new,
);

/// The operations the controller single-flights and keys.
enum OnboardingOperation {
  restore,
  signUp,
  signIn,
  google,
  verify,
  resend,
  refresh,
  link,
  setup,
}

/// The single owner of the pre-session journey (machines A–D feeding E).
///
/// **What it guarantees, so 17B's screens do not have to:**
///
/// - **One request per gesture.** A second call of the same operation while
///   one is in flight gets the *same* future — a double tap cannot send two.
/// - **Idempotency keys.** Each mutation carries a key that is reused while
///   the same inputs are retried after a transport failure, and replaced as
///   soon as a definitive answer arrives or the inputs change. Repeated taps
///   and network retries therefore cannot create a second account, challenge
///   or link; the backend owns the final conflict resolution.
/// - **Local courtesy checks first.** A malformed email, code or Team Code is
///   refused before any request, so a typo spends no server-side attempt.
/// - **Refresh, never invent.** A refusal that means "the state moved under
///   you" (`OnboardingProblemCode.requiresRefresh`) re-reads the
///   authoritative snapshot before returning, and the classifier routes from
///   that.
/// - **Online-only.** Offline returns `Offline` and changes nothing; nothing
///   is queued, retried later or written to the outbox.
/// - **No secret in state.** Passwords, codes and Team Codes are arguments
///   only. The one value kept — the challenge — is the backend's handle, and
///   the state's `toString` never prints it.
///
/// Its state is [AuthEntryState]; the classifier consults it whenever there
/// is no full session. **Point 17A: nothing in the UI calls it yet.** The
/// state starts at [EntryNone] and 17B wires [restore] into startup.
class OnboardingController extends Notifier<AuthEntryState> {
  @override
  AuthEntryState build() => const EntryNone();

  OnboardingRepository get _repo => ref.read(onboardingRepositoryProvider);

  final Map<OnboardingOperation, Future<Result<Object?>>> _inFlight = {};
  final Map<OnboardingOperation, ({int inputs, String key})> _keys = {};

  Future<Result<T>> _once<T>(
    OnboardingOperation op,
    Future<Result<T>> Function() run,
  ) {
    final pending = _inFlight[op];
    if (pending != null) return pending.then((r) => r as Result<T>);
    // A block body on purpose: `remove` returns the removed future, and
    // `whenComplete` would await it — the future would wait for itself.
    final future = run().whenComplete(() {
      _inFlight.remove(op);
    });
    _inFlight[op] = future;
    return future;
  }

  /// The key for this attempt. [inputs] is an in-memory hash of the request
  /// — never stored beyond this controller and never logged.
  String _keyFor(OnboardingOperation op, List<Object?> inputs) {
    final hash = Object.hashAll(inputs);
    final held = _keys[op];
    if (held != null && held.inputs == hash) return held.key;
    final key = ref.read(newOperationIdProvider)();
    _keys[op] = (inputs: hash, key: key);
    return key;
  }

  /// Drops the key once the server has answered definitively; keeps it for a
  /// transport failure so the retry replays instead of duplicating.
  void _settleKey(OnboardingOperation op, Result<Object?> result) {
    final transport = result.when(
      success: (_, {stale = false}) => false,
      failure: (_, code) => switch (ProblemCode.parse(code)) {
        ProblemCode.network || ProblemCode.server => true,
        _ => code == null,
      },
      offline: (_) => true,
    );
    if (!transport) _keys.remove(op);
  }

  static bool _isCode(Result<Object?> r, OnboardingProblemCode code) =>
      r is OnboardingFailure && r.problem == code;

  static bool _isGlobal(Result<Object?> r, ProblemCode code) =>
      r is Failure && ProblemCode.parse(r.code) == code;

  /// Applies an entry outcome to the state. The only writer of a transition.
  void _apply(AuthEntryOutcome outcome) {
    switch (outcome) {
      case EntryReady():
        state = const EntryNone();
        // A full session now exists: the base read, not the derived one.
        ref.invalidate(currentUserResultProvider);
      case EntryVerificationRequired(:final challenge):
        state = EntryVerificationPending(challenge);
      case EntryContinueOnboarding(:final snapshot):
        state = EntryOnboarding(snapshot);
    }
  }

  /// Applies what every call's refusal implies for the journey as a whole.
  Future<void> _react(Result<Object?> result) async {
    if (_isGlobal(result, ProblemCode.authenticationExpired) ||
        _isCode(result, OnboardingProblemCode.onboardingRequired)) {
      _keys.clear();
      state = const EntryNone(notice: EntryNotice.sessionEnded);
    } else if (_isCode(
        result, OnboardingProblemCode.verificationChallengeEnded)) {
      _keys.clear();
      state = const EntryNone(notice: EntryNotice.verificationEnded);
    } else if (_isCode(result, OnboardingProblemCode.setupAlreadyCompleted)) {
      _keys.clear();
      state = const EntryNone(notice: EntryNotice.setupCompletedElsewhere);
    } else if (result is OnboardingFailure &&
        result.problem.requiresRefresh &&
        state is EntryOnboarding) {
      await refresh();
    }
  }

  Future<Result<T>> _entry<T>(
    OnboardingOperation op,
    Future<Result<T>> Function() call, {
    void Function(T value)? onSuccess,
  }) =>
      _once(op, () async {
        final result = await call();
        _settleKey(op, result);
        if (result case Success(:final data)) {
          onSuccess?.call(data);
        } else {
          await _react(result);
        }
        return result;
      });

  // -------------------------------------------------------------------------

  /// Hydrates from the device vault. 17B calls this at startup; until it
  /// lands the state is [EntryRestoring], which holds the loading surface.
  Future<Result<AuthEntryState>> restore() => _once(
        OnboardingOperation.restore,
        () async {
          state = const EntryRestoring();
          final result = await _repo.restore();
          state = result.when(
            success: (value, {stale = false}) => value,
            failure: (_, __) => const EntryNone(),
            // Offline with a kept snapshot still routes to the right step,
            // read-only; with nothing kept there is no journey to resume.
            offline: (cached) => cached ?? const EntryNone(),
          );
          return result;
        },
      );

  Future<Result<VerificationChallenge>> signUpWithPassword({
    required String email,
    required String password,
  }) {
    if (validateLoginEmail(email) != null) {
      return Future.value(const Failure('', code: 'validation'));
    }
    final e = normalizeLoginEmail(email);
    return _entry(
      OnboardingOperation.signUp,
      () => _repo.signUpWithPassword(
        email: e,
        password: password,
        idempotencyKey: _keyFor(OnboardingOperation.signUp, [e, password]),
      ),
      onSuccess: (challenge) => state = EntryVerificationPending(challenge),
    );
  }

  Future<Result<AuthEntryOutcome>> signInWithPassword({
    required String email,
    required String password,
  }) {
    if (validateLoginEmail(email) != null || password.isEmpty) {
      return Future.value(const Failure('', code: 'validation'));
    }
    return _entry(
      OnboardingOperation.signIn,
      () => _repo.signInWithPassword(
          email: normalizeLoginEmail(email), password: password),
      onSuccess: _apply,
    );
  }

  Future<Result<AuthEntryOutcome>> signInWithGoogle(
    GoogleIdentityAssertion assertion,
  ) =>
      _entry(
        OnboardingOperation.google,
        () => _repo.signInWithGoogle(
          assertion,
          idempotencyKey:
              _keyFor(OnboardingOperation.google, [assertion.idToken]),
        ),
        onSuccess: _apply,
      );

  Future<Result<AuthEntryOutcome>> verifyEmail(String code) {
    final current = state;
    if (current is! EntryVerificationPending) {
      return Future.value(const Failure('', code: 'validation'));
    }
    final challenge = current.challenge;
    if (validateVerificationCode(code, length: challenge.codeLength) != null) {
      return Future.value(const Failure('', code: 'validation'));
    }
    final normalized = normalizeVerificationCode(code);
    return _entry(
      OnboardingOperation.verify,
      () => _repo.verifyEmail(
        challenge: challenge,
        code: normalized,
        idempotencyKey:
            _keyFor(OnboardingOperation.verify, [challenge.handle, normalized]),
      ),
      onSuccess: _apply,
    ).then((result) {
      // A wrong code narrows the attempts the screen shows; the challenge is
      // otherwise unchanged.
      if (result case OnboardingFailure(:final attemptsRemaining?)
          when state is EntryVerificationPending) {
        state = EntryVerificationPending(
            challenge.copyWith(attemptsRemaining: attemptsRemaining));
      }
      return result;
    });
  }

  Future<Result<VerificationChallenge>> resendVerification() {
    final current = state;
    if (current is! EntryVerificationPending) {
      return Future.value(const Failure('', code: 'validation'));
    }
    final challenge = current.challenge;
    return _entry(
      OnboardingOperation.resend,
      () => _repo.resendVerification(
        challenge: challenge,
        idempotencyKey: _keyFor(OnboardingOperation.resend,
            [challenge.handle, challenge.resendAvailableAt]),
      ),
      onSuccess: (updated) => state = EntryVerificationPending(updated),
    );
  }

  /// Re-reads the authoritative snapshot — the answer to every race (another
  /// device verified, linked, finished setup; the account or tenant was
  /// suspended; an invitation was withdrawn). Offline keeps the last snapshot
  /// and marks it stale.
  Future<Result<OnboardingSnapshot>> refresh() => _once(
        OnboardingOperation.refresh,
        () async {
          final result = await _repo.refresh();
          switch (result) {
            case Success(:final data):
              state = EntryOnboarding(data);
            case Offline():
              if (state case EntryOnboarding(:final snapshot)) {
                state = EntryOnboarding(snapshot, stale: true);
              }
            case Failure():
              await _react(result);
          }
          return result;
        },
      );

  Future<Result<OnboardingSnapshot>> linkTeam(String teamCode) {
    if (validateTeamCodeInput(teamCode) != null) {
      return Future.value(const OnboardingFailure<OnboardingSnapshot>(
          OnboardingProblemCode.teamCodeMalformed));
    }
    final canonical = normalizeTeamCodeInput(teamCode);
    return _entry(
      OnboardingOperation.link,
      () => _repo.linkTeam(
        teamCode: canonical,
        idempotencyKey: _keyFor(OnboardingOperation.link, [canonical]),
      ),
      onSuccess: (snapshot) => state = EntryOnboarding(snapshot),
    );
  }

  Future<Result<AuthEntryOutcome>> completeSetup({
    required String displayName,
  }) {
    if (validateDisplayName(displayName) != null) {
      return Future.value(const Failure('', code: 'validation'));
    }
    final name = normalizeDisplayName(displayName);
    return _entry(
      OnboardingOperation.setup,
      () => _repo.completeSetup(
        displayName: name,
        idempotencyKey: _keyFor(OnboardingOperation.setup, [name]),
      ),
      onSuccess: _apply,
    );
  }

  /// Leaves the journey on this device. Always clears local state — a
  /// restricted identity grants nothing, and discarding it is the safe
  /// direction even when the server-side revoke cannot be confirmed.
  Future<Result<void>> abandon() async {
    final result = await _repo.abandon();
    _keys.clear();
    state = const EntryNone();
    return result;
  }
}
