import 'dart:convert';

import '../../../core/storage/secure_store.dart';
import '../domain/onboarding_models.dart';

/// The minimum device state needed to resume a pre-session journey.
sealed class StoredOnboardingState {
  const StoredOnboardingState();
}

final class StoredVerificationState extends StoredOnboardingState {
  const StoredVerificationState(this.challenge);

  final VerificationChallenge challenge;

  @override
  String toString() => 'StoredVerificationState(<redacted>)';
}

final class StoredRestrictedSession extends StoredOnboardingState {
  const StoredRestrictedSession({
    required this.token,
    required this.cachedSnapshot,
  });

  /// Opaque backend-issued restricted-session credential.
  final String token;

  /// Safe offline presentation only. It is never final authority: an online
  /// restore always re-reads the backend using [token].
  final OnboardingSnapshot cachedSnapshot;

  @override
  String toString() => 'StoredRestrictedSession(<redacted>)';
}

abstract class AuthStateStore {
  Future<StoredOnboardingState?> readOnboarding();

  Future<void> writeVerification(VerificationChallenge challenge);

  Future<void> writeRestricted({
    required String token,
    required OnboardingSnapshot cachedSnapshot,
  });

  Future<void> clearOnboarding();

  Future<String?> readFullSessionToken();

  Future<void> writeFullSessionToken(String token);

  Future<void> clearFullSession();

  Future<void> clearAll();
}

/// Versioned auth records stored only through platform secure storage.
///
/// The two slots are mutually exclusive. Exchanging a restricted session for
/// a full session removes the onboarding record before the full token is
/// installed, and starting verification removes a stale full-session token.
class SecureAuthStateStore implements AuthStateStore {
  SecureAuthStateStore(this._store);

  static const onboardingKey = 'mtm.auth.onboarding.v1';
  static const fullSessionKey = 'mtm.auth.full_session.v1';

  final SecureStore _store;

  @override
  Future<StoredOnboardingState?> readOnboarding() async {
    final raw = await _store.readString(onboardingKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1) {
        throw const FormatException('auth onboarding record version');
      }
      return switch (decoded['kind']) {
        'verification' => StoredVerificationState(
            VerificationChallenge.fromJson(_map(decoded['challenge'])),
          ),
        'restricted' => StoredRestrictedSession(
            token: _nonEmpty(decoded['token'], 'restricted token'),
            cachedSnapshot:
                OnboardingSnapshot.fromJson(_map(decoded['snapshot'])),
          ),
        _ => throw const FormatException('auth onboarding record kind'),
      };
    } on Object {
      // A malformed local credential is never repaired or trusted. Remove
      // only this namespaced record and let startup classify as signed out.
      await _store.remove(onboardingKey);
      return null;
    }
  }

  @override
  Future<void> writeVerification(VerificationChallenge challenge) async {
    final encoded = jsonEncode({
      'version': 1,
      'kind': 'verification',
      'challenge': challenge.toJson(),
    });
    await _store.remove(fullSessionKey);
    await _store.writeString(onboardingKey, encoded);
  }

  @override
  Future<void> writeRestricted({
    required String token,
    required OnboardingSnapshot cachedSnapshot,
  }) async {
    final value = _nonEmpty(token, 'restricted token');
    final encoded = jsonEncode({
      'version': 1,
      'kind': 'restricted',
      'token': value,
      'snapshot': cachedSnapshot.toJson(),
    });
    await _store.remove(fullSessionKey);
    await _store.writeString(onboardingKey, encoded);
  }

  @override
  Future<void> clearOnboarding() => _store.remove(onboardingKey);

  @override
  Future<String?> readFullSessionToken() async {
    final token = await _store.readString(fullSessionKey);
    if (token == null) return null;
    if (token.trim().isEmpty) {
      await _store.remove(fullSessionKey);
      return null;
    }
    return token;
  }

  @override
  Future<void> writeFullSessionToken(String token) async {
    final value = _nonEmpty(token, 'full session token');
    await _store.remove(onboardingKey);
    await _store.writeString(fullSessionKey, value);
  }

  @override
  Future<void> clearFullSession() => _store.remove(fullSessionKey);

  @override
  Future<void> clearAll() async {
    await _store.remove(onboardingKey);
    await _store.remove(fullSessionKey);
  }

  static Map<String, dynamic> _map(Object? raw) {
    if (raw is Map<String, dynamic>) return raw;
    throw const FormatException('auth record object');
  }

  static String _nonEmpty(Object? raw, String field) {
    if (raw is String && raw.trim().isNotEmpty) return raw;
    throw FormatException(field);
  }
}
