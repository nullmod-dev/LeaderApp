/// The app's **one** durable local key/value seam.
///
/// MTM had no durable storage at all before this file: every store
/// (`SettingsRepository`, `AppVersionGateStore`, `DemoSessionStore`) was a
/// mock that held its record for the lifetime of one Dart object, and a real
/// process restart lost it. This is the mechanism those seams were written
/// against — one small interface, three operations, so a second storage
/// architecture never has to appear beside it.
///
/// **It stores strings and nothing else.** A caller that needs structure
/// encodes its own JSON, which keeps the shape of a record owned by the store
/// that defines it rather than by this file.
///
/// **What must never be written here.** This is ordinary unencrypted device
/// preference storage — the bucket `DATA-NEEDS.md` §3.3 allows for theme,
/// motion level and the forced-upgrade verdict. No token, no password, no
/// TOTP secret, no capability grant and no personal record goes in it. The
/// one identity-shaped thing it holds is the *development* persona id, which
/// names a fixture compiled into a debug build and authenticates nothing on
/// its own.
library;

import 'package:shared_preferences/shared_preferences.dart';

abstract class LocalStore {
  /// The stored value, or `null` when the key was never written.
  Future<String?> readString(String key);

  Future<void> writeString(String key, String value);

  /// Removes the key entirely, so a later [readString] answers `null`.
  Future<void> remove(String key);
}

/// The real device implementation, on `shared_preferences`.
///
/// Every operation is guarded: on a platform with no plugin registered — a
/// plain `flutter test` host, a headless tool — the platform channel throws,
/// and a store that let that escape would take down whatever asked. A read
/// that cannot happen answers `null` (the caller's "nothing on file"), and a
/// write that cannot happen is dropped. That is the correct failure direction
/// for everything this store is allowed to hold: losing a preference is a
/// nuisance, and no security decision rests on a value here.
class SharedPreferencesLocalStore implements LocalStore {
  SharedPreferencesLocalStore();

  Future<SharedPreferences>? _pending;

  Future<SharedPreferences> get _prefs =>
      _pending ??= SharedPreferences.getInstance();

  @override
  Future<String?> readString(String key) async {
    try {
      return (await _prefs).getString(key);
    } catch (_) {
      // A failed lookup must not be retried forever against a broken handle.
      _pending = null;
      return null;
    }
  }

  @override
  Future<void> writeString(String key, String value) async {
    try {
      await (await _prefs).setString(key, value);
    } catch (_) {
      _pending = null;
    }
  }

  @override
  Future<void> remove(String key) async {
    try {
      await (await _prefs).remove(key);
    } catch (_) {
      _pending = null;
    }
  }
}

/// A [LocalStore] held in memory.
///
/// For tests, and for the one production case that must not touch the device
/// at all: a build where the development persona record may not be read (see
/// `demoSessionStoreProvider`). A second object built over the **same** map
/// models an app relaunch, which is the idiom `forced_upgrade_test.dart`
/// established.
class InMemoryLocalStore implements LocalStore {
  InMemoryLocalStore([Map<String, String>? seed]) : _values = {...?seed};

  final Map<String, String> _values;

  /// The raw contents, for a test that asserts a key is gone.
  Map<String, String> get values => Map.unmodifiable(_values);

  @override
  Future<String?> readString(String key) async => _values[key];

  @override
  Future<void> writeString(String key, String value) async =>
      _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}
