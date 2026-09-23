import 'dart:math';

import '../../../core/env/build_mode.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/secure_store.dart';
import '../../../l10n/strings.dart';
import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';
import '../domain/customer_demo.dart';
import '../domain/demo_session_store.dart';
import '../domain/session_access.dart';
import 'dev_test_credentials.dart';
import 'demo_personas.dart';
import 'in_memory_demo_session_store.dart';
import 'secure_auth_state_store.dart';

/// The remote half of the development full-session exchange.
///
/// Tests share one instance across fresh repositories to model a real process
/// death: the device vault survives locally and this server registry survives
/// remotely. The device stores only the opaque token; [AuthUser] and its grant
/// are always re-read from this authoritative side.
class MockAuthSessionServer {
  final Map<String, AuthUser> _sessions = {};
  final Set<String> _revoked = {};
  int _sequence = 0;

  String? lastIssuedToken;

  String issue(AuthUser user) {
    final token = 'mock_full_session_${++_sequence}';
    _sessions[token] = user;
    lastIssuedToken = token;
    return token;
  }

  AuthUser? userFor(String token) =>
      _revoked.contains(token) ? null : _sessions[token];

  bool contains(String token) => _sessions.containsKey(token);

  bool isRevoked(String token) => _revoked.contains(token);

  void revoke(String token) {
    if (_sessions.containsKey(token)) _revoked.add(token);
  }
}

/// The development authentication repository.
///
/// It knows exactly three accounts — the three demo personas — and it is
/// wired only in a development build. A shipping build overrides
/// `authRepositoryProvider` with a network-backed repository; this class is
/// never the fallback for one.
///
/// **Two authentication paths, kept separate on purpose** (`§11` of the Point
/// 2 brief):
///
/// 1. [signIn] — ordinary credential authentication. It resolves the address
///    against the persona table and answers with **that** account, or
///    refuses. It no longer hands every input the same full administrator,
///    which was the behaviour that made every development session look like a
///    Main Admin whatever was typed.
/// 2. [signInAsPersona] — a legacy test-only shortcut kept behind
///    `DemoSignInController`; no Login widget exposes it. It is not on
///    [AuthRepository], so the production interface carries no persona entry.
///
/// Both paths land in the same place — `_me`, the session
/// `currentUserResultProvider` reads and the one ordinary sign-out clears.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository({
    DemoSessionStore? demoSessions,
    AuthStateStore? authState,
    MockAuthSessionServer? sessionServer,
    bool demoAccountsEnabled = demoAccountsAllowed,
  })  : _demoSessions = demoSessions ?? InMemoryDemoSessionStore(),
        _authState = authState ?? SecureAuthStateStore(InMemorySecureStore()),
        _sessionServer = sessionServer ?? MockAuthSessionServer(),
        // Both gates, and the constant is the one that cannot be overridden:
        // a release artefact resolves this to `false` no matter what the
        // provider says, so no demo account can be authenticated or restored.
        _demoEnabled = demoAccountsEnabled && demoAccountsAllowed;

  final DemoSessionStore _demoSessions;
  final AuthStateStore _authState;
  final MockAuthSessionServer _sessionServer;
  String? _fullSessionToken;

  /// Whether this repository may authenticate or restore a demo persona.
  /// `false` in a release configuration, where every demo path below is
  /// refused and the repository authenticates nobody.
  final bool _demoEnabled;

  /// The signed-in account, or null.
  ///
  /// Starts null and is filled by [_restoreDemoSession] on the first session
  /// read — the app no longer boots into a hard-coded administrator. What it
  /// boots into is whatever the development session store holds, which on a
  /// fresh development device is the Main Admin persona
  /// (`InMemoryDemoSessionStore`'s seed) and after a sign-out is nothing.
  AuthUser? _me;
  SessionAccess _access = SessionAccess.normal;

  /// The mock companion to the session envelope. Production supplies this
  /// beside `AuthUser`; keeping it here lets the customer-demo entry create
  /// one coherent full session without reusing a developer persona.
  SessionAccess get currentSessionAccess => _access;

  /// Whether the persisted persona has already been consulted.
  ///
  /// One restore per repository instance. A restore that ran and found
  /// nothing must not run again on the next read, or a sign-out followed by a
  /// session refresh would resurrect the persona it just cleared. A relaunch
  /// is a *new* repository over the same store, which is exactly the state
  /// this flag is per-instance for.
  bool _restored = false;

  final _rand = Random(7);

  Future<void> _latency() => Future<void>.delayed(
        Duration(milliseconds: 400 + _rand.nextInt(400)),
      );

  /// Restores the persona the last development session selected.
  ///
  /// Release safety: when demo accounts are not allowed this reads nothing
  /// and writes nothing, so a stored persona left behind by a development
  /// build on the same device cannot become a session. The record is not
  /// cleared either — refusing to honour it is the requirement; deleting a
  /// developer's state from a production run is not.
  Future<void> _restoreDemoSession() async {
    if (!demoAccountsAllowed || !_demoEnabled) return;
    final String? stored;
    try {
      stored = await _demoSessions.read();
    } catch (_) {
      // A store that cannot be read is not a session. Fail closed — the
      // opposite of the forced-upgrade gate, because here failing open would
      // mean inventing an authenticated user.
      return;
    }
    _me = DemoPersona.parse(stored)?.user;
    _access = SessionAccess.normal;
  }

  /// Signs in as an explicitly selected development persona.
  ///
  /// Refused outright in a release configuration, and unreachable there
  /// anyway — the caller checks [demoAccountsAllowed] first, and that
  /// constant makes this whole branch dead code the tree shaker removes.
  Future<Result<AuthUser>> signInAsPersona(DemoPersona persona) async {
    if (!demoAccountsAllowed || !_demoEnabled) {
      return const Failure('غير متاح.', code: 'not_permitted');
    }
    await _latency();
    _restored = true;
    _fullSessionToken = null;
    await _authState.clearFullSession();
    _me = persona.user;
    _access = SessionAccess.normal;
    await _demoSessions.write(persona.wire);
    return Success(_me!);
  }

  @override
  Future<Result<AuthUser>> signIn({
    required String emailOrUsername,
    required String password,
  }) async {
    await _latency();
    // An explicit sign-in supersedes whatever was on file; a later session
    // read must not overwrite it with the stored persona.
    _restored = true;
    _fullSessionToken = null;
    await _authState.clearFullSession();
    if (password.length < 4) {
      return const Failure('كلمة المرور قصيرة جدا.');
    }
    // The release rule from §10 of the brief, stated in code: production
    // authentication has no fallback that recognises a demo credential. This
    // repository knows only demo accounts, so in a release configuration it
    // authenticates nobody at all — which is correct for a development mock
    // that a shipping build replaces outright.
    if (!demoAccountsAllowed || !_demoEnabled) {
      return const Failure('تعذّر تسجيل الدخول.', code: 'not_permitted');
    }
    final credential = DevTestCredentials.forEmail(emailOrUsername);
    if (credential == null || !credential.matchesPassword(password)) {
      // Deliberately *not* "any credentials sign you in as the full admin".
      // Development authenticates only an exact local email/password pair.
      return const Failure(
        'تعذّر تسجيل الدخول.',
        code: 'invalid_credentials',
      );
    }
    final persona = credential.persona;
    _me = credential.user;
    _access = SessionAccess.normal;
    await _demoSessions.write(persona.wire);
    return Success(_me!);
  }

  /// Installs the full session Point 17B's onboarding journey just produced.
  ///
  /// The mock counterpart of "both repositories read the same token vault in
  /// a real build" (`onboarding_repository.dart`): `OnboardingRepository`
  /// never imports this class, so `onboardingRepositoryProvider` is wired
  /// with this method as an `OnboardingSessionIssued` callback instead. Every
  /// field on [user] already came from a backend authorization — this call
  /// only makes it the session `currentUser()` answers with.
  Future<void> installOnboardedSession(AuthUser user) async {
    _restored = true;
    _me = user;
    _access = SessionAccess.normal;
    final token = _sessionServer.issue(user);
    await _authState.writeFullSessionToken(token);
    _fullSessionToken = token;
    await _demoSessions.clear();
  }

  /// Starts the product customer demo, not a debug persona.
  Future<Result<AuthUser>> startCustomerDemo({
    required CustomerDemoPolicy policy,
  }) async {
    if (!policy.available) {
      return const Failure('', code: 'demo_unavailable');
    }
    await _latency();
    _restored = true;
    _fullSessionToken = null;
    await _authState.clearFullSession();
    _me = customerDemoUser;
    _access = const SessionAccess(demo: DemoMode.active);
    // A product demo must never be persisted in the development-persona key.
    await _demoSessions.clear();
    return const Success(customerDemoUser);
  }

  @override
  Future<Result<AuthUser?>> currentUser() async {
    await _latency();
    if (!_restored) {
      _restored = true;
      try {
        final token = await _authState.readFullSessionToken();
        if (token != null) {
          final user = _sessionServer.userFor(token);
          if (user == null) {
            await _authState.clearFullSession();
            _fullSessionToken = null;
            _me = null;
            // A token the server no longer accepts is expired/revoked. Never
            // fall through to a development persona after a credential was
            // present, even in debug builds.
            return const Failure('', code: 'authentication_expired');
          } else {
            _fullSessionToken = token;
            _me = user;
            _access = SessionAccess.normal;
          }
        }
        if (_me == null) await _restoreDemoSession();
      } catch (_) {
        // A vault failure is not evidence of sign-out and never becomes a
        // locally invented user. The auth gate remains unresolved.
        _restored = false;
        return const Failure('', code: 'server');
      }
    }
    return Success(_me);
  }

  @override
  Future<Result<void>> signOut() async {
    await _latency();
    _me = null;
    _access = SessionAccess.normal;
    final token = _fullSessionToken;
    if (token != null) _sessionServer.revoke(token);
    _fullSessionToken = null;
    await _authState.clearFullSession();
    // The same sign-out every account uses — there is no separate demo
    // logout. Clearing the record is what makes the next launch stay signed
    // out instead of restoring the persona that just left.
    _restored = true;
    await _demoSessions.clear();
    return const Success(null);
  }

  @override
  Future<Result<MfaSetupData>> beginMfaSetup() async {
    await _latency();

    // TODO(backend): secret and otpauth URI must come from the server.
    // Never generate a TOTP secret on the client.
    //
    // The values below are FIXTURES for the mock only — they are not
    // computed here and must not be treated as a valid TOTP secret.
    // The real repository implementation will delegate this call to
    // POST /api/v1/mfa/setup and return the server's response verbatim.
    // Backup codes follow the same rule: issued by the server, never
    // generated on the device.
    const serverIssuedFixture = MfaSetupData(
      otpauthUrl:
          'otpauth://totp/${S.productNameEn}:pbea4007@mtu.edu.iq?secret=JBSWY3DPEHPK3PXP&issuer=${S.productNameEn}',
      manualSecret: 'JBSWY3DPEHPK3PXP',
      backupCodes: [
        'F7K2-9QLM',
        'W3RA-B0VC',
        '8ZP4-JDN1',
        'HYX9-5MKT',
        '2QCS-EL7B',
        'V0RE-YH6U',
        'M9NA-6WFP',
        'X1TB-KO4J',
      ],
    );
    return const Success(serverIssuedFixture);
  }

  @override
  Future<Result<void>> verifyMfa(String code) async {
    await _latency();
    if (code.length != 6) return const Failure('الرمز يجب أن يكون ٦ أرقام.');
    return const Success(null);
  }

  @override
  Future<Result<void>> requestPasswordReset(String email) async {
    await _latency();
    return const Success(null);
  }

  @override
  Future<Result<void>> verifyResetOtp(String email, String code) async {
    await _latency();
    if (code.length != 6) return const Failure('الرمز غير صحيح.');
    return const Success(null);
  }

  @override
  Future<Result<void>> setNewPassword(String password) async {
    await _latency();
    if (password.length < 8) {
      return const Failure('٨ أحرف على الأقل.');
    }
    return const Success(null);
  }

  @override
  Future<Result<void>> confirmNewDevice({required bool itsMe}) async {
    await _latency();
    return const Success(null);
  }

  /// Built once so a revoke actually removes a row instead of the list
  /// reappearing intact on the next read.
  late final List<Session> _sessions = () {
    final now = DateTime.now();
    return [
      Session(
        id: 's_cur',
        device: 'iPhone 15 · Safari',
        ipMasked: '176.29.xx.xx',
        locationLabel: 'دمشق, سوريا',
        startedAt: now.subtract(const Duration(hours: 1, minutes: 12)),
        current: true,
      ),
      Session(
        id: 's_2',
        device: 'MacBook Pro · Chrome',
        ipMasked: '176.29.xx.xx',
        locationLabel: 'دمشق, سوريا',
        startedAt: now.subtract(const Duration(days: 1, hours: 4)),
        current: false,
      ),
      Session(
        id: 's_3',
        device: 'Samsung Galaxy · ${S.productNameEn} App',
        ipMasked: '82.137.xx.xx',
        locationLabel: 'حمص, سوريا',
        startedAt: now.subtract(const Duration(days: 3)),
        current: false,
      ),
    ];
  }();

  @override
  Future<Result<List<Session>>> listSessions() async {
    await _latency();
    return Success(List.of(_sessions));
  }

  @override
  Future<Result<void>> revokeSession(String id) async {
    await _latency();
    final i = _sessions.indexWhere((s) => s.id == id);
    if (i < 0) return const Failure('لم يُعثر على الجلسة.', code: 'not_found');
    if (_sessions[i].current) {
      return const Failure('لا يمكن إنهاء الجلسة الحالية من هنا.',
          code: 'validation');
    }
    _sessions.removeAt(i);
    return const Success(null);
  }
}
