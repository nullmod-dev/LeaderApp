import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/about/presentation/about_page.dart';
import 'package:mtm/features/home/presentation/home_page.dart';
import 'package:mtm/features/platform/domain/platform_area.dart';
import 'package:mtm/features/platform/domain/platform_report_models.dart';
import 'package:mtm/features/platform/presentation/platform_more_page.dart';
import 'package:mtm/features/platform/presentation/platform_main_admin_page.dart';
import 'package:mtm/features/platform/presentation/platform_main_admin_replace_page.dart';
import 'package:mtm/features/platform/presentation/platform_operations_page.dart';
import 'package:mtm/features/platform/presentation/platform_operations_routes.dart';
import 'package:mtm/features/platform/presentation/platform_overview_page.dart';
import 'package:mtm/features/platform/presentation/platform_reports_catalogue_page.dart';
import 'package:mtm/features/platform/presentation/platform_shell.dart';
import 'package:mtm/features/platform/presentation/platform_tenants_page.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_limits_page.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_features_page.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_routes.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_subscription_page.dart';
import 'package:mtm/features/settings/presentation/profile_page.dart';
import 'package:mtm/features/settings/presentation/security_page.dart';
import 'package:mtm/features/shell/main_shell.dart';

import 'platform_harness.dart';

/// Point 4 — the boundary between the two product surfaces, now that the
/// platform one is a route *subtree* rather than a single page.
///
/// Point 3 proved the boundary held for one location. The regression this file
/// exists to catch is the obvious way to break it while adding three more:
/// a guard written as `here == '/platform'` refuses `/platform/tenants` to the
/// Super Admin and permits it to everybody else — both halves wrong, and
/// neither visible from `/platform` alone.

void main() {
  /// Every location the platform surface owns, including a nested one.
  final platformRoutes = [
    for (final area in PlatformArea.values) area.route,
    ...PlatformOperationsRoutes.all,
    PlatformOperationsRoutes.commerceOffer,
    '${PlatformOperationsRoutes.commerceOffer}/offer_seed_try2',
    PlatformOperationsRoutes.commerceCoupon,
    '${PlatformOperationsRoutes.commerceCoupon}/coupon_seed_public',
    PlatformOperationsRoutes.accessRequest,
    PlatformOperationsRoutes.report(PlatformReportType.subscriptions),
    PlatformOperationsRoutes.report(PlatformReportType.usageLimits),
    PlatformOperationsRoutes.report(PlatformReportType.featureAvailability),
    PlatformOperationsRoutes.report(PlatformReportType.platformActivity),
    '${PlatformArea.more.route}/profile',
    '${PlatformArea.more.route}/security',
    '${PlatformArea.more.route}/themes',
    '${PlatformArea.more.route}/about',
    SaasTenantRoutes.subscription('saas_hilal'),
    SaasTenantRoutes.limits('saas_hilal'),
    SaasTenantRoutes.features('saas_hilal'),
    SaasTenantRoutes.mainAdmin('saas_hilal'),
    SaasTenantRoutes.mainAdminReplace('saas_hilal'),
  ];

  const tenantRoutes = [
    '/home',
    '/detachment',
    '/detachment-groups',
    '/workshop',
    '/more',
    '/more/org',
    '/more/organization',
    '/more/plan',
    '/more/profile',
    '/more/sync',
    '/search',
    '/needs-review',
    '/notifications',
  ];

  group('a Super Admin gets the platform shell and only that', () {
    testWidgets('the launch lands on /platform inside PlatformShell',
        (tester) async {
      final router = await bootPlatform(tester, platformContainer(superAdmin));

      expect(locationOf(router), PlatformShell.location);
      expect(find.byType(PlatformShell), findsOneWidget);
      expect(find.byType(PlatformOverviewPage), findsOneWidget);
      expect(find.byType(MainShell), findsNothing);
      expect(find.byType(HomePage), findsNothing);
    });

    testWidgets('every platform location resolves, root and nested alike',
        (tester) async {
      final router = await bootPlatform(tester, platformContainer(superAdmin));

      for (final location in platformRoutes) {
        router.go(location);
        await settlePlatform(tester);
        expect(locationOf(router), location, reason: location);
        expect(find.byType(PlatformShell), findsOneWidget, reason: location);
      }
    });

    testWidgets('a direct deep link into a nested platform page opens it',
        (tester) async {
      // Not reached by tapping through the shell: the app is entered and the
      // link is followed, which is the restored-stack and external-link case.
      final router = await bootPlatform(tester, platformContainer(superAdmin));

      router.go('${PlatformArea.more.route}/security');
      await settlePlatform(tester);

      expect(locationOf(router), '${PlatformArea.more.route}/security');
      expect(find.byType(SecurityPage), findsOneWidget);
      expect(find.byType(PlatformShell), findsOneWidget,
          reason: 'a nested platform page keeps the platform navigation');
    });

    testWidgets('Point 7 deep links stay inside the platform shell',
        (tester) async {
      final router = await bootPlatform(tester, platformContainer(superAdmin));

      router.go(SaasTenantRoutes.subscription('saas_hilal'));
      await settlePlatform(tester);
      expect(find.byType(SaasTenantSubscriptionPage), findsOneWidget);
      expect(find.byType(PlatformShell), findsOneWidget);

      router.go(SaasTenantRoutes.limits('saas_hilal'));
      await settlePlatform(tester);
      expect(find.byType(SaasTenantLimitsPage), findsOneWidget);
      expect(find.byType(PlatformShell), findsOneWidget);

      router.go(SaasTenantRoutes.features('saas_hilal'));
      await settlePlatform(tester);
      expect(find.byType(SaasTenantFeaturesPage), findsOneWidget);
      expect(find.byType(PlatformShell), findsOneWidget);
    });

    testWidgets('Point 14B Main Admin routes stay inside the platform shell',
        (tester) async {
      final router = await bootPlatform(tester, platformContainer(superAdmin));

      router.go(SaasTenantRoutes.mainAdmin('saas_hilal'));
      await settlePlatform(tester);
      expect(find.byType(PlatformMainAdminPage), findsOneWidget);
      expect(find.byType(PlatformShell), findsOneWidget);

      router.go(SaasTenantRoutes.mainAdminReplace('saas_hilal'));
      await settlePlatform(tester);
      expect(find.byType(PlatformMainAdminReplacePage), findsOneWidget);
      expect(find.byType(PlatformShell), findsOneWidget);
    });

    testWidgets('it is still turned around at every tenant route',
        (tester) async {
      ignoreKnownTenantComplaints();
      final router = await bootPlatform(tester, platformContainer(superAdmin));

      for (final location in tenantRoutes) {
        router.go(location);
        await settlePlatform(tester);
        expect(locationOf(router), PlatformShell.location, reason: location);
        expect(find.byType(MainShell), findsNothing, reason: location);
      }
    });

    testWidgets('it may still finish an authentication errand it started',
        (tester) async {
      // The Security screen it shares offers MFA enrolment and a password
      // reset. Both are public routes; a platform session that was bounced off
      // them would be looking at two rows that do nothing.
      final router = await bootPlatform(tester, platformContainer(superAdmin));

      for (final location in ['/mfa-setup', '/forgot']) {
        router.go(location);
        await settlePlatform(tester);
        expect(locationOf(router), location, reason: location);
      }

      // But not the sign-in form: a signed-in account has no business there.
      router.go('/login');
      await settlePlatform(tester);
      expect(locationOf(router), PlatformShell.location);
    });
  });

  group('a tenant role reaches no part of the platform subtree', () {
    for (final (label, user) in [
      ('main_admin', mainAdmin),
      ('admin', simpleAdmin),
      ('a main_admin holding every key', fullTenantAdmin),
    ]) {
      testWidgets('$label is refused every /platform location', (tester) async {
        ignoreKnownTenantComplaints();
        final router = await bootPlatform(tester, platformContainer(user));
        expect(locationOf(router), '/home');

        for (final location in platformRoutes) {
          router.go(location);
          await settlePlatform(tester);
          expect(locationOf(router), '/home', reason: location);
          expect(find.byType(PlatformShell), findsNothing, reason: location);
        }
      });
    }

    testWidgets('holding Cap.all changes nothing — role selects the surface',
        (tester) async {
      // The single most important negative in this file. Platform access is
      // not a very large capability grant, and a session that held every key
      // in `Cap` must still be refused, because none of those keys is about
      // the platform at all (`CAPABILITIES.md` §5b).
      ignoreKnownTenantComplaints();
      final router =
          await bootPlatform(tester, platformContainer(fullTenantAdmin));

      router.go('${PlatformArea.more.route}/profile');
      await settlePlatform(tester);
      expect(locationOf(router), '/home');
    });
  });

  group('branch navigation behaves', () {
    testWidgets('each area opens its own page', (tester) async {
      final router = await bootPlatform(tester, platformContainer(superAdmin));

      router.go(PlatformArea.tenants.route);
      await settlePlatform(tester);
      expect(find.byType(PlatformTenantsPage), findsOneWidget);

      router.go(PlatformArea.operations.route);
      await settlePlatform(tester);
      expect(find.byType(PlatformOperationsPage), findsOneWidget);

      router.go(PlatformArea.more.route);
      await settlePlatform(tester);
      expect(find.byType(PlatformMorePage), findsOneWidget);
    });

    testWidgets('a branch keeps where it was left', (tester) async {
      // The scenario `§13` names: drill into an area, leave it, come back and
      // find it as you left it.
      final router = await bootPlatform(tester, platformContainer(superAdmin));

      router.go('${PlatformArea.more.route}/profile');
      await settlePlatform(tester);
      expect(find.byType(ProfilePage), findsOneWidget);

      router.go(PlatformArea.tenants.route);
      await settlePlatform(tester);
      expect(find.byType(PlatformTenantsPage), findsOneWidget);

      // Back to the branch through its root, the way the navigation control
      // does it — the stack inside it should still be standing.
      final shell = tester.widget<PlatformShell>(find.byType(PlatformShell));
      shell.navigationShell.goBranch(PlatformArea.more.branchIndex);
      await settlePlatform(tester);

      expect(locationOf(router), '${PlatformArea.more.route}/profile');
      expect(find.byType(ProfilePage), findsOneWidget);
    });

    testWidgets('a row opens its page and the back gesture returns',
        (tester) async {
      // Tapped the way the operator does, not navigated to. Asserted on the
      // *pages*, not on `currentConfiguration.uri`: go_router leaves that at
      // the branch root for an imperative `push`, on this shell and on the
      // tenant one alike, so a URI assertion here would be testing go_router's
      // bookkeeping rather than the app's back behaviour.
      final router = await bootPlatform(tester, platformContainer(superAdmin));

      router.go(PlatformArea.more.route);
      await settlePlatform(tester);

      await tester.tap(find.byKey(const Key('platform-more-about')));
      await settlePlatform(tester);
      expect(find.byType(AboutPage), findsOneWidget);
      expect(find.byType(PlatformShell), findsOneWidget,
          reason: 'a pushed platform page stays inside the platform shell');
      expect(router.canPop(), isTrue);

      router.pop();
      await settlePlatform(tester);

      expect(find.byType(AboutPage), findsNothing);
      expect(find.byType(PlatformMorePage), findsOneWidget);
      expect(locationOf(router), PlatformArea.more.route);
      // And no loop: the redirect does not immediately move it again.
      await settlePlatform(tester);
      expect(locationOf(router), PlatformArea.more.route);
    });

    testWidgets('the shell does not bounce between /platform and startup',
        (tester) async {
      // The loop `§33` warns about. Two settles after arriving: if the
      // redirect and the classifier disagreed, the location would keep moving.
      final router = await bootPlatform(tester, platformContainer(superAdmin));
      final first = locationOf(router);
      await settlePlatform(tester);
      await settlePlatform(tester);
      expect(locationOf(router), first);
      expect(first, PlatformShell.location);
    });
  });

  group('the route tree agrees with the domain model', () {
    test('every area claims its own location and no other', () {
      for (final area in PlatformArea.values) {
        expect(PlatformArea.forLocation(area.route), area, reason: area.name);
      }
      expect(
        PlatformArea.forLocation('${PlatformArea.more.route}/security'),
        PlatformArea.more,
      );
      // The overview owns `/platform` exactly — it must not swallow the other
      // three, whose routes all start with it.
      expect(
        PlatformArea.forLocation(PlatformArea.tenants.route),
        isNot(PlatformArea.overview),
      );
      expect(PlatformArea.forLocation('/home'), isNull);
      expect(PlatformArea.forLocation('/more'), isNull);
    });

    test(
        'Point 13 report routes are recognized as Operations, root and '
        'child alike', () {
      expect(
        PlatformArea.forLocation(PlatformOperationsRoutes.reports),
        PlatformArea.operations,
      );
      expect(
        PlatformArea.forLocation(
          PlatformOperationsRoutes.report(PlatformReportType.subscriptions),
        ),
        PlatformArea.operations,
      );
      expect(
        PlatformArea.forLocation('${PlatformOperationsRoutes.reports}/bogus'),
        PlatformArea.operations,
      );
    });

    test('branch index and declaration order are the same number', () {
      for (var i = 0; i < PlatformArea.values.length; i++) {
        expect(PlatformArea.ofBranch(i).branchIndex, i);
      }
    });
  });

  group('Point 13 — Platform Reports routing', () {
    testWidgets(
        'the catalogue and every report type resolve for a '
        'Super Admin', (tester) async {
      final router = await bootPlatform(tester, platformContainer(superAdmin));

      router.go(PlatformOperationsRoutes.reports);
      await settlePlatform(tester);
      expect(find.byType(PlatformReportsCataloguePage), findsOneWidget);

      for (final type in [
        PlatformReportType.subscriptions,
        PlatformReportType.usageLimits,
        PlatformReportType.featureAvailability,
        PlatformReportType.platformActivity,
      ]) {
        router.go(PlatformOperationsRoutes.report(type));
        await settlePlatform(tester);
        expect(locationOf(router), PlatformOperationsRoutes.report(type));
        expect(find.byType(PlatformShell), findsOneWidget, reason: type.wire);
      }
    });

    testWidgets('an unknown report type renders a safe state, not a loop',
        (tester) async {
      final router = await bootPlatform(tester, platformContainer(superAdmin));

      router.go('${PlatformOperationsRoutes.reports}/not_a_real_report');
      await settlePlatform(tester);

      expect(
        locationOf(router),
        '${PlatformOperationsRoutes.reports}/not_a_real_report',
      );
      expect(find.byKey(const Key('report-unsupported')), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-unsupported-back')));
      await settlePlatform(tester);
      expect(locationOf(router), PlatformOperationsRoutes.reports);
      expect(find.byType(PlatformReportsCataloguePage), findsOneWidget);
    });
  });
}
