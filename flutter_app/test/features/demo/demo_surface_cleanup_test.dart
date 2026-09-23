import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/customer_demo.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/demo/data/demo_control_plane.dart';
import 'package:mtm/features/demo/domain/demo_policy.dart';
import 'package:mtm/features/demo/presentation/demo_trial_bar.dart';
import 'package:mtm/features/platform/presentation/platform_demo_page.dart';
import 'package:mtm/features/shell/main_shell.dart';
import 'package:mtm/l10n/strings.dart';

import '../platform/platform_harness.dart';

/// **Where Demo is allowed to appear, and where it is not.**
///
/// The product has exactly two Demo surfaces: one entry for a user, and one
/// management screen for a Super Admin. Everything else that once carried Demo
/// copy — a holding page, a summary card, a second availability control — is
/// gone, and this file is what stops one growing back.
void main() {
  final now = DateTime.utc(2026, 9, 16, 12);

  Future<GoRouter> bootDemo(WidgetTester tester, {double width = 400}) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(customerDemoUser, overrides: [
      clockProvider.overrideWithValue(() => now),
      demoControlPlaneSeedProvider.overrideWithValue(const []),
      sessionAccessOverrideProvider
          .overrideWith((ref) => const SessionAccess(demo: DemoMode.active)),
    ]);
    return bootPlatform(tester, container, width: width, height: 1200);
  }

  group('inside a trial', () {
    testWidgets('the trial says what it is, once, and carries the exit',
        (tester) async {
      final router = await bootDemo(tester);

      // One bar, above the shell — not a paragraph repeated per screen.
      expect(find.byType(DemoTrialBar), findsOneWidget);
      expect(find.text(S.demoTrialNotice), findsOneWidget);
      expect(find.byKey(const Key('demo-exit')), findsOneWidget);

      // Still exactly one after moving around the application.
      router.go('/detachment');
      await settlePlatform(tester);
      expect(find.text(S.demoTrialNotice), findsOneWidget);
      expect(find.byType(MainShell), findsOneWidget);
    });

    testWidgets('Settings offers no Demo policy control of any kind',
        (tester) async {
      final router = await bootDemo(tester);
      router.go('/more');
      await settlePlatform(tester);

      // The hub ends a trial; it never administers one.
      expect(find.text(S.customerDemoExit), findsWidgets);
      expect(find.byKey(const Key('settings-pricing-row')), findsOneWidget);
      for (final policyControl in [
        S.platformDemoTitle,
        S.platformDemoAvailability,
        S.platformDemoDuration,
        S.platformDemoTerminateAll,
        S.platformDemoCleanExpired,
      ]) {
        expect(find.text(policyControl), findsNothing, reason: policyControl);
      }
      expect(find.byType(SwitchListTile), findsNothing);
    });

    testWidgets('the refused destinations are refused, and the rest are not',
        (tester) async {
      final router = await bootDemo(tester);

      // A trial is not an account and owns no organisation: security, the
      // device list, the real sync queue, the org record, the plan, Simple
      // Admin management and the conflict inbox are all bounced.
      for (final blocked in [
        '/more/security',
        '/more/sessions',
        '/more/sync',
        '/more/organization',
        '/more/plan',
        '/more/simple-admins',
        '/needs-review',
      ]) {
        router.go(blocked);
        await settlePlatform(tester);
        expect(locationOf(router), isNot(blocked), reason: blocked);
      }

      // Platform is not merely hidden from the trial — it is another product
      // surface entirely, and the Demo management screen lives inside it.
      router.go(PlatformDemoPage.routePath);
      await settlePlatform(tester);
      expect(find.byType(PlatformDemoPage), findsNothing);
      expect(find.text(S.platformDemoTitle), findsNothing);

      // And the modules the trial exists to demonstrate still open.
      for (final allowed in ['/home', '/detachment', '/workshop', '/more']) {
        router.go(allowed);
        await settlePlatform(tester);
        expect(locationOf(router), allowed, reason: allowed);
      }
    });
  });

  group('the obsolete Demo surfaces are gone', () {
    testWidgets('no holding screen stands between the trial and the app',
        (tester) async {
      final router = await bootDemo(tester);

      // The trial opens on the application, not on a page describing one.
      expect(locationOf(router), '/home');
      expect(find.byType(MainShell), findsOneWidget);
    });

    testWidgets('Login offers no Demo action', (tester) async {
      ignoreKnownTenantComplaints();
      final container = platformContainer(null, overrides: [
        clockProvider.overrideWithValue(() => now),
        demoControlPlaneSeedProvider.overrideWithValue(const []),
      ]);
      final router = await bootPlatform(tester, container, height: 1200);
      router.go('/login');
      await settlePlatform(tester);

      // The trial is offered once, to a verified unlinked identity, on the
      // onboarding chooser — never as a button beside the password field.
      expect(find.text(S.customerDemoAction), findsNothing);
      expect(find.text(S.customerDemoExit), findsNothing);
      expect(find.byType(DemoTrialBar), findsNothing);
    });
  });

  group('the Super Admin side', () {
    testWidgets('holds every Demo control, and the tenant app holds none',
        (tester) async {
      ignoreKnownTenantComplaints();
      final container = platformContainer(superAdmin, overrides: [
        clockProvider.overrideWithValue(() => now),
        demoControlPlaneSeedProvider.overrideWithValue(const []),
      ]);
      final router = await bootPlatform(tester, container, height: 1400);

      router.go(PlatformDemoPage.routePath);
      await settlePlatform(tester);

      expect(find.byType(PlatformDemoPage), findsOneWidget);
      // One availability switch in the whole product, and it is this one.
      expect(find.byKey(const Key('platform-demo-enabled')), findsOneWidget);
      expect(
        find.byKey(const Key('platform-demo-duration-value')),
        findsOneWidget,
      );
      // A Super Admin is not in a trial, so the trial bar is not above them.
      expect(find.byType(DemoTrialBar), findsNothing);
    });

    testWidgets('a tenant administrator is offered no Demo control',
        (tester) async {
      ignoreKnownTenantComplaints();
      final container = platformContainer(fullTenantAdmin, overrides: [
        clockProvider.overrideWithValue(() => now),
        demoControlPlaneSeedProvider.overrideWithValue(const []),
      ]);
      final router = await bootPlatform(tester, container, height: 1200);
      router.go('/more');
      await settlePlatform(tester);

      expect(find.text(S.platformDemoTitle), findsNothing);
      expect(find.text(S.platformDemoAvailability), findsNothing);
      // `DemoTrialBar` is in the shell's tree for every session — it collapses
      // to nothing outside a trial — so the claim is that it renders nothing,
      // not that the widget is absent.
      expect(find.text(S.demoTrialNotice), findsNothing);
      expect(find.byKey(const Key('demo-exit')), findsNothing);
      // The strongest tenant session still cannot reach the control plane.
      expect(
        container.read(demoControlPlaneProvider.notifier).setEnabled(false),
        isA<Failure<DemoPolicy>>(),
      );
    });
  });
}
