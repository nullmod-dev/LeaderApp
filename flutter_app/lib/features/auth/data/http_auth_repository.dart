import 'dart:async';

import '../../../core/access/capability.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/token_vault.dart';
import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';
import '../domain/customer_demo.dart';
import '../domain/session_access.dart';
import 'full_session_snapshot_store.dart';

/// The full-session repository against the Leader API (`docs/api/auth.md`).
///
/// `GET /auth/me` answers `{ user, access }`; both halves are cached here so
/// `sessionAccessProvider` can read the envelope the same way it reads the
/// mock's (`currentSessionAccess`), without a second request.
///
/// A cold launch with no network opens on the last confirmed account
/// ([FullSessionSnapshotStore]) for up to seven days after the last
/// successful server contact, as long as the phone still holds that same
/// session — the server's `sessionId`, stored beside the tokens
/// ([SessionTokens.sessionId]). Offline opens never extend the seven days.
/// Past them the read answers [offlineExpiredCode] and the tokens stay, so
/// the next online read can still succeed.
///
/// The Customer Demo stays local, exactly as with the mock: the trial's data
/// is the in-memory `DemoWorkspace`, so [startCustomerDemo] installs the demo
/// identity on this device and nothing is sent.
class HttpAuthRepository implements AuthRepository {
  HttpAuthRepository(
    this._api, {
    FullSessionSnapshotStore? snapshots,
    DateTime Function()? clock,
  })  : _snapshots = snapshots,
        _clock = clock ?? DateTime.now;

  /// The client-owned failure code for a stored copy whose seven days have
  /// run out while the server cannot be reached.
  static const offlineExpiredCode = 'offline_session_expired';

  final ApiClient _api;

  /// `null` keeps the in-memory behaviour only: no copy survives a restart.
  final FullSessionSnapshotStore? _snapshots;
  final DateTime Function() _clock;

  TokenVault get _vault => _api.vault;

  AuthUser? _me;
  SessionAccess _access = SessionAccess.normal;
  bool _demoActive = false;

  /// Set when the API could not refresh the full session; answered once as
  /// `authentication_expired` so the router lands on `/session-expired`.
  bool _sessionExpired = false;

  /// Password reset (`/forgot` → `/otp` → `/new-password`). The reset bearer
  /// and the address the request was made for live only in memory.
  String? _resetToken;
  String? _resetEmail;

  /// When the offline copy of the current session stops opening the app,
  /// or `null` when there is none. A running session reads itself again at
  /// that instant (`currentUserResultProvider`).
  DateTime? _trustEndsAt;

  SessionAccess get currentSessionAccess => _access;

  /// When this phone stops opening the account offline (seven days after its
  /// last server contact), or `null` when it holds no offline copy.
  DateTime? get offlineTrustEndsAt => _trustEndsAt;

  /// How long until the current session's offline copy expires; `null`
  /// when no copy is held or it has already expired.
  Duration? get untilOfflineExpiry {
    final endsAt = _trustEndsAt;
    if (endsAt == null) return null;
    final left = endsAt.difference(_clock().toUtc());
    return left.isNegative ? null : left;
  }

  /// Wired to [ApiClient.onSessionEnded] by the composition root.
  void markSessionExpired() {
    _sessionExpired = true;
    _me = null;
    _access = SessionAccess.normal;
    unawaited(_forgetSnapshot());
  }

  /// Starts the product customer demo locally — the HTTP twin of
  /// `MockAuthRepository.startCustomerDemo`.
  Future<Result<AuthUser>> startCustomerDemo({
    required CustomerDemoPolicy policy,
  }) async {
    if (!policy.available) {
      return const Failure('', code: 'demo_unavailable');
    }
    await _vault.clearFull();
    await _forgetSnapshot();
    _sessionExpired = false;
    _demoActive = true;
    _me = customerDemoUser;
    _access = const SessionAccess(demo: DemoMode.active);
    return const Success(customerDemoUser);
  }

  @override
  Future<Result<AuthUser>> signIn({
    required String emailOrUsername,
    required String password,
  }) async {
    _endDemo();
    final outcome = await _api.exchange('POST', '/auth/sign-in',
        body: {'email': emailOrUsername.trim(), 'password': password},
        authenticated: false);
    if (outcome is ApiReply && outcome.ok) {
      final json = outcome.json;
      if (json is Map<String, dynamic> && json['outcome'] == 'ready') {
        final sessionId = json['sessionId'];
        await _vault.writeFull(
            json['accessToken'] as String, json['refreshToken'] as String,
            sessionId:
                sessionId is String && sessionId.isNotEmpty ? sessionId : null);
        final me = await currentUser();
        return switch (me) {
          Success(:final data?) => Success(data),
          Success() => const Failure('', code: 'authentication_expired'),
          Failure(:final message, :final code) => Failure(message, code: code),
          Offline() => const Offline(),
        };
      }
      // Verification or onboarding still owed: the onboarding journey owns
      // those outcomes, not the full-session repository.
      return const Failure('', code: 'onboarding_required');
    }
    return ApiClient.resultOf<AuthUser>(outcome, (_) => throw StateError(''));
  }

  @override
  Future<Result<AuthUser?>> currentUser() async {
    if (_demoActive) return Success(_me);
    final SessionTokens? tokens;
    try {
      tokens = await _vault.read();
    } catch (_) {
      // A vault failure is not evidence of sign-out — and it is this phone's
      // storage, not the server, so it must not read as a server failure.
      return const Failure('', code: AuthRepository.deviceStorageCode);
    }
    if (tokens == null || tokens.grade != SessionGrade.full) {
      _me = null;
      _access = SessionAccess.normal;
      await _forgetSnapshot();
      if (_sessionExpired) {
        _sessionExpired = false;
        return const Failure('', code: 'authentication_expired');
      }
      return const Success(null);
    }
    final outcome = await _api.exchange('GET', '/auth/me');
    switch (outcome) {
      case ApiUnreachable(:final offline):
        if (_snapshots != null) {
          final restored = await _restoreSnapshot(tokens);
          if (restored == _Restore.expired) {
            return const Failure('', code: offlineExpiredCode);
          }
          if (restored == _Restore.opened) return Offline(cached: _me);
          return offline ? const Offline() : const Failure('', code: 'network');
        }
        return offline
            ? Offline(cached: _me)
            : const Failure('', code: 'network');
      case ApiReply(:final ok, :final json):
        if (ok && json is Map<String, dynamic>) {
          final user = _parseUser(json['user']);
          if (user == null) return const Failure('', code: 'server');
          _me = user;
          _access = json['access'] is Map<String, dynamic>
              ? SessionAccess.fromJson(json['access'] as Map<String, dynamic>)
              : SessionAccess.normal;
          _sessionExpired = false;
          await _rememberSnapshot(tokens, user, json['sessionId']);
          return Success(user);
        }
        final code = outcome.code;
        if (code == ProblemCode.authenticationExpired.wire) {
          _me = null;
          _access = SessionAccess.normal;
          _sessionExpired = false;
          await _vault.clearFull();
          await _forgetSnapshot();
          return const Failure('', code: 'authentication_expired');
        }
        // A failing server is no more evidence about the session than a
        // missing network.
        if (outcome.status >= 500) {
          if (await _restoreSnapshot(tokens) == _Restore.opened) {
            return Offline(cached: _me);
          }
          // Whatever code the body carried, a 5xx with nothing to open is the
          // server's failure, and the launch says so.
          return Failure(failureMessage(ProblemCode.server.wire),
              code: ProblemCode.server.wire);
        }
        return Failure(failureMessage(code), code: code);
    }
  }

  /// Keeps what this read confirmed for an offline cold launch. This read
  /// reached the server, so it is the new last contact: the seven offline
  /// days start again from now (the server slid the session the same way).
  ///
  /// The session is the one `/auth/me` named ([named]), which is also stored
  /// beside the tokens; an older server that names none falls back to the
  /// id the tokens were stored with. No id at all keeps no copy.
  Future<void> _rememberSnapshot(
    SessionTokens tokens,
    AuthUser user,
    Object? named,
  ) async {
    final snapshots = _snapshots;
    if (snapshots == null) return;
    final sessionId =
        named is String && named.isNotEmpty ? named : tokens.sessionId;
    if (sessionId != null && sessionId != tokens.sessionId) {
      await _vault.adoptSessionId(sessionId);
    }
    // A refused account opens nothing offline either.
    if (sessionId == null || !user.isWellFormed) {
      await _forgetSnapshot();
      return;
    }
    final snapshot = FullSessionSnapshot(
      sessionId: sessionId,
      user: user,
      access: _access,
      lastServerContactAt: _clock().toUtc(),
    );
    await snapshots.write(snapshot);
    _trustEndsAt = snapshot.trustEndsAt;
  }

  /// Opens the stored account when it belongs to the session this phone
  /// still holds and its last server contact is less than seven days old. A copy of
  /// another session — or tokens with no id to match — is removed.
  Future<_Restore> _restoreSnapshot(SessionTokens tokens) async {
    final snapshot = await _snapshots?.read();
    if (snapshot == null) return _Restore.none;
    final sessionId = tokens.sessionId;
    if (sessionId == null || snapshot.sessionId != sessionId) {
      await _forgetSnapshot();
      return _Restore.none;
    }
    if (!snapshot.trustedAt(_clock())) {
      // The seven days also end the copy already open in memory.
      _me = null;
      _access = SessionAccess.normal;
      _trustEndsAt = null;
      return _Restore.expired;
    }
    _me = snapshot.user;
    _access = snapshot.access;
    _trustEndsAt = snapshot.trustEndsAt;
    return _Restore.opened;
  }

  Future<void> _forgetSnapshot() async {
    _trustEndsAt = null;
    await _snapshots?.clear();
  }

  /// `AuthUser.fromJson` refuses a role/tenant contradiction by throwing. The
  /// router's `AuthGate.invalid` exists for exactly that payload, so it is
  /// rebuilt here without the check and handed over for the gate to refuse.
  AuthUser? _parseUser(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    try {
      return AuthUser.fromJson(raw);
    } on FormatException {
      final role = AuthRole.parse(raw['role'] as String?);
      if (role == null) return null;
      try {
        return AuthUser(
          id: raw['id'] as String,
          name: raw['name'] as String,
          email: raw['email'] as String,
          role: role,
          saasTenantId: raw['saasTenantId'] as String?,
          // Refused by the gate before anything reads it: no grant at all.
          capabilities: Capabilities.none,
          orgName: (raw['orgName'] as String?) ?? '',
        );
      } catch (_) {
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Result<void>> signOut() async {
    final wasDemo = _demoActive;
    _endDemo();
    _me = null;
    _access = SessionAccess.normal;
    _sessionExpired = false;
    await _forgetSnapshot();
    if (!wasDemo) {
      final tokens = await _vault.read();
      if (tokens != null) {
        // Best effort: the server revokes the refresh family. The device
        // forgets the pair whatever the answer.
        await _api.exchange('POST', '/auth/sign-out');
      }
    }
    await _vault.clearFull();
    return const Success(null);
  }

  @override
  Future<Result<MfaSetupData>> beginMfaSetup() => _api.send(
        'POST',
        '/auth/mfa/setup',
        parse: (json) => MfaSetupData.fromJson(json as Map<String, dynamic>),
      );

  @override
  Future<Result<void>> verifyMfa(String code) => _api.send(
        'POST',
        '/auth/mfa/verify',
        body: {'code': code},
        parse: (_) {},
      );

  @override
  Future<Result<void>> requestPasswordReset(String email) async {
    final address = email.trim();
    final result = await _api.send<String>(
      'POST',
      '/auth/password-reset/request',
      body: {'email': address},
      authenticated: false,
      parse: (json) => (json as Map<String, dynamic>)['resetToken'] as String,
    );
    if (result case Success(:final data)) {
      _resetToken = data;
      _resetEmail = address;
      return const Success(null);
    }
    return _void(result);
  }

  @override
  Future<Result<void>> verifyResetOtp(String email, String code) {
    final token = _resetToken;
    if (token == null) {
      return Future.value(const Failure('', code: 'authentication_expired'));
    }
    // The address the reset was requested for — the code is bound to it.
    final address = _resetEmail ?? email;
    return _api.send(
      'POST',
      '/auth/password-reset/verify',
      body: {'email': address, 'code': code},
      bearer: token,
      parse: (_) {},
    );
  }

  @override
  Future<Result<void>> setNewPassword(String password) async {
    final token = _resetToken;
    if (token == null) return const Failure('', code: 'authentication_expired');
    final result = await _api.send<void>(
      'POST',
      '/auth/password-reset/complete',
      body: {'password': password},
      bearer: token,
      parse: (_) {},
    );
    if (result.isSuccess) {
      _resetToken = null;
      _resetEmail = null;
    }
    return result;
  }

  /// The server already ended every session of the account (a trusted
  /// device answered "No" to a new one): forget this phone's copy of it
  /// without asking the server anything.
  Future<void> forgetLocalSession() async {
    _endDemo();
    _me = null;
    _access = SessionAccess.normal;
    _sessionExpired = false;
    await _forgetSnapshot();
    await _vault.clearFull();
  }

  @override
  Future<Result<List<Session>>> listSessions() => _api.send(
        'GET',
        '/auth/sessions',
        parse: (json) => [
          for (final row in json as List)
            Session.fromJson(row as Map<String, dynamic>),
        ],
      );

  @override
  Future<Result<void>> revokeSession(String id) => _api.send(
        'DELETE',
        '/auth/sessions/${Uri.encodeComponent(id)}',
        parse: (_) {},
      );

  void _endDemo() {
    _demoActive = false;
  }

  static Result<void> _void<T>(Result<T> r) => switch (r) {
        Success() => const Success(null),
        Failure(:final message, :final code) => Failure(message, code: code),
        Offline() => const Offline(),
      };
}

/// What an offline read could do with the stored copy.
enum _Restore {
  /// No copy for the session this phone holds.
  none,

  /// The copy opened: same session, under seven days old.
  opened,

  /// The same session's copy, past its seven days (or dated in the future).
  expired,
}
