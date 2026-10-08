import 'dart:convert';

import '../../features/auth/data/secure_auth_state_store.dart';
import '../../features/auth/domain/onboarding_models.dart';

/// Which kind of session a credential pair belongs to.
///
/// The backend issues two (`docs/api/auth.md` → "Outcome union"): a **full**
/// session for a finished account, and a **restricted** onboarding session
/// that only reaches `/auth/onboarding/**`, `/auth/sign-out` and
/// `/auth/refresh`. The device never holds both at once.
enum SessionGrade { full, onboarding }

/// One access/refresh pair. Opaque strings; never logged.
class SessionTokens {
  const SessionTokens({
    required this.access,
    required this.refresh,
    required this.grade,
    this.sessionId,
  });

  final String access;
  final String refresh;
  final SessionGrade grade;

  /// The server session this pair belongs to (`sessionId` in every
  /// sign-in, refresh and `/auth/me` answer). Refresh never changes it.
  /// `null` until the server has named it — a pair stored by an older build,
  /// or answered by an older server.
  final String? sessionId;

  @override
  String toString() => 'SessionTokens(<redacted>, ${grade.name})';
}

/// The HTTP layer's view of the device's credential vault.
///
/// **Not a second store.** Every value goes through the existing
/// [AuthStateStore] — the same two namespaced, versioned secure-storage
/// records (`mtm.auth.full_session.v1`, `mtm.auth.onboarding.v1`) the app
/// already reads at startup — so the "one slot at a time" rule and the
/// fail-closed parsing stay where they were written. A pair is kept in a
/// slot as one small JSON string, which the store treats as the opaque token
/// it always was.
///
/// Reads are cached in memory because every request needs the access token;
/// every write goes through this class, so the cache cannot drift.
class TokenVault {
  TokenVault(this._state);

  final AuthStateStore _state;

  SessionTokens? _cached;
  bool _loaded = false;

  Future<SessionTokens?> read() async {
    if (_loaded) return _cached;
    SessionTokens? found;
    final full = await _state.readFullSessionToken();
    if (full != null) {
      found = _decode(full, SessionGrade.full);
      // A credential this build cannot read (for example one a mock build
      // left behind) is not a session. Drop it rather than guess.
      if (found == null) await _state.clearFullSession();
    }
    if (found == null) {
      final onboarding = await _state.readOnboarding();
      if (onboarding is StoredRestrictedSession) {
        found = _decode(onboarding.token, SessionGrade.onboarding);
        if (found == null) await _state.clearOnboarding();
      }
    }
    _cached = found;
    _loaded = true;
    return found;
  }

  /// Installs a full session. Removes any onboarding record first — the
  /// store's own exchange rule.
  Future<void> writeFull(
    String access,
    String refresh, {
    String? sessionId,
  }) async {
    await _state.writeFullSessionToken(_encode(access, refresh, sessionId));
    _remember(SessionTokens(
        access: access,
        refresh: refresh,
        grade: SessionGrade.full,
        sessionId: sessionId));
  }

  /// Installs a restricted onboarding session with its last snapshot (the
  /// offline presentation the startup restore falls back to).
  Future<void> writeOnboarding(
    String access,
    String refresh,
    OnboardingSnapshot snapshot, {
    String? sessionId,
  }) async {
    await _state.writeRestricted(
      token: _encode(access, refresh, sessionId),
      cachedSnapshot: snapshot,
    );
    _remember(SessionTokens(
        access: access,
        refresh: refresh,
        grade: SessionGrade.onboarding,
        sessionId: sessionId));
  }

  /// Keeps the onboarding credential and replaces only its cached snapshot.
  Future<void> updateOnboardingSnapshot(OnboardingSnapshot snapshot) async {
    final tokens = await read();
    if (tokens == null || tokens.grade != SessionGrade.onboarding) return;
    await _state.writeRestricted(
      token: _encode(tokens.access, tokens.refresh, tokens.sessionId),
      cachedSnapshot: snapshot,
    );
  }

  /// Records the session id an online `GET /auth/me` named for the full
  /// pair this device holds. Nothing else changes.
  Future<void> adoptSessionId(String sessionId) async {
    final tokens = await read();
    if (tokens == null || tokens.grade != SessionGrade.full) return;
    if (tokens.sessionId == sessionId) return;
    await writeFull(tokens.access, tokens.refresh, sessionId: sessionId);
  }

  /// Stores a pending verification challenge. No session exists alongside
  /// one, so the full-session slot is emptied by the store itself.
  Future<void> writeVerification(VerificationChallenge challenge) async {
    await _state.writeVerification(challenge);
    _remember(null);
  }

  /// The pair `POST /auth/refresh` rotated. Same grade as before: an
  /// onboarding refresh yields an onboarding token, a full refresh never
  /// downgrades (`docs/api/auth.md` → "POST /auth/refresh"). Rotation keeps
  /// the session, so a reply without a [sessionId] keeps the stored one.
  Future<void> rotate(String access, String refresh, {String? sessionId}) async {
    final current = await read();
    if (current == null) return;
    final id = sessionId ?? current.sessionId;
    switch (current.grade) {
      case SessionGrade.full:
        await writeFull(access, refresh, sessionId: id);
      case SessionGrade.onboarding:
        final stored = await _state.readOnboarding();
        if (stored is! StoredRestrictedSession) return;
        await writeOnboarding(access, refresh, stored.cachedSnapshot,
            sessionId: id);
    }
  }

  Future<void> clearFull() async {
    await _state.clearFullSession();
    if (_cached?.grade == SessionGrade.full) _remember(null);
  }

  Future<void> clearOnboarding() async {
    await _state.clearOnboarding();
    if (_cached?.grade == SessionGrade.onboarding) _remember(null);
  }

  /// Ends whatever session this device holds, of either grade.
  Future<void> clear() async {
    await _state.clearAll();
    _remember(null);
  }

  void _remember(SessionTokens? tokens) {
    _cached = tokens;
    _loaded = true;
  }

  static String _encode(String access, String refresh, String? sessionId) =>
      jsonEncode({
        'v': 1,
        'access': access,
        'refresh': refresh,
        if (sessionId != null) 'sid': sessionId,
      });

  static SessionTokens? _decode(String raw, SessionGrade grade) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['v'] != 1) return null;
      final access = decoded['access'];
      final refresh = decoded['refresh'];
      if (access is! String || access.isEmpty) return null;
      if (refresh is! String || refresh.isEmpty) return null;
      // The id is optional (older records have none); a malformed one is
      // dropped, never trusted, and the pair itself stays usable.
      final sid = decoded['sid'];
      return SessionTokens(
        access: access,
        refresh: refresh,
        grade: grade,
        sessionId: sid is String && sid.isNotEmpty ? sid : null,
      );
    } on FormatException {
      return null;
    }
  }
}
