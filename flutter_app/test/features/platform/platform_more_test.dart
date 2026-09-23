import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/about/presentation/about_page.dart';
import 'package:mtm/features/platform/domain/platform_area.dart';
import 'package:mtm/features/platform/presentation/platform_more_page.dart';
import 'package:mtm/features/platform/presentation/platform_shell.dart';
import 'package:mtm/features/organization/presentation/organization_page.dart';
import 'package:mtm/features/organization/presentation/plan_page.dart';
import 'package:mtm/features/settings/presentation/profile_page.dart';
import 'package:mtm/features/settings/presentation/security_page.dart';
import 'package:mtm/features/settings/presentation/themes_and_performance_page.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

/// Point 4 — Platform More, the Super Admin's own account screen, and the data
/// boundary underneath both.
///
/// The three things this file is here to stop, in order of how much damage
/// each would do:
///
///  1. **A tenant repository built on the platform surface** (`§16`). Nothing
///     would look wrong; the leak is invisible until the day one of those
///     repositories is a network call scoped to a `saasTenantId` this account
///     does not have.
///  2. **A tenant settings row on the platform hub** (`§26`, `§29`) — the
///     organisation record, the sync outbox, tenant notification preferences.
///  3. **The account screen describing the platform owner as a narrow tenant
///     admin** (`§27`), which is what reporting its empty tenant grant would
///     amount to.

void main() {
  group('the platform surface builds no tenant repository', () {
    testWidgets('not on the landing surface', (tester) async {
      final watch = TenantRepositoryWatch();
      final router = await bootPlatform(
        tester,
        platformContainer(superAdmin, watch: watch),
      );

      expect(locationOf(router), PlatformShell.location);
      expect(watch.built, isEmpty);
    });

    testWidgets('not on any destination, nor on any page inside More',
        (tester) async {
      final watch = TenantRepositoryWatch();
      final router = await bootPlatform(
        tester,
        platformContainer(superAdmin, watch: watch),
      );

      for (final location in [
        for (final area in PlatformArea.values) area.route,
        '${PlatformArea.more.route}/profile',
        '${PlatformArea.more.route}/security',
        '${PlatformArea.more.route}/themes',
        '${PlatformArea.more.route}/eye-protect',
        '${PlatformArea.more.route}/about',
      ]) {
        router.go(location);
        await settlePlatform(tester);
        expect(watch.built, isEmpty, reason: location);
      }
    });

    testWidgets('not even after a tenant deep link is refused', (tester) async {
      // The refusal happens at the redirect, before the shell — so the tenant
      // screens behind those links are never built, and neither is anything
      // they would have read.
      final watch = TenantRepositoryWatch();
      final router = await bootPlatform(
        tester,
        platformContainer(superAdmin, watch: watch),
      );

      for (final location in ['/home', '/detachment', '/more', '/workshop']) {
        router.go(location);
        await settlePlatform(tester);
      }

      expect(locationOf(router), PlatformShell.location);
      expect(watch.built, isEmpty);
    });
  });

  group('Platform More offers the allowlist and nothing else', () {
    Future<void> openMore(WidgetTester tester) async {
      final router = await bootPlatform(tester, platformContainer(superAdmin));
      router.go(PlatformArea.more.route);
      await settlePlatform(tester);
    }

    testWidgets('the four safe destinations are all there', (tester) async {
      await openMore(tester);

      expect(find.byType(PlatformMorePage), findsOneWidget);
      for (final key in const [
        'platform-more-profile',
        'platform-more-themes',
        'platform-more-security',
        'platform-more-about',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
      expect(find.text(S.signOut), findsOneWidget);
      expect(find.byKey(const Key('platform-more-eye-protect')), findsNothing);
      expect(find.text(S.settingsEyeProtect), findsNothing);
    });

    testWidgets('no tenant-only row appears', (tester) async {
      await openMore(tester);

      for (final label in const [
        S.settingsOrg, // the organisation record
        S.settingsPlan, // the tenant plan
        S.sectionSync, // the tenant outbox
        S.settingsNotifications, // shift/stock/workshop preferences
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
      // And the boundary is said out loud rather than merely being absent.
      expect(find.text(S.platformMoreScopeNote), findsOneWidget);
    });

    testWidgets('every row opens the screen it names', (tester) async {
      // The `§34` requirement, checked destination by destination: no dead
      // buttons on the surface this Point introduces.
      for (final (key, matcher) in <(String, Finder)>[
        ('platform-more-profile', find.byType(ProfilePage)),
        ('platform-more-themes', find.byType(ThemesAndPerformancePage)),
        ('platform-more-security', find.byType(SecurityPage)),
        ('platform-more-about', find.byType(AboutPage)),
      ]) {
        await openMore(tester);
        await tester.tap(find.byKey(Key(key)));
        await settlePlatform(tester);

        expect(matcher, findsOneWidget, reason: key);
        expect(find.byType(PlatformShell), findsOneWidget, reason: key);
      }
    });

    testWidgets('the old Eye Protection deep link opens canonical Themes',
        (tester) async {
      final router = await bootPlatform(
        tester,
        platformContainer(superAdmin),
      );
      router.go('${PlatformArea.more.route}/eye-protect');
      await settlePlatform(tester);

      expect(locationOf(router), '${PlatformArea.more.route}/themes');
      expect(find.byType(ThemesAndPerformancePage), findsOneWidget);
      expect(find.byKey(const Key('themes-eye-protection')), findsOneWidget);
    });

    testWidgets('the organisation and plan screens are not reachable from here',
        (tester) async {
      ignoreKnownTenantComplaints();
      final router = await bootPlatform(tester, platformContainer(superAdmin));

      for (final location in const [
        '/more/org',
        OrganizationPage.routePath,
        PlanPage.routePath,
      ]) {
        router.go(location);
        await settlePlatform(tester);

        expect(locationOf(router), PlatformShell.location, reason: location);
        expect(find.byType(OrganizationPage), findsNothing, reason: location);
        expect(find.byType(PlanPage), findsNothing, reason: location);
      }
    });
  });

  group('the Super Admin account screen tells the truth', () {
    Future<void> openProfile(WidgetTester tester) async {
      final router = await bootPlatform(tester, platformContainer(superAdmin));
      router.go('${PlatformArea.more.route}/profile');
      await settlePlatform(tester);
    }

    testWidgets('it names the account as the platform administrator',
        (tester) async {
      await openProfile(tester);

      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text(superAdmin.name), findsOneWidget);
      expect(find.text(S.roleSuperAdmin), findsWidgets);
    });

    testWidgets('it shows no tenant organisation and no tenant grant',
        (tester) async {
      await openProfile(tester);

      // No organisation row: this account is not inside a `SaasTenant`, and
      // `orgName` on it names the platform rather than a customer.
      expect(find.text(S.profileOrg), findsNothing);
      expect(find.text(superAdmin.orgName), findsNothing);

      // No access level, no detachment scope, no capability rows — all four
      // are readings of a tenant grant this account does not hold.
      expect(find.text(S.profileAccessLevel), findsNothing);
      expect(find.text(S.profileScope), findsNothing);
      expect(find.text(S.profileManagesAdmins), findsNothing);
      expect(find.text(S.profileEditsOrg), findsNothing);

      // And it is absent because it does not apply, which the screen says.
      expect(find.text(S.platformProfileAccessNote), findsOneWidget);
      expect(find.text(S.profileAccessNote), findsNothing);
    });

    testWidgets('it carries no in-tenant experience label', (tester) async {
      await openProfile(tester);

      // `AdminExperience` grades a session *inside* one team. A Super Admin
      // holding `Capabilities.none` would be graded the narrowest of them.
      expect(find.text(S.adminExperienceFull), findsNothing);
      expect(find.text(S.adminExperienceScoped), findsNothing);
    });

    testWidgets('its Security row opens the platform Security screen',
        (tester) async {
      // The default target is the tenant `/more/security`, which this session
      // is bounced off. The route passes its own.
      await openProfile(tester);

      await tester.tap(find.text(S.settingsSecurity));
      await settlePlatform(tester);

      expect(find.byType(SecurityPage), findsOneWidget);
      expect(find.byType(PlatformShell), findsOneWidget);
    });

    testWidgets('a tenant admin still sees its own full account screen',
        (tester) async {
      // The other half of the same change: nothing was removed from the tenant
      // surface in order to make the platform one truthful.
      ignoreKnownTenantComplaints();
      // A tall window: the tenant account screen has four more rows than the
      // platform one, and a lazily-built `ListView` does not construct what is
      // below the fold.
      final router = await bootPlatform(
        tester,
        platformContainer(fullTenantAdmin),
        height: 1600,
      );

      router.go('/more/profile');
      await settlePlatform(tester);

      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text(S.profileOrg), findsOneWidget);
      expect(find.text(S.profileAccessLevel), findsOneWidget);
      expect(find.text(S.profileManagesAdmins), findsOneWidget);
      expect(find.text(S.profileAccessNote), findsOneWidget);
      expect(find.text(S.platformProfileAccessNote), findsNothing);
    });
  });
}
