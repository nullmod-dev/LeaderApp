import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mtm/core/network/api_client.dart';
import 'package:mtm/core/network/token_vault.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/storage/secure_store.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/device_trust_repository.dart';
import 'package:mtm/features/auth/data/http_auth_repository.dart';
import 'package:mtm/features/auth/data/secure_auth_state_store.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/auth_repository.dart';
import 'package:mtm/features/auth/domain/device_trust.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/auth/presentation/account_secured_page.dart';
import 'package:mtm/features/auth/presentation/new_device_page.dart';
import 'package:mtm/features/auth/presentation/sign_out_action.dart';
import 'package:mtm/features/settings/presentation/my_devices_page.dart';
import 'package:mtm/l10n/strings.dart';

/// Device trust, D4: the approval prompt, My devices, the page after "No",
/// and the sign-out wording that depends on the offline window.
void main() {
  late _FakeDevices devices;
  late _FakeAuth auth;

  setUp(() {
    devices = _FakeDevices();
    auth = _FakeAuth();
  });

  final pending = SessionAccess(pendingDeviceApprovals: [
    PendingDeviceApproval(
      id: 'dv_new',
      label: 'Android',
      signedInAt: DateTime.utc(2026, 10, 8, 16),
    ),
  ]);

  Future<GoRouter> pump(
    WidgetTester tester, {
    required String at,
    SessionAccess access = SessionAccess.normal,
    ThemeData? theme,
    double width = 390,
    double scale = 1,
    AuthRepository? authRepository,
  }) async {
    tester.view.physicalSize = Size(width * 3, 2600);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = GoRouter(initialLocation: at, routes: [
      for (final path in ['/home', '/forgot', '/login'])
        GoRoute(
            path: path, builder: (_, __) => Scaffold(body: Text('at $path'))),
      GoRoute(path: '/new-device', builder: (_, __) => const NewDevicePage()),
      GoRoute(
          path: AccountSecuredPage.location,
          builder: (_, __) => const AccountSecuredPage()),
      GoRoute(
          path: '/more/security/devices',
          builder: (_, __) => const MyDevicesPage()),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sessionAccessOverrideProvider.overrideWith((ref) => access),
        deviceTrustRepositoryProvider.overrideWithValue(devices),
        authRepositoryProvider.overrideWithValue(authRepository ?? auth),
      ],
      child: MaterialApp.router(
        theme: theme ?? AppTheme.light(PaletteId.medical),
        routerConfig: router,
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  String at(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  group('/new-device', () {
    testWidgets('names the device and when it signed in', (tester) async {
      await pump(tester, at: '/new-device', access: pending);
      expect(find.text(S.newDeviceApprovalTitle), findsOneWidget);
      expect(find.text('Android'), findsOneWidget);
      expect(find.byKey(const Key('new-device-yes')), findsOneWidget);
      expect(find.byKey(const Key('new-device-no')), findsOneWidget);
    });

    testWidgets('Yes approves that device and leaves', (tester) async {
      final router = await pump(tester, at: '/new-device', access: pending);
      await tester.tap(find.byKey(const Key('new-device-yes')));
      await tester.pumpAndSettle();
      expect(devices.approved, ['dv_new']);
      expect(find.text(S.newDeviceApproved), findsOneWidget);
      expect(at(router), '/home');
    });

    testWidgets('Yes while the limit is full points at My devices',
        (tester) async {
      devices.approveResult =
          const Failure('', code: trustedDeviceLimitCode);
      final router = await pump(tester, at: '/new-device', access: pending);
      await tester.tap(find.byKey(const Key('new-device-yes')));
      await tester.pumpAndSettle();
      expect(find.text(S.newDeviceLimitReached), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('new-device-open-devices')));
      await tester.tap(find.byKey(const Key('new-device-open-devices')));
      await tester.pumpAndSettle();
      expect(find.byType(MyDevicesPage), findsOneWidget);
      expect(router.canPop(), isTrue);
    });

    testWidgets('No asks first; cancelling sends nothing', (tester) async {
      await pump(tester, at: '/new-device', access: pending);
      await tester.tap(find.byKey(const Key('new-device-no')));
      await tester.pumpAndSettle();
      expect(find.text(S.newDeviceDenyBody), findsOneWidget);
      await tester.tap(find.text(S.cancel));
      await tester.pumpAndSettle();
      expect(devices.denied, isEmpty);
    });

    testWidgets('No: the session ends here too, then the reset is offered',
        (tester) async {
      final router = await pump(tester, at: '/new-device', access: pending);
      await tester.tap(find.byKey(const Key('new-device-no')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-device-deny-confirm')));
      await tester.pumpAndSettle();
      expect(devices.denied, ['dv_new']);
      expect(auth.signedOut, isTrue);
      expect(at(router), '/account-secured?reset=1');
      expect(find.text(S.accountSecuredPasswordBody), findsOneWidget);
      await tester.tap(find.byKey(const Key('account-secured-next')));
      await tester.pumpAndSettle();
      expect(at(router), '/forgot');
    });

    testWidgets('No on a Google-only account signs in again instead',
        (tester) async {
      devices.denyResult =
          const Success(DenyDeviceOutcome(passwordReset: false));
      final router = await pump(tester, at: '/new-device', access: pending);
      await tester.tap(find.byKey(const Key('new-device-no')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-device-deny-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(S.accountSecuredGoogleBody), findsOneWidget);
      await tester.tap(find.byKey(const Key('account-secured-next')));
      await tester.pumpAndSettle();
      expect(at(router), '/login');
    });

    testWidgets('nothing waiting is a quiet state with a way back',
        (tester) async {
      await pump(tester, at: '/new-device');
      expect(find.text(S.newDeviceNoneTitle), findsOneWidget);
      expect(find.byKey(const Key('new-device-none-back')), findsOneWidget);
    });

    testWidgets('fits 320dp at 1.6× text, dark', (tester) async {
      await pump(tester,
          at: '/new-device',
          access: pending,
          width: 320,
          scale: 1.6,
          theme: AppTheme.dark(PaletteId.medical));
      expect(tester.takeException(), isNull);
    });
  });

  group('My devices', () {
    testWidgets('this device first, the count, and remove on the others only',
        (tester) async {
      await pump(tester, at: '/more/security/devices');
      expect(find.text(S.deviceThisDevice), findsOneWidget);
      expect(find.byKey(const Key('my-devices-count')), findsOneWidget);
      expect(find.byKey(const Key('my-device-remove-dv_this')), findsNothing);
      expect(find.byKey(const Key('my-device-remove-dv_old')), findsOneWidget);
      expect(find.text(S.deviceStatusRestricted), findsOneWidget);
    });

    testWidgets('remove asks, then removes and says so', (tester) async {
      await pump(tester, at: '/more/security/devices');
      await tester.tap(find.byKey(const Key('my-device-remove-dv_old')));
      await tester.pumpAndSettle();
      expect(find.text(S.deviceRemoveBody), findsOneWidget);
      await tester.tap(find.byKey(const Key('my-device-remove-confirm')));
      await tester.pumpAndSettle();
      expect(devices.removed, ['dv_old']);
      expect(find.text(S.deviceRemoved), findsOneWidget);
    });

    testWidgets('a restricted device says it cannot remove, and offers no button',
        (tester) async {
      await pump(
        tester,
        at: '/more/security/devices',
        access: const SessionAccess(
          deviceRestriction:
              DeviceRestriction(reason: DeviceRestrictionReason.deviceLimit),
        ),
      );
      expect(find.byKey(const Key('my-devices-restricted-note')), findsOneWidget);
      expect(find.text(S.deviceRemove), findsNothing);
    });

    testWidgets('offline is a state, not a blank', (tester) async {
      devices.listResult = const Offline();
      await pump(tester, at: '/more/security/devices');
      expect(find.byKey(const Key('my-devices-offline')), findsOneWidget);
    });

    testWidgets('fits 320dp at 1.6× text, dark', (tester) async {
      await pump(tester,
          at: '/more/security/devices',
          width: 320,
          scale: 1.6,
          theme: AppTheme.dark(PaletteId.medical));
      expect(tester.takeException(), isNull);
    });
  });

  group('sign-out wording', () {
    Future<void> openDialog(WidgetTester tester, AuthRepository repository,
        {bool offline = false}) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          if (offline)
            currentUserResultProvider
                .overrideWith((ref) async => const Offline<AuthUser?>()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.medical),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Consumer(
              builder: (context, ref, _) {
                // The app's router keeps the session read alive; so does this.
                ref.watch(currentUserResultProvider);
                return Scaffold(
                  body: TextButton(
                    onPressed: () => confirmAndSignOut(context, ref),
                    child: const Text('out'),
                  ),
                );
              },
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('out'));
      await tester.pumpAndSettle();
    }

    HttpAuthRepository backend() => HttpAuthRepository(ApiClient(
          vault: TokenVault(SecureAuthStateStore(InMemorySecureStore())),
          origin: 'http://leader.test',
          client: MockClient((_) async => http.Response('', 204)),
        ));

    testWidgets('a backend build says the offline copy goes too',
        (tester) async {
      await openDialog(tester, backend());
      expect(find.text(S.signOutOfflineCopyNote), findsOneWidget);
    });

    testWidgets('offline it adds that the server session runs out by itself',
        (tester) async {
      await openDialog(tester, backend(), offline: true);
      expect(
          find.text(
              '${S.signOutOfflineCopyNote} ${S.signOutOfflineServerNote}'),
          findsOneWidget);
    });

    testWidgets('a build with no offline copy says nothing about it',
        (tester) async {
      await openDialog(tester, auth);
      expect(find.byKey(const Key('sign-out-offline-note')), findsNothing);
    });
  });
}

class _FakeDevices implements DeviceTrustRepository {
  final approved = <String>[];
  final denied = <String>[];
  final removed = <String>[];
  Result<void> approveResult = const Success(null);
  Result<DenyDeviceOutcome> denyResult =
      const Success(DenyDeviceOutcome(passwordReset: true));
  Result<AccountDevices>? listResult;

  @override
  Future<Result<AccountDevices>> listDevices() async =>
      listResult ??
      Success(AccountDevices(limit: 3, devices: [
        AccountDevice(
          id: 'dv_old',
          label: 'حاسوب المكتب',
          status: AccountDeviceStatus.trusted,
          current: false,
          restricted: true,
          restrictedUntil: DateTime.utc(2026, 10, 8, 22),
          signedInAt: DateTime.utc(2026, 10, 8, 16),
          lastSeenAt: DateTime.utc(2026, 10, 8, 16),
        ),
        AccountDevice(
          id: 'dv_this',
          label: 'Android',
          status: AccountDeviceStatus.trusted,
          current: true,
          restricted: false,
          signedInAt: DateTime.utc(2026, 9, 1),
          lastSeenAt: DateTime.utc(2026, 10, 8, 17),
        ),
      ]));

  @override
  Future<Result<void>> approve(String deviceId) async {
    approved.add(deviceId);
    return approveResult;
  }

  @override
  Future<Result<DenyDeviceOutcome>> deny(String deviceId) async {
    denied.add(deviceId);
    return denyResult;
  }

  @override
  Future<Result<void>> remove(String deviceId) async {
    removed.add(deviceId);
    return const Success(null);
  }
}

class _FakeAuth implements AuthRepository {
  bool signedOut = false;

  @override
  Future<Result<AuthUser?>> currentUser() async => const Success(null);

  @override
  Future<Result<void>> signOut() async {
    signedOut = true;
    return const Success(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
