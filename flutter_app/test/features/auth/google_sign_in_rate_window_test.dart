import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mtm/core/network/api_client.dart';
import 'package:mtm/core/network/token_vault.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/storage/local_store.dart';
import 'package:mtm/core/storage/secure_store.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/device_id_store.dart';
import 'package:mtm/features/auth/data/google_identity_gateway.dart';
import 'package:mtm/features/auth/data/google_sign_in_rate_window.dart';
import 'package:mtm/features/auth/data/http_onboarding_repository.dart';
import 'package:mtm/features/auth/data/onboarding_controller.dart';
import 'package:mtm/features/auth/data/secure_auth_state_store.dart';
import 'package:mtm/features/auth/domain/onboarding_models.dart';
import 'package:mtm/features/auth/domain/onboarding_repository.dart';

const _rejected = OnboardingFailure<Object?>(
    OnboardingProblemCode.googleAssertionRejected);

class _Clock {
  DateTime now = DateTime.utc(2026, 10, 6, 12);
  DateTime call() => now;
  void advance(Duration by) => now = now.add(by);
}

class _TokenClient implements GoogleIdentityTokenClient {
  int calls = 0;

  @override
  bool get configured => true;

  @override
  Future<String> obtainIdToken() async {
    calls++;
    return 'header.payload.signature';
  }
}

http.Response _json(int status, Object body, [Map<String, String>? headers]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json', ...?headers});

void main() {
  group('GoogleSignInRateWindow', () {
    late InMemoryLocalStore store;
    late _Clock clock;
    late GoogleSignInRateWindow window;

    setUp(() {
      store = InMemoryLocalStore();
      clock = _Clock();
      window = GoogleSignInRateWindow(store, now: clock.call);
    });

    test('six refusals in an hour block until the oldest ages out', () async {
      for (var i = 0; i < 5; i++) {
        await window.record(_rejected);
        clock.advance(const Duration(minutes: 1));
      }
      expect(await window.blockedFor(), isNull);
      await window.record(_rejected);
      // Oldest at 12:00, now 12:05 → free at 13:00.
      expect(await window.blockedFor(), const Duration(minutes: 55));

      clock.advance(const Duration(minutes: 55));
      expect(await window.blockedFor(), isNull);
    });

    test('successes, offline attempts and transport faults never count',
        () async {
      for (var i = 0; i < 10; i++) {
        await window.record(const Success<Object?>(null));
        await window.record(const Offline<Object?>());
        await window.record(const Failure<Object?>('', code: 'network'));
      }
      expect(await window.blockedFor(), isNull);
      expect(store.values, isEmpty);
    });

    test('a server 429 blocks until its Retry-After, capped at one window',
        () async {
      await window.record(OnboardingFailure<Object?>(
        OnboardingProblemCode.rateLimited,
        retryAvailableAt: clock.now.add(const Duration(minutes: 20)),
      ));
      expect(await window.blockedFor(), const Duration(minutes: 20));

      await window.record(OnboardingFailure<Object?>(
        OnboardingProblemCode.rateLimited,
        retryAvailableAt: clock.now.add(const Duration(days: 3)),
      ));
      expect(await window.blockedFor(), const Duration(hours: 1));
    });

    test('persists across a relaunch over the same store', () async {
      for (var i = 0; i < 6; i++) {
        await window.record(_rejected);
      }
      final relaunched = GoogleSignInRateWindow(store, now: clock.call);
      expect(await relaunched.blockedFor(), const Duration(hours: 1));
      expect(store.values.keys, [GoogleSignInRateWindow.storageKey]);
      expect(store.values.values.single, isNot(contains('@')));
    });

    test('corrupt data reads as empty; instants from the future are ignored',
        () async {
      await store.writeString(GoogleSignInRateWindow.storageKey, '{not json');
      expect(await window.blockedFor(), isNull);

      final future =
          clock.now.add(const Duration(hours: 2)).millisecondsSinceEpoch;
      await store.writeString(
        GoogleSignInRateWindow.storageKey,
        jsonEncode({
          'failures': List.filled(6, future),
          'blockedUntil':
              clock.now.add(const Duration(days: 1)).millisecondsSinceEpoch,
        }),
      );
      expect(await window.blockedFor(), isNull);
    });
  });

  group('GoogleSdkIdentityGateway with a window', () {
    test('a spent budget answers RateLimited without opening the picker',
        () async {
      final clock = _Clock();
      final window = GoogleSignInRateWindow(InMemoryLocalStore(), now: clock.call);
      final client = _TokenClient();
      final gateway = GoogleSdkIdentityGateway(client, window: window);

      expect(await gateway.signIn(), isA<GoogleSignInObtained>());
      for (var i = 0; i < 6; i++) {
        await window.record(_rejected);
      }
      final attempt = await gateway.signIn();
      expect(attempt, isA<GoogleSignInRateLimited>());
      expect((attempt as GoogleSignInRateLimited).retryAfter,
          const Duration(hours: 1));
      expect(client.calls, 1);
    });
  });

  group('DeviceIdStore', () {
    test('mints one UUID v4 in secure storage and keeps it across relaunches',
        () async {
      final secure = InMemorySecureStore();
      final local = InMemoryLocalStore();
      final first = await DeviceIdStore(secure, local).read();
      expect(isUuidV4(first), isTrue);
      expect(await DeviceIdStore(secure, local).read(), first);
      expect(secure.values[DeviceIdStore.storageKey], first);
      expect(local.values.containsKey(DeviceIdStore.storageKey), isFalse);
    });

    test('a corrupt stored value is replaced', () async {
      final secure = InMemorySecureStore({DeviceIdStore.storageKey: 'nope'});
      final local = InMemoryLocalStore({DeviceIdStore.installedKey: '1'});
      final id = await DeviceIdStore(secure, local).read();
      expect(isUuidV4(id), isTrue);
      expect(secure.values[DeviceIdStore.storageKey], id);
    });

    test('an id an earlier build kept in preferences moves over unchanged',
        () async {
      const legacy = '0f6d2c9e-4b1a-4c3d-9e8f-1a2b3c4d5e6f';
      final secure = InMemorySecureStore();
      final local = InMemoryLocalStore({DeviceIdStore.storageKey: legacy});
      expect(await DeviceIdStore(secure, local).read(), legacy);
      expect(secure.values[DeviceIdStore.storageKey], legacy);
      expect(local.values.containsKey(DeviceIdStore.storageKey), isFalse);
      expect(await DeviceIdStore(secure, local).read(), legacy);
    });

    test('a reinstall is a new device, even when the Keychain kept the old id',
        () async {
      const left = '0f6d2c9e-4b1a-4c3d-9e8f-1a2b3c4d5e6f';
      // iOS: secure storage survived the uninstall, preferences did not.
      final secure = InMemorySecureStore({DeviceIdStore.storageKey: left});
      final id = await DeviceIdStore(secure, InMemoryLocalStore()).read();
      expect(id, isNot(left));
      expect(isUuidV4(id), isTrue);
    });

    test('version and variant bits are set', () {
      final random = Random(7);
      for (var i = 0; i < 200; i++) {
        final id = uuidV4(random);
        expect(id[14], '4');
        expect('89ab'.contains(id[19]), isTrue);
        expect(isUuidV4(id), isTrue);
      }
    });
  });

  group('POST /auth/google over HTTP', () {
    late List<http.Request> requests;
    late int status;
    late ProviderContainer container;
    late InMemoryLocalStore local;
    late InMemorySecureStore secure;

    setUp(() {
      requests = [];
      status = 409;
      local = InMemoryLocalStore();
      secure = InMemorySecureStore();
      final authState = SecureAuthStateStore(InMemorySecureStore());
      final api = ApiClient(
        vault: TokenVault(authState),
        origin: 'http://leader.test',
        client: MockClient((request) async {
          requests.add(request);
          if (status == 429) {
            return _json(429, {
              'error': {'code': 'rate_limited', 'retryAfterSeconds': 1200},
            }, {
              'retry-after': '1200'
            });
          }
          return _json(status, {
            'error': {'code': 'auth_method_link_required'},
          });
        }),
      );
      container = ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(local),
        secureStoreProvider.overrideWithValue(secure),
        onboardingRepositoryProvider.overrideWith(
          (ref) => HttpOnboardingRepository(api, authState,
              deviceId: ref.watch(deviceIdStoreProvider).read),
        ),
      ]);
      addTearDown(container.dispose);
    });

    Future<Result<Object?>> google(String token) => container
        .read(onboardingControllerProvider.notifier)
        .signInWithGoogle(GoogleIdentityAssertion(token));

    test('sends this install\'s X-Device-Id on the Google request only',
        () async {
      await google('a.b.c');
      await container
          .read(onboardingRepositoryProvider)
          .signInWithPassword(email: 'a@b.co', password: 'x');

      final id = secure.values[DeviceIdStore.storageKey]!;
      expect(isUuidV4(id), isTrue);
      expect(requests.first.url.path, '/api/v1/auth/google');
      expect(requests.first.headers['X-Device-Id'], id);
      expect(requests.last.url.path, '/api/v1/auth/sign-in');
      expect(requests.last.headers.containsKey('X-Device-Id'), isFalse);
    });

    test('each refusal is counted; the seventh press is held on the device',
        () async {
      final window = container.read(googleSignInRateWindowProvider);
      for (var i = 0; i < 5; i++) {
        await google('t$i.b.c');
      }
      expect(await window.blockedFor(), isNull);
      await google('t5.b.c');
      expect(await window.blockedFor(), isNotNull);
      expect(requests, hasLength(6));
    });

    test('a server 429 is held for its Retry-After', () async {
      status = 429;
      final result = await google('a.b.c');
      expect(onboardingErrorKindOf(result), OnboardingErrorKind.rateLimited);
      final wait =
          await container.read(googleSignInRateWindowProvider).blockedFor();
      expect(wait, isNotNull);
      expect(wait!.inSeconds, inInclusiveRange(1190, 1200));
    });

    test('a device id that cannot be read never blocks the sign-in', () async {
      final authState = SecureAuthStateStore(InMemorySecureStore());
      final seen = <http.Request>[];
      final repo = HttpOnboardingRepository(
        ApiClient(
          vault: TokenVault(authState),
          origin: 'http://leader.test',
          client: MockClient((request) async {
            seen.add(request);
            return _json(401, {
              'error': {'code': 'google_assertion_rejected'},
            });
          }),
        ),
        authState,
        deviceId: () async => throw StateError('storage unavailable'),
      );
      await repo.signInWithGoogle(const GoogleIdentityAssertion('a.b.c'),
          idempotencyKey: 'k');
      expect(seen.single.headers.containsKey('X-Device-Id'), isFalse);
    });
  });
}
