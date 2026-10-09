import 'dart:convert';

import '../../../core/storage/secure_store.dart';
import '../domain/auth_models.dart';
import '../domain/session_access.dart';

/// The last account `GET /auth/me` confirmed for the full session this phone
/// holds — what a cold launch with no network opens on.
///
/// Presentation, never authority: the same contract as the restricted
/// record's `cachedSnapshot`. Every online read replaces it, and the server
/// still refuses whatever the session can no longer do.
class FullSessionSnapshot {
  const FullSessionSnapshot({
    required this.sessionId,
    required this.user,
    required this.access,
    required this.lastServerContactAt,
  });

  /// How long after [lastServerContactAt] the copy may open the app offline
  /// — the server's own idle limit (`REFRESH_TOKEN_TTL_DAYS`), which every
  /// successful online read slides the same way.
  static const trustWindow = Duration(days: 7);

  /// The server session the copy was read under (`sessionId` from the
  /// server, stored with the tokens). It binds the copy to that one session:
  /// a different session on this phone never opens on it.
  final String sessionId;

  final AuthUser user;
  final SessionAccess access;

  /// The last successful `GET /auth/me` of this session, in UTC. Every
  /// online read moves it forward; an offline open never does, so seven days
  /// without the server are seven days however often the app is opened.
  final DateTime lastServerContactAt;

  /// The instant the copy stops opening the app offline.
  DateTime get trustEndsAt => lastServerContactAt.add(trustWindow);

  /// Whether the copy may stand in for the server at [now]. A contact dated
  /// in the future (the clock was moved back) is not trusted either.
  bool trustedAt(DateTime now) {
    final age = now.toUtc().difference(lastServerContactAt);
    return !age.isNegative && age < trustWindow;
  }

  @override
  String toString() => 'FullSessionSnapshot(<redacted>)';
}

/// One versioned record in platform secure storage, beside the two
/// credential slots of `SecureAuthStateStore` and never inside them.
///
/// Best effort in both directions: a failed write only costs the offline
/// copy, and a record that cannot be read is removed and reads as none.
///
/// Record version 2 names `lastServerContactAt`. A version 1 record (from the
/// build that counted seven days from the sign-in) reads its `signedInAt` as
/// the last contact — never later than the real one, so it only ever ends
/// sooner, never later.
class FullSessionSnapshotStore {
  FullSessionSnapshotStore(this._store);

  static const key = 'mtm.auth.me_snapshot.v1';

  final SecureStore _store;

  Future<FullSessionSnapshot?> read() async {
    final String? raw;
    try {
      raw = await _store.readString(key);
    } on Object {
      return null;
    }
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      final version =
          decoded is Map<String, dynamic> ? decoded['version'] : null;
      if (version != 1 && version != 2) {
        throw const FormatException('me snapshot version');
      }
      decoded as Map<String, dynamic>;
      final sessionId = decoded['sessionId'];
      final contact = DateTime.parse(
          decoded[version == 2 ? 'lastServerContactAt' : 'signedInAt']
              as String);
      if (sessionId is! String || sessionId.isEmpty || !contact.isUtc) {
        throw const FormatException('me snapshot fields');
      }
      return FullSessionSnapshot(
        sessionId: sessionId,
        user: AuthUser.fromJson(decoded['user'] as Map<String, dynamic>),
        access:
            SessionAccess.fromJson(decoded['access'] as Map<String, dynamic>),
        lastServerContactAt: contact,
      );
    } on Object {
      // Never repaired or trusted, exactly like the credential records.
      await clear();
      return null;
    }
  }

  Future<void> write(FullSessionSnapshot snapshot) async {
    final encoded = jsonEncode({
      'version': 2,
      'sessionId': snapshot.sessionId,
      'user': snapshot.user.toJson(),
      'access': snapshot.access.toJson(),
      'lastServerContactAt':
          snapshot.lastServerContactAt.toUtc().toIso8601String(),
    });
    try {
      await _store.writeString(key, encoded);
    } on Object {
      // No offline copy this time; the online session is unaffected.
    }
  }

  Future<void> clear() async {
    try {
      await _store.remove(key);
    } on Object {
      // A copy left behind still opens nothing: it is bound to its session.
    }
  }
}
