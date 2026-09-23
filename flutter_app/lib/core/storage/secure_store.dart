/// The app's single storage seam for security-sensitive credentials.
///
/// This is intentionally separate from `LocalStore`, which is backed by
/// ordinary preferences and is only suitable for non-sensitive settings.
/// Passwords, OTPs, Team Codes, provider tokens and reset/MFA secrets must
/// never be written through either seam.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureStore {
  Future<String?> readString(String key);

  Future<void> writeString(String key, String value);

  Future<void> remove(String key);
}

/// Platform keystore/keychain-backed storage.
///
/// Errors are allowed to propagate to the repository: unlike a theme
/// preference, silently losing a credential write would make the UI claim a
/// session can be restored when it cannot. Callers fail closed and surface a
/// generic authentication error without logging the value or provider code.
class PlatformSecureStore implements SecureStore {
  PlatformSecureStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readString(String key) => _storage.read(key: key);

  @override
  Future<void> writeString(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> remove(String key) => _storage.delete(key: key);
}

/// A process-independent device stand-in for tests.
///
/// A new repository/container over the same instance is a new app process
/// reading the same secure device vault. [values] exists only for assertions
/// that forbidden secrets were not persisted.
class InMemorySecureStore implements SecureStore {
  InMemorySecureStore([Map<String, String>? seed]) : _values = {...?seed};

  final Map<String, String> _values;

  Map<String, String> get values => Map.unmodifiable(_values);

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeString(String key, String value) async =>
      _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}
