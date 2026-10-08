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
    required this.signedInAt,
  });

  /// How long after [signedInAt] the copy may open the app offline — the
  /// server's own absolute session lifetime.
  static const trustWindow = Duration(days: 7);

  /// The server session the copy was read under (`sessionId` from the
  /// server, stored with the tokens). It binds the copy to that one session:
  /// a different session on this phone never opens on it.
  final String sessionId;

  final AuthUser user;
  final SessionAccess access;

  /// The first confirmed read of this session, in UTC. Kept across later
  /// reads of the same session, so the window never slides.
  final DateTime signedInAt;

  /// The instant the copy stops opening the app offline.
  DateTime get trustEndsAt => signedInAt.add(trustWindow);

  /// Whether the copy may stand in for the server at [now]. A sign-in dated
  /// in the future (the clock was moved back) is not trusted either.
  bool trustedAt(DateTime now) {
    final age = now.toUtc().difference(signedInAt);
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
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        throw const FormatException('me snapshot version');
      }
      final sessionId = decoded['sessionId'];
      final signedInAt = DateTime.parse(decoded['signedInAt'] as String);
      if (sessionId is! String || sessionId.isEmpty || !signedInAt.isUtc) {
        throw const FormatException('me snapshot fields');
      }
      return FullSessionSnapshot(
        sessionId: sessionId,
        user: AuthUser.fromJson(decoded['user'] as Map<String, dynamic>),
        access:
            SessionAccess.fromJson(decoded['access'] as Map<String, dynamic>),
        signedInAt: signedInAt,
      );
    } on Object {
      // Never repaired or trusted, exactly like the credential records.
      await clear();
      return null;
    }
  }

  Future<void> write(FullSessionSnapshot snapshot) async {
    final encoded = jsonEncode({
      'version': 1,
      'sessionId': snapshot.sessionId,
      'user': snapshot.user.toJson(),
      'access': snapshot.access.toJson(),
      'signedInAt': snapshot.signedInAt.toUtc().toIso8601String(),
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
