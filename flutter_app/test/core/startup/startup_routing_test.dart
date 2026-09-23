import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/startup/startup_destination.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/auth/presentation/dev_session_states_page.dart';
import 'package:mtm/features/auth/presentation/login_page.dart';
import 'package:mtm/features/platform/presentation/platform_shell.dart';
import 'package:mtm/features/auth/presentation/startup_page.dart';
import 'package:mtm/features/auth/presentation/status_pages.dart';
import 'package:mtm/features/admin_management/presentation/simple_admin_management_page.dart';
import 'package:mtm/features/home/presentation/home_page.dart';
import 'package:mtm/features/shell/main_shell.dart';
import 'package:mtm/l10n/strings.dart';

/// Point 3 — what the router does with the classifier's answer.
///
/// The classifier's own table is checked in `startup_classifier_test.dart`
/// without a widget tree. This file is about the half that only a real router
/// can prove: that a deep link cannot get round the decision, that a surface
/// change actually closes the previous shell, and that no protected screen is
/// built before the decision exists.
void main() {
  void ignoreKnownPreexistingComplaints() {
    final inherited = FlutterError.onError;
    FlutterError.onError = (details) {
      final report = details.toString();
      if (report.contains('overflowed') &&
          (report.contains('glass_bottom_nav.dart') ||
              report.contains('login_page.dart'))) {
        return;
      }
      if (report.contains('ListTile background color or ink splashes')) return;
      inherited?.call(details);
    };
    addTearDown(() => FlutterError.onError = inherited);
  }

  String at(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  /// Every tenant operational route a deep link could name.
  const tenantRoutes = [
    '/home',
    '/detachment',
    '/detachment-groups',
    '/detachment/d_dam_central/team',
    '/detachment/d_dam_central/shifts',
    '/detachment/d_dam_central/storage',
    '/detachment/d_dam_central/stats',
    '/workshop',
    '/more',
    '/more/org',
    '/more/organization',
    '/more/plan',
    '/more/profile',
    '/search',
    '/needs-review',
  ];

  group('no protected content is built before the decision exists', () {
    testWidgets('a cold start renders the startup surface, not a tenant screen',
        (tester) async {
      // The session read never lands, which is the first frames of every cold
      // start held still.
      final container = _container(_never());
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      expect(at(router), StartupPage.location);
      expect(find.byType(StartupPage), findsOneWidget);
      expect(find.byType(HomePage), findsNothing);
      expect(find.byType(MainShell), findsNothing,
          reason: 'the tenant shell must not be built during a restore');
      expect(find.byType(LoginPage), findsNothing,
          reason: 'nor may the app claim nobody is signed in yet');
    });

    testWidgets('a deep link during the restore does not open either',
        (tester) async {
      final container = _container(_never());
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      for (final location in [
        '/home',
        '/more/security',
        PlatformShell.location
      ]) {
        router.go(location);
        await _settle(tester);
        expect(at(router), StartupPage.location, reason: location);
      }
      expect(find.byType(MainShell), findsNothing);
    });

    testWidgets('the restore resolving moves the app on its own',
        (tester) async {
      final answer = _Answer(null);
      final container = _container(null, answer: answer);
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);
      expect(at(router), StartupPage.location);

      answer.value = const Success<AuthUser?>(_mainAdmin);
      container.invalidate(currentUserResultProvider);
      await _settle(tester);

      expect(at(router), '/home');
      expect(find.byType(StartupPage), findsNothing);
    });
  });

  group('super_admin never enters the tenant application', () {
    testWidgets('every tenant deep link lands on a platform-safe destination',
        (tester) async {
      final container = _container(const Success<AuthUser?>(_superAdmin));
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      expect(at(router), PlatformShell.location);

      for (final location in tenantRoutes) {
        router.go(location);
        await _settle(tester);
        expect(at(router), PlatformShell.location, reason: location);
        expect(find.byType(MainShell), findsNothing, reason: location);
      }
    });

    testWidgets('the tenant shell is never instantiated for it',
        (tester) async {
      final container = _container(const Success<AuthUser?>(_superAdmin));
      await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      // §32/§33: rejection happens at the route, before the shell — and
      // therefore before any tenant repository the shell's screens read.
      expect(find.byType(MainShell), findsNothing);
      expect(find.byType(HomePage), findsNothing);
      expect(find.byType(PlatformShell), findsOneWidget);
    });
  });

  group('tenant roles never enter the platform', () {
    for (final (label, user) in [
      ('main_admin', _mainAdmin),
      ('admin', _simpleAdmin),
    ]) {
      testWidgets('$label is turned around at /platform', (tester) async {
        final container = _container(Success<AuthUser?>(user));
        final router = await _boot(tester, container,
            ignoreNoise: ignoreKnownPreexistingComplaints);

        expect(at(router), '/home');

        router.go(PlatformShell.location);
        await _settle(tester);
        expect(at(router), '/home');
        expect(find.byType(PlatformShell), findsNothing);
      });
    }

    testWidgets('and so is every startup-only holding location',
        (tester) async {
      final container = _container(const Success<AuthUser?>(_mainAdmin));
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      for (final location in startupStatusPages.keys) {
        router.go(location);
        await _settle(tester);
        expect(at(router), '/home', reason: location);
      }
    });
  });

  group('Simple Admin management route', () {
    testWidgets('Main Admin with admin.manage can open it', (tester) async {
      final container = _container(const Success<AuthUser?>(_mainAdmin));
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      router.go(SimpleAdminManagementPage.routePath);
      await _settle(tester);
      expect(at(router), SimpleAdminManagementPage.routePath);
      expect(find.byType(SimpleAdminManagementPage), findsOneWidget);
    });

    testWidgets('Simple Admin without admin.manage is returned home',
        (tester) async {
      final container = _container(const Success<AuthUser?>(_simpleAdmin));
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      router.go(SimpleAdminManagementPage.routePath);
      await _settle(tester);
      expect(at(router), '/home');
      expect(find.byType(SimpleAdminManagementPage), findsNothing);
    });
  });

  group('a tenant account with no assigned access', () {
    testWidgets('lands on the designed state and cannot leave it sideways',
        (tester) async {
      final container = _container(const Success<AuthUser?>(_bareTenant));
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      expect(at(router), StartupDestination.tenantNoAccess.location);
      expect(find.byType(AccessNotAssignedPage), findsOneWidget);
      expect(find.byType(MainShell), findsNothing);

      for (final location in tenantRoutes) {
        router.go(location);
        await _settle(tester);
        expect(at(router), StartupDestination.tenantNoAccess.location,
            reason: location);
      }
    });
  });

  group('lifecycle states are reachable only through the classifier', () {
    for (final (label, access, expected) in [
      (
        'a revoked account',
        const SessionAccess(account: AccountStatus.revoked),
        StartupDestination.accountRevoked,
      ),
      (
        'a suspended account',
        const SessionAccess(account: AccountStatus.suspended),
        StartupDestination.accountSuspended,
      ),
      (
        'a suspended tenant',
        const SessionAccess(tenant: SaasTenantStatus.suspended),
        StartupDestination.tenantSuspended,
      ),
      (
        'a deletion-pending tenant',
        const SessionAccess(tenant: SaasTenantStatus.deletionPending),
        StartupDestination.tenantDeletionPending,
      ),
      (
        'a deleted tenant',
        const SessionAccess(tenant: SaasTenantStatus.deleted),
        StartupDestination.tenantDeleted,
      ),
      (
        'an unlinked account',
        const SessionAccess(account: AccountStatus.pendingSetup),
        StartupDestination.firstTimeSetup,
      ),
      (
        'an expired demo',
        const SessionAccess(demo: DemoMode.expired),
        StartupDestination.demoExpired,
      ),
    ]) {
      testWidgets('$label is held on its own screen', (tester) async {
        final user = access.demo == DemoMode.none ? _mainAdmin : _customerDemo;
        final container = _container(
          Success<AuthUser?>(user),
          access: access,
        );
        final router = await _boot(tester, container,
            ignoreNoise: ignoreKnownPreexistingComplaints);

        expect(at(router), expected.location);
        expect(find.byType(MainShell), findsNothing);

        // A deep link into the tenant app, and into the platform, both fail.
        for (final location in ['/home', '/more', PlatformShell.location]) {
          router.go(location);
          await _settle(tester);
          expect(at(router), expected.location, reason: location);
        }
      });
    }
  });

  group('an active demo runs the tenant application', () {
    // The Customer Demo trial is the product, read from an isolated
    // workspace: it keeps the route it asks for, exactly as a tenant session
    // does, and is refused only the locations that belong to a real account
    // or would have to reach production.
    testWidgets('it opens the shell and moves between modules', (tester) async {
      final container = _container(
        const Success<AuthUser?>(_customerDemo),
        access: const SessionAccess(demo: DemoMode.active),
      );
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      expect(at(router), '/home');
      expect(find.byType(MainShell), findsOneWidget);

      for (final location in ['/workshop', '/detachment', '/more']) {
        router.go(location);
        await _settle(tester);
        expect(at(router), location, reason: location);
      }
    });

    testWidgets('the platform and the blocked account screens are refused',
        (tester) async {
      final container = _container(
        const Success<AuthUser?>(_customerDemo),
        access: const SessionAccess(demo: DemoMode.active),
      );
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      router.go(PlatformShell.location);
      await _settle(tester);
      expect(at(router), '/home');

      for (final blocked in [
        '/more/security',
        '/more/sync',
        '/more/organization',
        '/more/plan',
        '/more/simple-admins',
        '/needs-review',
      ]) {
        router.go(blocked);
        await _settle(tester);
        expect(at(router), '/more', reason: blocked);
      }
    });
  });

  group('an unsupported access state fails closed at the router', () {
    // The Point 3 follow-up, proved where it matters: a value this build
    // cannot interpret must not let *either* product surface open, and the
    // person must land on a screen that says so rather than on a blank one.
    final unsupported = SessionAccess.unsupportedValue(
      AccessLifecycleField.accountStatus,
      'locked',
    );

    for (final (label, user, forbidden) in [
      ('a tenant admin', _mainAdmin, '/home'),
      ('the platform owner', _superAdmin, PlatformShell.location),
    ]) {
      testWidgets('$label reaches neither $forbidden nor anything else',
          (tester) async {
        final container = _container(
          Success<AuthUser?>(user),
          access: unsupported,
        );
        final router = await _boot(tester, container,
            ignoreNoise: ignoreKnownPreexistingComplaints);

        expect(
          at(router),
          StartupDestination.unsupportedAccessState.location,
          reason: label,
        );
        expect(find.byType(AccessUnsupportedPage), findsOneWidget);
        expect(find.byType(MainShell), findsNothing);
        expect(find.byType(PlatformShell), findsNothing);

        // And no deep link gets round it — including into the platform
        // subtree, which is more than one location since Point 4.
        for (final location in [
          '/home',
          '/more',
          PlatformShell.location,
          '${PlatformShell.location}/tenants',
          '${PlatformShell.location}/more/security',
        ]) {
          router.go(location);
          await _settle(tester);
          expect(at(router), StartupDestination.unsupportedAccessState.location,
              reason: location);
        }
      });
    }

    testWidgets('an unknown demo mode is refused too', (tester) async {
      // The sharpest case: a future restricted demo read as «not a demo» would
      // hand a demo session the real product.
      final container = _container(
        const Success<AuthUser?>(_mainAdmin),
        access: SessionAccess.unsupportedValue(
          AccessLifecycleField.demoMode,
          'read_only',
        ),
      );
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      expect(at(router), StartupDestination.unsupportedAccessState.location);
      expect(find.byType(MainShell), findsNothing);
    });

    testWidgets('a healthy session cannot sit on the screen either',
        (tester) async {
      // Startup-only, like every other blocked state: reaching it by link is
      // turned around.
      final container = _container(const Success<AuthUser?>(_mainAdmin));
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      router.go(StartupDestination.unsupportedAccessState.location!);
      await _settle(tester);
      expect(at(router), '/home');
    });
  });

  group('the router reacts to the session changing under it', () {
    testWidgets('signing out from deep inside the app returns to login',
        (tester) async {
      final answer = _Answer(const Success<AuthUser?>(_mainAdmin));
      final container = _container(null, answer: answer);
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      router.go('/more/security');
      await _settle(tester);
      expect(at(router), '/more/security');

      answer.value = const Success<AuthUser?>(null);
      container.invalidate(currentUserResultProvider);
      await _settle(tester);

      expect(at(router), '/login');
      expect(find.byType(MainShell), findsNothing);
    });

    testWidgets('a role change cannot retain the previous shell',
        (tester) async {
      final answer = _Answer(const Success<AuthUser?>(_mainAdmin));
      final container = _container(null, answer: answer);
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);
      expect(find.byType(MainShell), findsOneWidget);

      answer.value = const Success<AuthUser?>(_superAdmin);
      container.invalidate(currentUserResultProvider);
      await _settle(tester);

      expect(at(router), PlatformShell.location);
      expect(find.byType(MainShell), findsNothing);
      expect(find.byType(HomePage), findsNothing);
    });

    testWidgets('a grant narrowed to nothing closes the tenant app',
        (tester) async {
      final answer = _Answer(const Success<AuthUser?>(_mainAdmin));
      final container = _container(null, answer: answer);
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);
      expect(at(router), '/home');

      answer.value = const Success<AuthUser?>(_bareTenant);
      container.invalidate(currentUserResultProvider);
      await _settle(tester);

      expect(at(router), StartupDestination.tenantNoAccess.location);
      expect(find.byType(MainShell), findsNothing);
    });

    testWidgets('an expiry mid-session lands on the expired screen',
        (tester) async {
      final answer = _Answer(const Success<AuthUser?>(_mainAdmin));
      final container = _container(null, answer: answer);
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      answer.value =
          const Failure<AuthUser?>('gone', code: 'authentication_expired');
      container.invalidate(currentUserResultProvider);
      await _settle(tester);

      expect(at(router), '/session-expired');

      // And a deep link cannot bypass it.
      router.go('/home');
      await _settle(tester);
      expect(at(router), '/session-expired');
    });
  });

  group('the development state inspector', () {
    testWidgets('drives a real state screen through the real classifier',
        (tester) async {
      // §40: the states have no backend behind them, so this is how they are
      // looked at. It writes the override and the *router* decides — the
      // screen is never navigated to directly.
      final container = _container(const Success<AuthUser?>(_mainAdmin));
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      router.go(DevSessionStatesPage.location);
      await _settle(tester);
      expect(at(router), DevSessionStatesPage.location);
      expect(find.byType(MainShell), findsNothing,
          reason: 'a root route, not a shell branch');

      await tester.tap(find.text(S.devStatesAccountSuspended));
      await _settle(tester);

      expect(at(router), StartupDestination.accountSuspended.location);
      expect(find.byType(AccountSuspendedPage), findsOneWidget);
    });
  });

  group('the existing auth flows still work', () {
    testWidgets('a signed-out session may still complete a password reset',
        (tester) async {
      final container = _container(const Success<AuthUser?>(null));
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      for (final location in ['/forgot', '/otp', '/new-password']) {
        router.go(location);
        await _settle(tester);
        expect(at(router), location, reason: location);
      }
    });

    testWidgets('a signed-in tenant admin may still open MFA setup',
        (tester) async {
      final container = _container(const Success<AuthUser?>(_mainAdmin));
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      router.go('/mfa-setup');
      await _settle(tester);
      expect(at(router), '/mfa-setup');
    });

    testWidgets('an inconclusive session is left exactly where it asked',
        (tester) async {
      // Offline with nothing cached. Unchanged from before Point 3, and
      // deliberately so — see `StartupDestination.unresolved`.
      final container = _container(const Offline<AuthUser?>());
      final router = await _boot(tester, container,
          ignoreNoise: ignoreKnownPreexistingComplaints);

      router.go('/more/security');
      await _settle(tester);
      expect(at(router), '/more/security');
      expect(find.byType(LoginPage), findsNothing);
    });
  });
}

// -----------------------------------------------------------------------------

const _superAdmin = AuthUser(
  id: 'u_platform',
  name: 'مدير المنصة',
  email: 'nullmod.dev@gmail.com',
  role: AuthRole.superAdmin,
  saasTenantId: null,
  capabilities: Capabilities.none,
  orgName: 'MTM',
);

const _mainAdmin = AuthUser(
  id: 'u_main',
  name: 'مشرف',
  email: 'admin@mtm.org',
  role: AuthRole.mainAdmin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities(global: Cap.all),
  orgName: 'MTM',
);

const _simpleAdmin = AuthUser(
  id: 'u_simple',
  name: 'مشرف مفرزة',
  email: 'scoped@mtm.org',
  role: AuthRole.admin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities(scoped: {
    'd_dam_central': {Cap.detachmentView, Cap.memberView}
  }),
  orgName: 'MTM',
);

const _bareTenant = AuthUser(
  id: 'u_bare',
  name: 'حساب جديد',
  email: 'new@mtm.org',
  role: AuthRole.mainAdmin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities.none,
  orgName: 'MTM',
);

const _customerDemo = AuthUser(
  id: 'u_customer_demo',
  name: 'مساحة تجريبية',
  email: 'customer-demo@mtm.app',
  role: AuthRole.customerDemo,
  saasTenantId: null,
  capabilities: Capabilities.none,
  orgName: 'MTM Demo',
);

/// A session read that never completes — a cold start held at its first frame.
Future<Result<AuthUser?>> _never() => Completer<Result<AuthUser?>>().future;

class _Answer {
  _Answer(this.value);
  Result<AuthUser?>? value;
}

ProviderContainer _container(
  Object? fixed, {
  _Answer? answer,
  SessionAccess? access,
}) {
  final container = ProviderContainer(overrides: [
    currentUserResultProvider.overrideWith((ref) async {
      if (answer != null) {
        final value = answer.value;
        if (value == null) return _never();
        return value;
      }
      if (fixed is Future<Result<AuthUser?>>) return fixed;
      return fixed! as Result<AuthUser?>;
    }),
    sessionsProvider.overrideWith(
      (ref) async => const Success<List<Session>>([]),
    ),
    if (access != null) sessionAccessProvider.overrideWithValue(access),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<GoRouter> _boot(
  WidgetTester tester,
  ProviderContainer container, {
  required void Function() ignoreNoise,
}) async {
  ignoreNoise();
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final router = container.read(appRouterProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(PaletteId.medical),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await _settle(tester);
  return router;
}

/// Bounded pumps: the real screens boot behind the router and their mock
/// repositories answer after a simulated delay, so `pumpAndSettle` would
/// never return.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
}
