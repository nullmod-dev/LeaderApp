import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/network/api_client.dart';
import 'package:mtm/core/network/token_vault.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/startup/startup_destination.dart';
import 'package:mtm/core/startup/startup_providers.dart';
import 'package:mtm/core/storage/local_store.dart';
import 'package:mtm/core/storage/secure_store.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/data/app_lock_controller.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/device_authenticator.dart';
import 'package:mtm/features/auth/data/full_session_snapshot_store.dart';
import 'package:mtm/features/auth/data/http_auth_repository.dart';
import 'package:mtm/features/auth/data/secure_auth_state_store.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

/// An opaque access token. The app never reads inside it: the session is
/// matched on the `sessionId` the server names and the vault stores.
String _access(String sid) => 'access-$sid';

/// A JWT-shaped token whose `sid` claim disagrees with the stored id — the
/// proof that nothing parses the token any more.
String _jwtClaiming(String sid) =>
    'h.${base64Url.encode(utf8.encode(jsonEncode({
          'sid': sid
        }))).replaceAll('=', '')}.s';

class _Phone implements DeviceAuthenticator {
  @override
  bool get enabled => true;

  @override
  Future<DeviceUnlockOutcome> unlock({required String reason}) async =>
      DeviceUnlockOutcome.unlocked;
}

const _admin = AuthUser(
  id: 'acc-1',
  name: 'سارة',
  email: 'sara@leader.test',
  role: AuthRole.mainAdmin,
  saasTenantId: 'tenant-1',
  capabilities: Capabilities(global: Cap.all),
  orgName: 'فرق النبض',
);

/// Plan A3 + D2 — a cold launch with no network opens on the last account
/// `GET /auth/me` confirmed, for seven days from the sign-in, and only for the
/// session that read it — matched on the server's `sessionId`, stored beside
/// the tokens.
void main() {
  late InMemorySecureStore device;
  late DateTime now;
  late http.Response Function(http.Request) server;

  /// The session the server names for the pair this phone holds.
  String? heldSid;

  /// A fresh process over the same phone.
  HttpAuthRepository launch() => HttpAuthRepository(
        ApiClient(
          vault: TokenVault(SecureAuthStateStore(device)),
          origin: 'http://leader.test',
          client: MockClient((request) async => server(request)),
        ),
        snapshots: FullSessionSnapshotStore(device),
        clock: () => now,
      );

  /// A full pair, stored with its session id unless [storedId] is false (a
  /// pair an older build wrote).
  Future<void> holdSession(String sid, {bool storedId = true}) {
    heldSid = sid;
    return TokenVault(SecureAuthStateStore(device)).writeFull(
        _access(sid), 'refresh-$sid',
        sessionId: storedId ? sid : null);
  }

  /// [namesSession] false is a server older than D1.
  void online({Map<String, dynamic>? access, bool namesSession = true}) =>
      server = (request) {
        if (request.url.path.endsWith('/auth/sign-out')) {
          return http.Response('', 204);
        }
        return _json(200, {
          if (namesSession) 'sessionId': heldSid,
          'user': _admin.toJson(),
          'access': access ??
              {
                'accountStatus': 'active',
                'tenantStatus': 'active',
                'demoMode': 'none',
                'mfaRequired': false,
              },
        });
      };

  void offline() =>
      server = (_) => throw const SocketException('no route to host');

  AuthUser? cachedOf(Result<AuthUser?> r) => switch (r) {
        Offline(:final cached) => cached,
        _ => null,
      };

  setUp(() {
    device = InMemorySecureStore();
    now = DateTime.utc(2026, 10, 8, 9);
  });

  test('an online read keeps the account, bound to its session, no tokens',
      () async {
    await holdSession('sid-1');
    online();
    expect((await launch().currentUser() as Success).data?.id, 'acc-1');

    final raw = device.values[FullSessionSnapshotStore.key]!;
    final record = jsonDecode(raw) as Map<String, dynamic>;
    expect(record['sessionId'], 'sid-1');
    expect(record['signedInAt'], '2026-10-08T09:00:00.000Z');
    expect(raw, isNot(contains('refresh-sid-1')));
    expect(raw, isNot(contains(_access('sid-1'))));
  });

  test('a cold launch offline opens the stored account and its envelope',
      () async {
    await holdSession('sid-1');
    online(access: {
      'accountStatus': 'active',
      'tenantStatus': 'suspended',
      'demoMode': 'none',
      'mfaRequired': false,
    });
    await launch().currentUser();

    offline();
    final relaunched = launch();
    final r = await relaunched.currentUser();
    expect(cachedOf(r)?.id, 'acc-1');
    expect(relaunched.currentSessionAccess.tenant, SaasTenantStatus.suspended);
  });

  test('a 5xx or a transport fault opens it too; neither is a sign-out',
      () async {
    await holdSession('sid-1');
    online();
    await launch().currentUser();

    server = (_) => _json(503, {
          'error': {'code': 'server'}
        });
    expect(cachedOf(await launch().currentUser())?.id, 'acc-1');

    server = (_) => throw const HandshakeException('bad certificate');
    expect(cachedOf(await launch().currentUser())?.id, 'acc-1');
  });

  test('seven days after the sign-in the copy answers offline-expired',
      () async {
    await holdSession('sid-1');
    online();
    await launch().currentUser();
    offline();

    now = DateTime.utc(2026, 10, 15, 8, 59);
    expect(cachedOf(await launch().currentUser())?.id, 'acc-1');

    now = DateTime.utc(2026, 10, 15, 9);
    final r = await launch().currentUser();
    expect((r as Failure).code, HttpAuthRepository.offlineExpiredCode);
    // Not a sign-out: the pair stays, so reconnecting can still succeed.
    expect(await TokenVault(SecureAuthStateStore(device)).read(), isNotNull);

    online();
    expect((await launch().currentUser() as Success).data?.id, 'acc-1');
  });

  test('re-reading the same session never moves the sign-in instant', () async {
    await holdSession('sid-1');
    online();
    await launch().currentUser();

    now = DateTime.utc(2026, 10, 12, 9);
    await launch().currentUser();

    offline();
    now = DateTime.utc(2026, 10, 15, 9, 1);
    expect(cachedOf(await launch().currentUser()), isNull);
  });

  test('a clock moved back before the sign-in is not trusted', () async {
    await holdSession('sid-1');
    online();
    await launch().currentUser();
    offline();
    now = DateTime.utc(2026, 10, 7);
    final r = await launch().currentUser();
    expect((r as Failure).code, HttpAuthRepository.offlineExpiredCode);
  });

  group('the session id comes from the server, never from the token', () {
    test('a token claiming another sid still opens on the stored id',
        () async {
      heldSid = 'sid-1';
      await TokenVault(SecureAuthStateStore(device))
          .writeFull(_jwtClaiming('sid-other'), 'r', sessionId: 'sid-1');
      online();
      await launch().currentUser();
      offline();
      expect(cachedOf(await launch().currentUser())?.id, 'acc-1');
    });

    test('a pair stored without an id adopts the one /auth/me names',
        () async {
      await holdSession('sid-1', storedId: false);
      online();
      await launch().currentUser();
      expect((await TokenVault(SecureAuthStateStore(device)).read())?.sessionId,
          'sid-1');
      offline();
      expect(cachedOf(await launch().currentUser())?.id, 'acc-1');
    });

    test('no id from the server and none stored keeps no copy (fails closed)',
        () async {
      await holdSession('sid-1', storedId: false);
      online(namesSession: false);
      expect((await launch().currentUser() as Success).data?.id, 'acc-1');
      expect(device.values.containsKey(FullSessionSnapshotStore.key), isFalse);
      offline();
      expect(await launch().currentUser(), isA<Offline<AuthUser?>>());
    });

    test('rotation keeps the stored id unless the reply names one', () async {
      final vault = TokenVault(SecureAuthStateStore(device));
      await vault.writeFull('a1', 'r1', sessionId: 'sid-1');
      await vault.rotate('a2', 'r2');
      expect((await TokenVault(SecureAuthStateStore(device)).read())?.sessionId,
          'sid-1');
      await vault.rotate('a3', 'r3', sessionId: 'sid-1');
      final reread = await TokenVault(SecureAuthStateStore(device)).read();
      expect(reread?.access, 'a3');
      expect(reread?.sessionId, 'sid-1');
    });
  });

  test('another session on this phone never opens on the copy', () async {
    await holdSession('sid-1');
    online();
    await launch().currentUser();

    await holdSession('sid-2');
    offline();
    expect(cachedOf(await launch().currentUser()), isNull);
    expect(device.values.containsKey(FullSessionSnapshotStore.key), isFalse);
  });

  test('a new session re-reads with a new sign-in instant', () async {
    await holdSession('sid-1');
    online();
    await launch().currentUser();

    now = DateTime.utc(2026, 10, 14, 9);
    await holdSession('sid-2');
    await launch().currentUser();
    final record = jsonDecode(device.values[FullSessionSnapshotStore.key]!)
        as Map<String, dynamic>;
    expect(record['sessionId'], 'sid-2');
    expect(record['signedInAt'], '2026-10-14T09:00:00.000Z');
  });

  group('every way the session ends removes the copy', () {
    setUp(() async {
      await holdSession('sid-1');
      online();
      await launch().currentUser();
      expect(device.values.containsKey(FullSessionSnapshotStore.key), isTrue);
    });

    void expectGone() => expect(
        device.values.containsKey(FullSessionSnapshotStore.key), isFalse);

    test('sign-out', () async {
      await launch().signOut();
      expectGone();
    });

    test('authentication_expired on /auth/me', () async {
      // `/auth/me` and the refresh it triggers both answer 401.
      server = (_) => _json(401, {
            'error': {'code': 'authentication_expired'}
          });
      final r = await launch().currentUser();
      expect((r as Failure).code, 'authentication_expired');
      expectGone();
    });

    test('the API ending the session (markSessionExpired)', () async {
      launch().markSessionExpired();
      await Future<void>.delayed(Duration.zero);
      expectGone();
    });

    test('"not me" on a new device', () async {
      server = (_) => http.Response('', 204);
      await launch().confirmNewDevice(itsMe: false);
      expectGone();
    });

    test('no full session left on the phone', () async {
      await SecureAuthStateStore(device).clearFullSession();
      await launch().currentUser();
      expectGone();
    });
  });

  test('a malformed copy is removed and opens nothing', () async {
    await holdSession('sid-1');
    await device.writeString(FullSessionSnapshotStore.key, '{"version":1}');
    offline();
    expect(cachedOf(await launch().currentUser()), isNull);
    expect(device.values.containsKey(FullSessionSnapshotStore.key), isFalse);
  });

  test('offline restore signs in through the gate, and the app lock holds',
      () async {
    await holdSession('sid-1');
    online();
    await launch().currentUser();
    offline();

    final c = ProviderContainer(overrides: [
      secureStoreProvider.overrideWithValue(device),
      localStoreProvider.overrideWithValue(InMemoryLocalStore()),
      authRepositoryProvider.overrideWith((ref) => launch()),
      deviceAuthenticatorProvider.overrideWithValue(_Phone()),
      clockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(c.dispose);

    // Armed on the cold launch, before the read lands.
    expect(c.read(appLockControllerProvider).phase, AppLockPhase.locked);
    await c.read(currentUserResultProvider.future);

    expect(c.read(authGateProvider), AuthGate.signedIn);
    expect((await c.read(currentUserProvider.future))?.id, 'acc-1');
    expect(c.read(startupDestinationProvider),
        isNot(StartupDestination.signedOut));
    expect(c.read(appLockControllerProvider).phase, AppLockPhase.locked);

    await c.read(appLockControllerProvider.notifier).unlock();
    expect(c.read(appLockControllerProvider).phase, AppLockPhase.open);
  });

  ProviderContainer appOver(HttpAuthRepository repository) =>
      ProviderContainer(overrides: [
        secureStoreProvider.overrideWithValue(device),
        localStoreProvider.overrideWithValue(InMemoryLocalStore()),
        authRepositoryProvider.overrideWithValue(repository),
        deviceAuthenticatorProvider.overrideWithValue(_Phone()),
        clockProvider.overrideWithValue(() => now),
      ]);

  test('an expired copy at launch lands on its own screen, unlocked',
      () async {
    await holdSession('sid-1');
    online();
    await launch().currentUser();
    offline();
    now = DateTime.utc(2026, 10, 15, 9);

    final c = appOver(launch());
    addTearDown(c.dispose);
    expect(c.read(appLockControllerProvider).phase, AppLockPhase.locked);
    await c.read(currentUserResultProvider.future);

    expect(c.read(authGateProvider), AuthGate.offlineExpired);
    expect(c.read(startupDestinationProvider),
        StartupDestination.offlineSessionExpired);
    // The lock never stands in front of a screen with no session to protect.
    expect(c.read(appLockControllerProvider).phase, AppLockPhase.open);
  });

  testWidgets('the seven days also end a running session', (tester) async {
    await holdSession('sid-1');
    online();
    final repository = launch();
    final c = appOver(repository);
    await c.read(currentUserResultProvider.future);
    expect(c.read(authGateProvider), AuthGate.signedIn);
    expect(repository.untilOfflineExpiry, const Duration(days: 7));

    offline();
    now = DateTime.utc(2026, 10, 15, 9);
    // Nothing re-reads before the window closes...
    expect(c.read(authGateProvider), AuthGate.signedIn);
    // ...and the read that fires when it does refuses the copy.
    await tester.pump(const Duration(days: 7));
    await c.read(currentUserResultProvider.future);
    expect(c.read(authGateProvider), AuthGate.offlineExpired);
    expect(repository.untilOfflineExpiry, isNull);
    c.dispose();
  });
}
