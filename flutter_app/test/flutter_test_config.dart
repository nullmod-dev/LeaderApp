import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs before every test in this suite (the `flutter_test` convention: one
/// `flutter_test_config.dart` beside `test/`, applied to every file under it).
///
/// **Why it exists.** `shared_preferences` is a platform plugin, and a
/// `flutter test` host has no platform behind it — so an unguarded call throws
/// `MissingPluginException`. The app's own store swallows that and reports
/// "nothing on file", which is the right failure direction in production but
/// the wrong *fixture*: every test that boots the real `MockAuthRepository`
/// would come up signed out, because the development persona record could
/// never be seeded or read.
///
/// [SharedPreferences.setMockInitialValues] installs the package's own
/// in-memory store instead, so the durable path is exercised for real — the
/// first-run seed writes, sign-out clears, and a second container over the
/// same values behaves like a relaunch.
///
/// It is re-installed **before each test**, not once for the run. The mock
/// store is process-global, so a test that signs out would otherwise leave the
/// persona record cleared for every test after it in the same file — an order
/// dependency that shows up as one unrelated test failing when another is
/// added above it.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });
  await testMain();
}
