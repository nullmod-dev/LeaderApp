/// A random per-installation identifier, sent as `X-Device-Id` on every API
/// request. The backend keys device trust on it (`docs/api/auth.md` → Device
/// trust: a new device needs an email code and starts restricted) and budgets
/// failed Google sign-ins per device instead of per IP — many mobile users
/// share one carrier IP.
///
/// A UUID v4 from `Random.secure()`, minted on the first launch that asks for
/// it and kept in [SecureStore] under [DeviceIdStore.storageKey]. It names this
/// installation and nothing else: no account, no hardware id, no advertising
/// id. The server stores only its hash.
///
/// **A reinstall is a new device.** Android wipes secure storage with the app;
/// the iOS Keychain does not, so a marker in [LocalStore] (which every
/// platform wipes on uninstall) tells this installation's own id from one an
/// earlier installation left behind. An id minted before secure storage held
/// it (in [LocalStore], same key) is moved over once and kept, so a phone
/// that updates the app stays the same device.
library;

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';
import '../../../core/storage/secure_store.dart';
import 'auth_providers.dart' show localStoreProvider, secureStoreProvider;

class DeviceIdStore {
  DeviceIdStore(this._secure, this._local, {Random? random})
      : _random = random ?? Random.secure();

  static const storageKey = 'mtm.device.id';

  /// In [LocalStore]: this installation already holds its id in secure storage.
  static const installedKey = 'mtm.device.installed';

  final SecureStore _secure;
  final LocalStore _local;
  final Random _random;

  Future<String>? _pending;

  /// This installation's id; the same value for the life of the install.
  Future<String> read() => _pending ??= _load();

  Future<String> _load() async {
    final legacy = await _local.readString(storageKey);
    final installed = await _local.readString(installedKey) != null;
    String? id;
    if (legacy != null && isUuidV4(legacy)) {
      // Minted by an earlier build of this same installation: keep it.
      id = legacy;
      await _secure.writeString(storageKey, legacy);
    } else if (installed) {
      final stored = await _secure.readString(storageKey);
      if (stored != null && isUuidV4(stored)) id = stored;
    }
    // No marker: a fresh install. An id still in the Keychain belongs to an
    // earlier installation and is not reused.
    if (id == null) {
      id = uuidV4(_random);
      await _secure.writeString(storageKey, id);
    }
    if (!installed) await _local.writeString(installedKey, '1');
    if (legacy != null) await _local.remove(storageKey);
    return id;
  }
}

final _uuidV4Pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

bool isUuidV4(String value) => _uuidV4Pattern.hasMatch(value);

/// RFC 9562 §5.4: 122 random bits, version `0100`, variant `10`.
String uuidV4([Random? random]) {
  final source = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final deviceIdStoreProvider = Provider<DeviceIdStore>((ref) {
  return DeviceIdStore(
    ref.watch(secureStoreProvider),
    ref.watch(localStoreProvider),
  );
});
