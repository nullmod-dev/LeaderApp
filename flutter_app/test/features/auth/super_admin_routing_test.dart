import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/presentation/login_page.dart';
import 'package:mtm/features/platform/presentation/platform_shell.dart';
import 'package:mtm/features/home/presentation/home_page.dart';

/// Point 2 — where a `super_admin` goes, and what an invalid account does.
///
/// The product rule being defended: **Super Admin is not a very powerful team
/// admin.** The tempting shortcut — give it the tenant grant and send it to
/// `/home` — would look fine on screen and be wrong about the product, so the
/// tests below assert the opposite outcome directly: it never lands on a
/// tenant screen, and it never acquires tenant scope on the way.
///
/// **Point 3 landed and these expectations survived it**, which is the useful
/// thing this file now says: the routing underneath was replaced wholesale by
/// `startupDestinationProvider`, and a Super Admin still ends up in exactly the
/// same place. The one expectation that changed is the invalid-account pair
/// below — a refused payload used to read as `signedOut` and now has its own
/// gate value and its own screen. The broader cross-surface guarantees are in
/// `test/core/startup/startup_routing_test.dart`.
///
/// **Point 4 landed and they survived it too.** `/platform` stopped being a
/// one-action holding page and became a four-branch shell; every expectation
/// below is about the *boundary*, so the only thing that changed is the widget
/// the finder names. The shell's own behaviour is covered in
/// `test/features/platform/`.

void main() {
  /// The same pre-existing debug complaints the other router tests tolerate:
  /// the floating bottom nav on a narrow test surface, `ListTile` inside a
  /// decorated settings card, and the login form's own overflow. All predate
  /// this file.
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

  testWidgets('a Super Admin never lands in the tenant application',
      (tester) async {
    final container = _container(DemoPersona.superAdmin.user);
    final router = await _boot(tester, container,
        ignoreNoise: ignoreKnownPreexistingComplaints);

    // The app's own initial location is `/home`; it does not stay there.
    expect(at(router), PlatformShell.location);
    expect(find.byType(PlatformShell), findsOneWidget);
    expect(find.byType(HomePage), findsNothing);

    // And it stays out: a deep link into the tenant application is turned
    // around, not merely un-navigated-to.
    for (final location in const [
      '/home',
      '/detachment-groups',
      '/more/profile',
      '/more/org',
      '/more/organization',
      '/more/plan',
    ]) {
      router.go(location);
      await _settle(tester);
      expect(at(router), PlatformShell.location, reason: location);
    }
  });

  testWidgets('the Super Admin session carries no tenant scope',
      (tester) async {
    final container = _container(DemoPersona.superAdmin.user);
    await _boot(tester, container,
        ignoreNoise: ignoreKnownPreexistingComplaints);

    // Being held outside the tenant app is one guarantee; holding nothing
    // inside it is the other, and neither is allowed to depend on the other.
    expect(container.read(capabilitiesProvider), Capabilities.none);
    expect(container.read(adminViewProvider).isFull, isFalse);
    expect(container.read(adminViewProvider).namedDetachmentIds, isEmpty);
  });

  testWidgets('a tenant admin cannot reach the platform surface',
      (tester) async {
    final container = _container(DemoPersona.mainAdmin.user);
    final router = await _boot(tester, container,
        ignoreNoise: ignoreKnownPreexistingComplaints);

    expect(at(router), '/home');

    router.go(PlatformShell.location);
    await _settle(tester);
    expect(at(router), '/home');
    expect(find.byType(PlatformShell), findsNothing);
  });

  testWidgets('a Simple Admin reaches the tenant application unchanged',
      (tester) async {
    // The regression that would be easy to ship: a role clause that catches
    // more than the platform account.
    final container = _container(DemoPersona.simpleAdmin.user);
    final router = await _boot(tester, container,
        ignoreNoise: ignoreKnownPreexistingComplaints);

    expect(at(router), '/home');
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('a signed-out session is sent to login, not to the platform',
      (tester) async {
    final container = _container(null);
    final router = await _boot(tester, container,
        ignoreNoise: ignoreKnownPreexistingComplaints);

    expect(at(router), '/login');

    router.go(PlatformShell.location);
    await _settle(tester);
    expect(at(router), '/login');
    expect(find.byType(LoginPage), findsOneWidget);
  });

  group('an invalid account is refused, and reads as no session', () {
    test('a main_admin with no SaasTenant is not signed in', () async {
      final container = _container(const AuthUser(
        id: 'u',
        name: 'مشرف',
        email: 'admin@mtm.org',
        role: AuthRole.mainAdmin,
        saasTenantId: null,
        capabilities: Capabilities(global: Cap.all),
        orgName: 'MTM',
      ));

      expect(await container.read(currentUserProvider.future), isNull);
      // Point 3: a refused payload is its own gate value. It used to read as
      // `signedOut`, which sent the person to a login form that would hand
      // back the same broken account; it now fails closed onto the invalid
      // session screen. Nothing downstream sees the account either way.
      expect(container.read(authGateProvider), AuthGate.invalid);
      // Nothing was repaired into a usable session: the full grant that
      // arrived with the broken account is not honoured either.
      expect(container.read(capabilitiesProvider), Capabilities.none);
    });

    test('a super_admin carrying a SaasTenant is not signed in', () async {
      final container = _container(const AuthUser(
        id: 'u',
        name: 'مدير المنصة',
        email: 'nullmod.dev@gmail.com',
        role: AuthRole.superAdmin,
        saasTenantId: 'saas_1',
        capabilities: Capabilities.none,
        orgName: 'MTM',
      ));

      expect(await container.read(currentUserProvider.future), isNull);
      expect(container.read(authGateProvider), AuthGate.invalid);
      expect(container.read(authRoleProvider), isNull);
    });
  });
}

ProviderContainer _container(AuthUser? user) {
  final container = ProviderContainer(overrides: [
    // Answered synchronously, without the mock repository's latency: these
    // tests are about the redirect, not about loading.
    currentUserResultProvider.overrideWith((ref) async => Success(user)),
    sessionsProvider.overrideWith(
      (ref) async => const Success<List<Session>>([]),
    ),
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

/// Bounded pumps rather than `pumpAndSettle`: the real screens boot behind
/// the router and their mock repositories answer after a simulated delay.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
}
