/// A random per-installation identifier, sent only as `X-Device-Id` on
/// `POST /auth/google`, so the backend can budget failed Google sign-ins per
/// device instead of per IP — many mobile users share one carrier IP.
///
/// A UUID v4 from `Random.secure()`, minted the first time it is asked for and
/// kept in [LocalStore] under [DeviceIdStore.storageKey]. It names this
/// installation and nothing else: no account, no hardware id, no advertising
/// id. Clearing the app's data mints a new one, which is fine — the backend's
/// per-IP backstop, not this id, is what stops a client that rotates it.
library;

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_store.dart';
import 'auth_providers.dart' show localStoreProvider;

class DeviceIdStore {
  DeviceIdStore(this._store, {Random? random})
      : _random = random ?? Random.secure();

  static const storageKey = 'mtm.device.id';

  final LocalStore _store;
  final Random _random;
  Future<String>? _pending;

  /// This installation's id; the same value for the life of the install.
  Future<String> read() => _pending ??= _load();

  Future<String> _load() async {
    final stored = await _store.readString(storageKey);
    if (stored != null && isUuidV4(stored)) return stored;
    final minted = uuidV4(_random);
    await _store.writeString(storageKey, minted);
    return minted;
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
  return DeviceIdStore(ref.watch(localStoreProvider));
});
