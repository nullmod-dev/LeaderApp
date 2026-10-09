import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/network/api_client.dart';
import 'package:mtm/core/network/token_vault.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/startup/startup_destination.dart';
import 'package:mtm/core/startup/startup_providers.dart';
import 'package:mtm/core/storage/local_store.dart';
import 'package:mtm/core/storage/secure_store.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/core/widgets/offline_banner.dart';
import 'package:mtm/features/auth/data/app_lock_controller.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/device_authenticator.dart';
import 'package:mtm/features/auth/data/full_session_snapshot_store.dart';
import 'package:mtm/features/auth/data/http_auth_repository.dart';
import 'package:mtm/features/auth/data/secure_auth_state_store.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/auth_repository.dart';
import 'package:mtm/features/auth/presentation/offline_copy_bar.dart';
import 'package:mtm/features/auth/presentation/startup_page.dart';
import 'package:mtm/features/auth/presentation/status_pages.dart';
import 'package:mtm/l10n/strings.dart';

/// The offline-session screens that were still missing after D2: the slow
/// launch line, the two launch-error screens, the shell's offline bar with its
/// 48-hour countdown and silent re-check, and the one shared sentence for an
/// action that needs the server.
http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

const _admin = AuthUser(
  id: 'acc-1',
  name: 'سارة',
  email: 'sara@leader.test',
  role: AuthRole.mainAdmin,
  saasTenantId: 'tenant-1',
  capabilities: Capabilities(global: Cap.all),
  orgName: 'فرق النبض',
);

class _Phone implements DeviceAuthenticator {
  @override
  bool get enabled => true;

  @override
  Future<DeviceUnlockOutcome> unlock({required String reason}) async =>
      DeviceUnlockOutcome.unlocked;
}

void main() {
  late InMemorySecureStore device;
  late DateTime now;
  late http.Response Function(http.Request) server;

  HttpAuthRepository launch() => HttpAuthRepository(
        ApiClient(
          vault: TokenVault(SecureAuthStateStore(device)),
          origin: 'http://leader.test',
          client: MockClient((request) async => server(request)),
        ),
        snapshots: FullSessionSnapshotStore(device),
        clock: () => now,
      );

  Future<void> holdSession(String sid) =>
      TokenVault(SecureAuthStateStore(device))
          .writeFull('access-$sid', 'refresh-$sid', sessionId: sid);

  void online() => server = (_) => _json(200, {
        'sessionId': 'sid-1',
        'user': _admin.toJson(),
        'access': {
          'accountStatus': 'active',
          'tenantStatus': 'active',
          'demoMode': 'none',
          'mfaRequired': false,
        },
      });

  void offline() =>
      server = (_) => throw const SocketException('no route to host');

  setUp(() {
    device = InMemorySecureStore();
    now = DateTime.utc(2026, 10, 9, 9);
  });

  group('why a launch with nothing stored failed', () {
    LaunchFailure failureOf(Result<AuthUser?> result) {
      final c = ProviderContainer(overrides: [
        currentUserResultProvider.overrideWith((ref) async => result),
      ]);
      addTearDown(c.dispose);
      return c.read(launchFailureProvider);
    }

    test('maps each read to the screen that can explain it', () async {
      final cases = <Result<AuthUser?>, LaunchFailure>{
        const Offline<AuthUser?>(): LaunchFailure.network,
        const Failure<AuthUser?>('', code: 'network'): LaunchFailure.network,
        const Failure<AuthUser?>('', code: 'server'): LaunchFailure.server,
        // The phone's own storage is neither, and names nothing.
        const Failure<AuthUser?>('', code: AuthRepository.deviceStorageCode):
            LaunchFailure.none,
        // A copy opened offline is a session, not a failure.
        const Offline<AuthUser?>(cached: _admin): LaunchFailure.none,
        const Success<AuthUser?>(_admin): LaunchFailure.none,
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        final c = ProviderContainer(overrides: [
          currentUserResultProvider.overrideWith((ref) async => key),
        ]);
        addTearDown(c.dispose);
        await c.read(currentUserResultProvider.future);
        expect(c.read(launchFailureProvider), value, reason: '$key');
      }
      // Before the read lands nothing is named.
      expect(failureOf(const Offline<AuthUser?>()), LaunchFailure.none);
    });

    test('a 5xx with no copy is the server, whatever code its body carried',
        () async {
      await holdSession('sid-1');
      server = (_) => _json(503, {
            'error': {'code': 'internal_error'}
          });
      final r = await launch().currentUser();
      expect((r as Failure).code, 'server');
    });

    test('an unreachable server with no copy is the network', () async {
      await holdSession('sid-1');
      offline();
      expect(await launch().currentUser(), isA<Offline<AuthUser?>>());
    });

    test('the launch-error screens never sit behind the app lock', () async {
      await holdSession('sid-1');
      offline();
      final c = ProviderContainer(overrides: [
        secureStoreProvider.overrideWithValue(device),
        localStoreProvider.overrideWithValue(InMemoryLocalStore()),
        authRepositoryProvider.overrideWithValue(launch()),
        deviceAuthenticatorProvider.overrideWithValue(_Phone()),
        clockProvider.overrideWithValue(() => now),
      ]);
      addTearDown(c.dispose);
      expect(c.read(appLockControllerProvider).phase, AppLockPhase.locked);
      await c.read(currentUserResultProvider.future);

      expect(c.read(startupDestinationProvider),
          StartupDestination.launchOffline);
      expect(c.read(appLockControllerProvider).phase, AppLockPhase.open);
    });
  });

  group('the launch-error screen', () {
    testWidgets('a retry that still cannot reach the server says so',
        (tester) async {
      var reads = 0;
      final c = ProviderContainer(overrides: [
        currentUserResultProvider.overrideWith((ref) async {
          reads++;
          return const Offline<AuthUser?>();
        }),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.medical),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: LaunchErrorPage(failure: LaunchFailure.network),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(S.launchOfflineTitle), findsOneWidget);
      expect(find.text(S.offlineSessionStillOffline), findsNothing);

      await tester.tap(find.byKey(const Key('launch-error-retry')));
      await tester.pumpAndSettle();
      expect(reads, 2, reason: 'the retry re-reads the session');
      expect(find.text(S.offlineSessionStillOffline), findsOneWidget);
    });

    testWidgets('the server case names the server, not the phone',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentUserResultProvider.overrideWith(
              (ref) async => const Failure<AuthUser?>('', code: 'server')),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(PaletteId.teal),
          home: const LaunchErrorPage(failure: LaunchFailure.server),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text(S.launchServerErrorTitle), findsOneWidget);
      expect(find.text(S.launchServerErrorBody), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    });
  });

  group('the shell offline bar', () {
    Future<void> pumpBar(WidgetTester tester, ProviderContainer c) async {
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.medical),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: Column(children: [OfflineCopyBar()])),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('shows on the stored copy, with the hours left in the last 48',
        (tester) async {
      await holdSession('sid-1');
      online();
      await launch().currentUser();
      // Six days and one hour after the last server contact: 23 hours left.
      offline();
      now = now.add(const Duration(days: 6, hours: 1));

      final c = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(launch()),
        clockProvider.overrideWithValue(() => now),
      ]);
      addTearDown(c.dispose);
      await tester.runAsync(() => c.read(currentUserResultProvider.future));
      await pumpBar(tester, c);

      expect(find.byKey(const Key('offline-banner')), findsOneWidget);
      expect(find.text(S.offlineCopyBanner), findsOneWidget);
      expect(find.text('ينتهي الدخول دون اتصال خلال ٢٣ ساعة'), findsOneWidget);
    });

    testWidgets('no countdown while more than 48 hours are left',
        (tester) async {
      final c = ProviderContainer(overrides: [
        currentUserResultProvider
            .overrideWith((ref) async => const Offline<AuthUser?>(cached: _admin)),
      ]);
      addTearDown(c.dispose);
      await pumpBar(tester, c);
      expect(find.text(S.offlineCopyBanner), findsOneWidget);
      expect(find.byKey(const Key('offline-banner-detail')), findsNothing);
    });

    testWidgets('re-reads the session every minute while offline, silently',
        (tester) async {
      var reads = 0;
      var answer = const Offline<AuthUser?>(cached: _admin) as Result<AuthUser?>;
      final c = ProviderContainer(overrides: [
        currentUserResultProvider.overrideWith((ref) async {
          reads++;
          return answer;
        }),
      ]);
      addTearDown(c.dispose);
      await pumpBar(tester, c);
      expect(reads, 1);
      expect(find.byKey(const Key('offline-banner')), findsOneWidget);

      await tester.pump(OfflineCopyBar.recheckEvery);
      await tester.pump();
      expect(reads, 2);
      // Still offline: nothing changed on screen.
      expect(find.byKey(const Key('offline-banner')), findsOneWidget);

      // Back online: the bar closes on the next re-read, and stops asking.
      answer = const Success<AuthUser?>(_admin);
      await tester.pump(OfflineCopyBar.recheckEvery);
      await tester.pumpAndSettle();
      expect(reads, 3);
      expect(find.byKey(const Key('offline-banner')), findsNothing);
      await tester.pump(OfflineCopyBar.recheckEvery * 3);
      expect(reads, 3);
    });

    testWidgets('sits above both shells, and only offline', (tester) async {
      Future<GoRouter> boot(Result<AuthUser?> result) async {
        final c = ProviderContainer(overrides: [
          currentUserResultProvider.overrideWith((ref) async => result),
          sessionsProvider.overrideWith(
              (ref) async => const Success<List<Session>>([])),
        ]);
        addTearDown(c.dispose);
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final router = c.read(appRouterProvider);
        await tester.pumpWidget(UncontrolledProviderScope(
          container: c,
          child: MaterialApp.router(
            routerConfig: router,
            theme: AppTheme.light(PaletteId.medical),
            builder: (context, child) => Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }
        return router;
      }

      final inherited = FlutterError.onError;
      FlutterError.onError = (details) {
        final report = details.toString();
        if (report.contains('overflowed') &&
            report.contains('glass_bottom_nav.dart')) {
          return;
        }
        if (report.contains('ListTile background color or ink splashes')) {
          return;
        }
        inherited?.call(details);
      };
      addTearDown(() => FlutterError.onError = inherited);

      await boot(const Offline<AuthUser?>(cached: _admin));
      expect(find.byKey(const Key('offline-banner')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await boot(const Success<AuthUser?>(_admin));
      expect(find.byKey(const Key('offline-banner')), findsNothing);
    });
  });

  group('the launch screen on a slow server', () {
    testWidgets('names the slow connection after three seconds',
        (tester) async {
      await holdSession('sid-1');
      // The read never answers within the test: a slow server.
      server = (_) => throw const SocketException('slow');
      final c = ProviderContainer(overrides: [
        authRepositoryProvider.overrideWithValue(launch()),
      ]);
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: StartupPage()),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(S.startupSlowNetwork), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(S.startupSlowNetwork), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a local build never claims the network is slow',
        (tester) async {
      await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(home: StartupPage()),
      ));
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(S.startupSlowNetwork), findsNothing);
      expect(find.text(S.startupRestoring), findsOneWidget);
    });
  });

  test('every offline action says the same sentence', () {
    final text = actionNeedsConnectionSnackBar.content as Text;
    expect(text.data, S.actionNeedsConnection);
    expect(S.actionNeedsConnection, 'يحتاج هذا الإجراء إلى اتصال بالإنترنت');
  });
}
