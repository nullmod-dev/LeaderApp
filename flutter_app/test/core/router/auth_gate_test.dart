import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/presentation/login_page.dart';
import 'package:mtm/features/auth/presentation/session_expired_page.dart';
import 'package:mtm/features/settings/presentation/security_page.dart';
import 'package:mtm/l10n/strings.dart';

/// The router's auth gate: what an unauthenticated session may reach, and
/// what happens the moment a session stops being valid while the app is open.
///
/// All of this is invisible until it is wrong, and every failure mode is
/// serious — a protected screen still reachable after sign-out, a redirect
/// loop, a blank page, or a cold start bounced to the login screen because
/// the session read had not landed yet.
void main() {
  /// The same two pre-existing debug complaints `settings_hub_test.dart`
  /// already tolerates for this layout: the floating bottom nav overflowing a
  /// narrow test surface, and `ListTile` inside a decorated settings card.
  /// Both predate this file and are not what it is about.
  void ignoreKnownPreexistingComplaints() {
    final inherited = FlutterError.onError;
    FlutterError.onError = (details) {
      final report = details.toString();
      if (report.contains('overflowed') &&
          (report.contains('glass_bottom_nav.dart') ||
              report.contains('login_page.dart'))) {
        return;
      }
      if (report.contains('ListTile background color or ink splashes')) {
        return;
      }
      inherited?.call(details);
    };
    addTearDown(() => FlutterError.onError = inherited);
  }

  /// Bounded pumps rather than `pumpAndSettle`.
  ///
  /// The real router boots the real screens, and every mock repository behind
  /// them answers after a simulated 400–800 ms — chained, in the dashboard's
  /// case. `pumpAndSettle` never returns while one of those is outstanding,
  /// so time is advanced in fixed steps instead, far enough to drain them.
  /// The same approach `settings_hub_test.dart` already takes.
  Future<void> settle(WidgetTester tester) => _settleBounded(tester);

  /// Where the router actually ended up.
  String at(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  testWidgets('a signed-in session reaches its protected screens',
      (tester) async {
    final container = _container(const Success<AuthUser?>(_me));
    final router = await _boot(tester, container,
        ignoreNoise: ignoreKnownPreexistingComplaints);

    router.go('/more/security');
    await settle(tester);

    expect(at(router), '/more/security');
    expect(find.byType(SecurityPage), findsOneWidget);
  });

  testWidgets(
      'a definitively signed-out session cannot reach one, however '
      'it asks — deep link included', (tester) async {
    final container = _container(const Success<AuthUser?>(null));
    final router = await _boot(tester, container,
        ignoreNoise: ignoreKnownPreexistingComplaints);

    for (final location in [
      '/more/security',
      '/more',
      '/home',
      '/needs-review'
    ]) {
      router.go(location);
      await settle(tester);
      expect(at(router), '/login', reason: '$location got past the gate');
    }
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('an expired session lands on its own screen, not the login form',
      (tester) async {
    final container = _container(
      const Failure<AuthUser?>('gone', code: 'authentication_expired'),
    );
    final router = await _boot(tester, container,
        ignoreNoise: ignoreKnownPreexistingComplaints);

    router.go('/more/security');
    await settle(tester);

    expect(at(router), '/session-expired');
    expect(find.byType(SessionExpiredPage), findsOneWidget);
    expect(find.text(S.sessionExpiredSub), findsOneWidget);
    expect(find.text(S.signIn), findsOneWidget);
  });

  testWidgets('an unknown session is not a signed-out one', (tester) async {
    // A cold start whose session read has not landed, and an offline device
    // with nothing cached, both look like this. Bouncing either to the login
    // screen would break the app for exactly the field conditions it is
    // built for.
    final container = _container(const Offline<AuthUser?>());
    final router = await _boot(tester, container,
        ignoreNoise: ignoreKnownPreexistingComplaints);

    router.go('/more/security');
    await settle(tester);

    expect(at(router), '/more/security');
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('the gate does not loop on the screens it redirects to',
      (tester) async {
    // A redirect that fires again on its own destination is an infinite loop
    // and takes the app down. Both destinations are public pages, so both
    // must be terminal.
    final signedOut = _container(const Success<AuthUser?>(null));
    final loggedOutRouter = await _boot(tester, signedOut,
        at: '/login', ignoreNoise: ignoreKnownPreexistingComplaints);
    expect(at(loggedOutRouter), '/login');
    expect(find.byType(LoginPage), findsOneWidget);

    final expired = _container(
      const Failure<AuthUser?>('gone', code: 'authentication_expired'),
    );
    final expiredRouter = await _boot(tester, expired,
        at: '/session-expired', ignoreNoise: ignoreKnownPreexistingComplaints);
    expect(at(expiredRouter), '/session-expired');
    expect(find.byType(SessionExpiredPage), findsOneWidget);
  });

  testWidgets(
      'a session that expires while Security is open takes the app '
      'out of the authenticated stack', (tester) async {
    // The exact shape of "the session was invalidated server-side while the
    // admin was looking at their sessions".
    final answer = _Answer(const Success<AuthUser?>(_me));
    final container = _container(null, answer: answer);
    final router = await _boot(tester, container,
        ignoreNoise: ignoreKnownPreexistingComplaints);

    router.go('/more/security');
    await settle(tester);
    expect(find.byType(SecurityPage), findsOneWidget);

    answer.value =
        const Failure<AuthUser?>('gone', code: 'authentication_expired');
    container.invalidate(currentUserResultProvider);
    await settle(tester);

    expect(at(router), '/session-expired');
    expect(find.byType(SecurityPage), findsNothing);

    // And it stays shut: a preserved branch stack or a deep link is no way
    // back in.
    router.go('/more/security');
    await settle(tester);
    expect(at(router), '/session-expired');
  });
}

const _me = AuthUser(
  id: 'u_1',
  name: 'مشرف',
  email: 'admin@mtm.org',
  role: AuthRole.mainAdmin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities(global: Cap.all),
  orgName: 'MTM',
);

/// A session answer a test can change mid-flight.
class _Answer {
  _Answer(this.value);
  Result<AuthUser?> value;
}

ProviderContainer _container(Result<AuthUser?>? fixed, {_Answer? answer}) {
  final container = ProviderContainer(
    overrides: [
      // Answered synchronously, without the mock repository's simulated
      // latency: these tests are about the redirect, not about loading.
      currentUserResultProvider.overrideWith(
        (ref) async => answer?.value ?? fixed!,
      ),
      // The session list is never the subject here; a screen that fetched it
      // for real would leave a pending timer behind every pump.
      sessionsProvider.overrideWith(
        (ref) async => const Success<List<Session>>([]),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<GoRouter> _boot(
  WidgetTester tester,
  ProviderContainer container, {
  String? at,
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
  await _settleBounded(tester);
  if (at != null) {
    router.go(at);
    await _settleBounded(tester);
  }
  return router;
}

Future<void> _settleBounded(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
}
