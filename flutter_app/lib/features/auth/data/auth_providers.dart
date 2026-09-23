import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/build_mode.dart';
import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/storage/secure_store.dart';
import '../../demo/data/demo_control_plane.dart';
import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';
import '../domain/demo_session_store.dart';
import '../domain/session_access.dart';
import 'mock_auth_repository.dart';
import 'persistent_demo_session_store.dart';
import 'secure_auth_state_store.dart';

/// Whether this *configuration* offers the development demo accounts.
///
/// The inner half of the release gate. It defaults to [demoAccountsAllowed],
/// the compile-time constant that is `false` in any shipping artefact, so in
/// production this is `false` and cannot be anything else — every demo entry
/// point checks the constant as well, which is what makes the code physically
/// absent rather than merely switched off.
///
/// It exists as a provider so a **test** can simulate a release configuration
/// while running under the debug VM: override it to `false` and typed dev
/// authentication plus stored-persona restore stop working, which is exactly
/// what a release build does. Overriding it to
/// `true` in a release build would still change nothing.
final demoAccountsEnabledProvider = Provider<bool>((ref) {
  return demoAccountsAllowed;
});

/// The durable local key/value store — the app's one persistence mechanism.
///
/// Overridden in tests with `InMemoryLocalStore`, which is also how an app
/// relaunch is modelled: a second `ProviderContainer` over the **same** store
/// object is a new process reading the same device state.
final localStoreProvider = Provider<LocalStore>((ref) {
  return SharedPreferencesLocalStore();
});

/// The one platform keystore/keychain used by both pre-session onboarding and
/// the existing full-session repository. It is deliberately not a
/// `LocalStore`: auth credentials must never enter ordinary preferences.
final secureStoreProvider = Provider<SecureStore>((ref) {
  return PlatformSecureStore();
});

final authStateStoreProvider = Provider<AuthStateStore>((ref) {
  return SecureAuthStateStore(ref.watch(secureStoreProvider));
});

/// Development backend state. A process-kill test overrides this with one
/// shared instance while rebuilding every client repository/provider.
final mockAuthSessionServerProvider = Provider<MockAuthSessionServer>((ref) {
  return MockAuthSessionServer();
});

/// Persists which demo persona a development session selected, so it survives
/// a real process restart. Development-only; see
/// `domain/demo_session_store.dart`.
///
/// **The release gate is here, at the wiring**, not only downstream. A
/// shipping configuration is handed [NoDemoSessionStore], which reads nothing
/// and writes nothing, so a persona record left on the device by a debug build
/// is never even loaded — there is no value for anything to ignore. The two
/// checks inside `MockAuthRepository` and `DemoSignInController` remain: this
/// is the outermost of three, not a replacement for them.
final demoSessionStoreProvider = Provider<DemoSessionStore>((ref) {
  if (!demoAccountsAllowed || !ref.watch(demoAccountsEnabledProvider)) {
    return const NoDemoSessionStore();
  }
  return PersistentDemoSessionStore(ref.watch(localStoreProvider));
});

/// Swap this override in a real build to plug in a network-backed repo.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return MockAuthRepository(
    demoSessions: ref.watch(demoSessionStoreProvider),
    authState: ref.watch(authStateStoreProvider),
    sessionServer: ref.watch(mockAuthSessionServerProvider),
    demoAccountsEnabled: ref.watch(demoAccountsEnabledProvider),
  );
});

/// The session exactly as the repository reported it.
///
/// This is the base; [currentUserProvider] is the collapsed view of it. The
/// distinction matters in two places and nowhere else: the account screen and
/// the router's auth gate need to tell "no session" from "the session
/// expired" from "we are offline with no cached copy", and collapsing all
/// three to `null` throws that away. Every capability check only ever needed
/// the collapsed form, so that stays the provider the rest of the app reads.
///
/// Invalidate **this** one to force a re-read of the session — invalidating
/// the derived provider alone re-awaits this cached future and gets the same
/// answer back.
final currentUserResultProvider =
    FutureProvider<Result<AuthUser?>>((ref) async {
  return ref.read(authRepositoryProvider).currentUser();
});

/// The signed-in account, or `null`.
///
/// Failure and offline-without-cache both read as "no account" here, which is
/// the correct answer for a capability check: deny. A screen that has to
/// explain *why* there is no account reads [currentUserResultProvider].
final currentUserProvider = FutureProvider<AuthUser?>((ref) async {
  final r = await ref.watch(currentUserResultProvider.future);
  final user = r.when(
    success: (data, {stale = false}) => data,
    failure: (_, __) => null,
    offline: (cached) => cached,
  );
  return _accepted(user);
});

/// The authenticated account's product surface, or `null` when there is none.
///
/// **Classification only** — no control anywhere may open because of what this
/// returns; see [AuthRole].
///
/// The router no longer reads it. Since Point 3 the surface decision belongs
/// to `startupDestinationProvider`, which reads the account itself, so this is
/// the convenience view for anything that wants the role on its own — a
/// screen labelling the account type, or a test asserting a payload was
/// refused. Nothing may grow a second routing rule on it.
final authRoleProvider = Provider<AuthRole?>((ref) {
  return ref.watch(currentUserProvider).valueOrNull?.role;
});

/// The one place an account payload is accepted or refused.
///
/// An `AuthUser` whose [AuthRole] and `saasTenantId` disagree is invalid
/// authentication data — an outside-tenant role carrying a tenant id, or a
/// `main_admin`/`admin` carrying none. It is **not repaired**: nothing here
/// strips the stray id or invents the missing one, because either would turn
/// a server bug into a session quietly scoped to the wrong customer, which is
/// the one failure mode a tenant boundary cannot survive.
///
/// It is refused instead, and the app reads as having no session: capability
/// checks resolve to `Capabilities.none` and the router's auth gate sends the
/// user to the login screen. Failing closed is the only safe direction — an
/// account this client cannot classify must not be handed a surface.
///
/// Not an `assert`: the refusal has to hold in a release build too, and a
/// debug-only crash would hide the very path the tests exercise.
AuthUser? _accepted(AuthUser? user) =>
    user != null && user.isWellFormed ? user : null;

/// What the router may conclude about the session.
///
/// TODO(security): a UX gate, like every other client-side access decision in
/// this app — see the contract at the top of `core/access/capability.dart`.
/// It keeps a signed-out person off a screen that would fail; the backend
/// rejects the request regardless.
enum AuthGate {
  /// The session read is **in flight**. Nothing is known yet, and a cold start
  /// spends its first frames here.
  ///
  /// Split out of [unknown] by Point 3, because the two need opposite
  /// treatments and sharing one value forced a single wrong answer. This one
  /// is "wait" — the startup classifier holds the app on its loading surface,
  /// which is what stops a protected screen rendering before the guard
  /// decision exists.
  restoring,

  /// The read **answered**, and the answer is not evidence of anything: an
  /// offline device with no cached account, or a transport error. **Never
  /// redirects**, and never bounces anyone to the login screen — an app that
  /// signed a field user out because the network was down would be broken for
  /// exactly the conditions it is built for.
  unknown,

  signedIn,

  /// The repository answered, definitively, that there is no session.
  signedOut,

  /// There was a session and it is no longer valid — `authentication_expired`.
  /// Distinct from [signedOut] because it lands on its own screen.
  expired,

  /// An account arrived and this client refuses it: [AuthUser.isWellFormed]
  /// failed, so the role and the tenant id disagree.
  ///
  /// Also split out by Point 3. It used to read as [signedOut], which sent the
  /// person to a login form that would hand back the same broken payload; it
  /// now fails closed onto a screen that says the account data is invalid.
  /// Nothing downstream ever sees the refused account — `currentUserProvider`
  /// still answers `null`, so every capability check still denies.
  invalid;

  /// Whether the gate has yet to reach a usable conclusion.
  ///
  /// The one question every capability route guard asks: while this is true a
  /// guard decides **nothing**, because the grant has not landed and bouncing
  /// a legitimate deep link to `/home` would break every cold start and every
  /// offline relaunch.
  bool get isUnresolved =>
      this == AuthGate.restoring || this == AuthGate.unknown;
}

final authGateProvider = Provider<AuthGate>((ref) {
  final async = ref.watch(currentUserResultProvider);
  final result = async.valueOrNull;
  if (result == null) {
    // No answer yet. Still reading is `restoring`; a read that *threw* is not
    // evidence about the session, so it reads as unresolved rather than as a
    // sign-out.
    return async.isLoading ? AuthGate.restoring : AuthGate.unknown;
  }
  return result.when(
    success: (user, {stale = false}) => switch (user) {
      null => AuthGate.signedOut,
      final u when !u.isWellFormed => AuthGate.invalid,
      _ => AuthGate.signedIn,
    },
    failure: (_, code) =>
        ProblemCode.parse(code) == ProblemCode.authenticationExpired
            ? AuthGate.expired
            : AuthGate.unknown,
    // A cached account is still an account: offline-first means the app keeps
    // working from what it already has.
    offline: (cached) => switch (cached) {
      null => AuthGate.unknown,
      final u when !u.isWellFormed => AuthGate.invalid,
      _ => AuthGate.signedIn,
    },
  );
});

/// What the server says about this account's and this customer's lifecycle,
/// and whether the session is a customer demo.
///
/// **PROVISIONAL — the seam, and nothing behind it yet.** No repository in
/// this build supplies any of it, so this is [SessionAccess.normal] for every
/// real session. It is a provider rather than a field on `AuthUser` so that a
/// real implementation overrides exactly one thing, and so the development
/// state inspector and the classifier tests can drive every state screen
/// without inventing a backend fact anywhere else.
///
/// See `features/auth/domain/session_access.dart` and `API_CONTRACT.md`.
final sessionAccessProvider = Provider<SessionAccess>((ref) {
  final override = ref.watch(sessionAccessOverrideProvider);
  if (override != null) return override;
  // Rebuild after a sign-in/session refresh. The development mock holds the
  // sibling envelope so its isolated customer-demo session is observable by
  // the same startup classifier a production response uses.
  ref.watch(currentUserResultProvider);
  final repository = ref.watch(authRepositoryProvider);
  final access = repository is MockAuthRepository
      ? repository.currentSessionAccess
      : SessionAccess.normal;
  // The demo **window** is control-plane state, not session state: a trial
  // ends because its 24 hours ran out or because a Super Admin ended it, and
  // neither of those is something the session that started it can know. In
  // production the backend refuses the next request and the envelope arrives
  // saying `expired`; here the control plane supplies the same verdict, so the
  // startup classifier reaches `/demo-expired` by exactly one path in both
  // builds. Only an *active* demo is re-examined — nothing else is touched.
  if (access.demo != DemoMode.active) return access;
  final verdict = ref.watch(demoSessionVerdictProvider);
  return verdict == DemoMode.active ? access : access.copyWith(demo: verdict);
});

/// DEVELOPMENT ONLY — forces [sessionAccessProvider] to a chosen value.
///
/// The seam `§40` of the Point 3 brief asks for: every state screen the
/// classifier can reach has to be *inspectable* even though no backend
/// produces the state yet, and adding six more personas to the login selector
/// would have conflated a development identity with a server lifecycle fact.
/// A release build never writes it — the inspector that does is behind
/// `demoAccountsAllowed` — so it is `null` there and this whole path is inert.
final sessionAccessOverrideProvider = StateProvider<SessionAccess?>((ref) {
  return null;
});

final sessionsProvider = FutureProvider<Result<List<Session>>>((ref) async {
  return ref.read(authRepositoryProvider).listSessions();
});
