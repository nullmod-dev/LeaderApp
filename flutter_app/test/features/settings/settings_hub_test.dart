import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/widgets/forward_chevron.dart';
import 'package:mtm/features/settings/presentation/notifications_page.dart';
import 'package:mtm/features/organization/presentation/organization_page.dart';
import 'package:mtm/features/organization/presentation/plan_page.dart';
import 'package:mtm/features/settings/presentation/profile_page.dart';
import 'package:mtm/features/settings/presentation/security_page.dart';
import 'package:mtm/features/settings/presentation/settings_page.dart';
import 'package:mtm/features/settings/presentation/sync_page.dart';
import 'package:mtm/features/settings/presentation/themes_and_performance_page.dart';
import 'package:mtm/features/settings/presentation/widgets/settings_widgets.dart';
import 'package:mtm/l10n/strings.dart';
import 'package:mtm/main.dart';

/// Point 1 — the Settings hub (`/more`) is navigation only; every control it
/// used to hold directly now lives on its own nested screen.
///
/// These tests boot the real app (`MtmApp`) rather than the bare
/// `SettingsPage`, so navigation genuinely exercises the router — a route
/// that resolves to a stale/duplicate page, or a back button that lands
/// somewhere other than `/more`, would fail here even though it looks fine
/// in isolation.
void main() {
  /// Swallows the same pre-existing, narrowly-matched debug complaint
  /// `needs_review_page_test.dart` already tolerates for this exact
  /// `ListTile`-inside-a-decorated-card layout — present before Point 1
  /// (the hub's rows were built the same way) and out of scope to fix here.
  void ignoreKnownPreexistingComplaints() {
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
  }

  Future<GoRouter> boot(WidgetTester tester, {String at = '/more'}) async {
    ignoreKnownPreexistingComplaints();
    // A tall phone size: the default test surface is small enough that the
    // floating bottom nav overlaps the last hub rows (intercepting their
    // taps) and the Organization section falls outside the viewport
    // entirely (a plain `ListView(children:)` only lays out what's within
    // the viewport + cache extent, same as any other sliver list). Point 15
    // added the Plan row, so the surface grew with it.
    // Pricing adds one canonical subscription section above Organization.
    // Keep this inventory-style harness tall enough to build the footer and
    // sign-out as well; narrow responsive behavior has its own focused tests.
    tester.view.physicalSize = const Size(1080, 5400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MtmApp()),
    );
    await tester.pumpAndSettle();
    final router = container.read(appRouterProvider);
    router.go(at);
    await tester.pumpAndSettle();
    return router;
  }

  /// Performance's quality/frame-rate pickers show an indeterminate
  /// `CircularProgressIndicator` until their stored preference loads, which
  /// keeps scheduling frames forever — `pumpAndSettle` never returns while
  /// one is on screen. Bounded pumps are enough: the mock repository's
  /// simulated latency is under a second.
  Future<void> settleAroundSpinners(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('renders as an Arabic RTL hub with every category reachable',
      (tester) async {
    await boot(tester);

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(
      tester
          .widget<Directionality>(find
              .ancestor(
                of: find.byType(SettingsPage),
                matching: find.byType(Directionality),
              )
              .first)
          .textDirection,
      TextDirection.rtl,
    );

    // Every category and account destination is reachable from the hub.
    for (final label in [
      S.sectionThemesPerformance,
      S.settingsProfile,
      S.settingsSecurity,
      S.settingsNotifications,
      S.pricingTitle,
      S.signOut,
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // A destination is named once: Sync is an app row, Organization is a row
    // under a broader group, and Pricing is the sole subscription door.
    expect(find.text(S.sectionSync), findsOneWidget);
    expect(find.text(S.settingsOrg), findsOneWidget);
    expect(find.text(S.sectionOrgManagement), findsOneWidget);
    expect(find.text(S.settingsPlan), findsNothing);
    expect(find.byKey(const Key('settings-pricing-row')), findsOneWidget);
    expect(find.text(S.pricingTitle), findsOneWidget);
    expect(
      find.widgetWithText(NavigationRow, S.settingsEyeProtect),
      findsNothing,
      reason: 'Eye Protection is controlled only inside Themes & Appearance',
    );
  });

  testWidgets(
      'no detailed theme, performance, or sync controls render on the hub',
      (tester) async {
    await boot(tester);

    expect(find.byType(PickerRow), findsNothing);
    expect(find.byType(ChoicePill), findsNothing);
    expect(find.byKey(const Key('sync-now-button')), findsNothing);
    expect(find.text(S.settingsQuality), findsNothing);
    expect(find.text(S.settingsFrameRate), findsNothing);
    expect(find.byType(Switch), findsNothing);
    // No raw backend/sync terminology anywhere on the hub.
    expect(find.textContaining('outbox', findRichText: true), findsNothing);
    expect(
        find.textContaining('operationId', findRichText: true), findsNothing);
  });

  testWidgets(
      'tapping Themes & Performance opens the one canonical screen and '
      'back returns to the hub', (tester) async {
    await boot(tester);

    await tester.tap(find.text(S.sectionThemesPerformance));
    await settleAroundSpinners(tester);
    expect(find.byType(ThemesAndPerformancePage), findsOneWidget);
    expect(find.byType(SettingsPage), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('the old Performance route redirects to that same screen',
      (tester) async {
    final router = await boot(tester);

    router.go('/more/performance');
    await settleAroundSpinners(tester);

    // One screen owns these controls; the old path is not a second copy.
    expect(find.byType(ThemesAndPerformancePage), findsOneWidget);
  });

  testWidgets('the old Eye Protection route redirects to Themes & Appearance',
      (tester) async {
    final router = await boot(tester);

    router.go('/more/eye-protect');
    await settleAroundSpinners(tester);
    expect(find.byType(ThemesAndPerformancePage), findsOneWidget);
    expect(find.byKey(const Key('themes-eye-protection')), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/more/themes',
    );
  });

  testWidgets('Settings navigation chevrons point forward in Arabic RTL',
      (tester) async {
    await boot(tester);
    final row = find.widgetWithText(NavigationRow, S.sectionThemesPerformance);
    final tile = tester.widget<ListTile>(
      find.descendant(of: row, matching: find.byType(ListTile)),
    );
    // The shared primitive, not a hand-picked constant: `ForwardChevron`
    // owns the mirroring rule and `forward_chevron_test.dart` proves which
    // way it actually paints in each direction.
    expect(tile.trailing, isA<ForwardChevron>());
    expect(ForwardChevron.icon, Icons.chevron_right_rounded);
  });

  testWidgets('tapping Sync opens the nested Sync screen', (tester) async {
    await boot(tester);

    // The row labelled "المزامنة" that is a ListTile-style navigation row
    // (not the section label above it).
    await tester.tap(find.widgetWithText(NavigationRow, S.sectionSync));
    await tester.pumpAndSettle();
    expect(find.byType(SyncPage), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets(
      'Profile, Security, Notifications and Organization links still open '
      'their existing routes, with Plan available inside Organization',
      (tester) async {
    await boot(tester);

    await tester.tap(find.text(S.settingsProfile));
    await tester.pumpAndSettle();
    expect(find.byType(ProfilePage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text(S.settingsSecurity));
    await tester.pumpAndSettle();
    expect(find.byType(SecurityPage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text(S.settingsNotifications));
    await tester.pumpAndSettle();
    expect(find.byType(NotificationsPage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(NavigationRow, S.settingsOrg));
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('org-open-plan')));
    await tester.pumpAndSettle();
    expect(find.byType(PlanPage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(OrganizationPage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('sign-out asks for confirmation exactly as before',
      (tester) async {
    await boot(tester);

    // Scrolled to first: the hub is a long list, and in a **development**
    // build it carries one more section than a shipping one (the Point 3
    // session-state inspector, behind `demoAccountsAllowed`), so the button
    // that sits below every destination is off-screen at this test's height.
    final signOut = find.widgetWithText(OutlinedButton, S.signOut);
    await tester.ensureVisible(signOut);
    await tester.pumpAndSettle();
    await tester.tap(signOut);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(S.signOutConfirm), findsOneWidget);

    // Cancel leaves the hub exactly where it was.
    await tester.tap(find.text(S.cancel));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('a narrow phone with large text does not overflow',
      (tester) async {
    ignoreKnownPreexistingComplaints();
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    // The hub in isolation, not the full app — this checks the hub's own
    // layout under a narrow width and a large accessibility text scale,
    // without also exercising unrelated screens kept alive behind it.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.medical),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.6),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: const SettingsPage(),
        ),
      ),
    );
    // Not `pumpAndSettle`: the hub's motion/frame-rate summaries watch
    // providers with a simulated load delay, and nothing upstream has
    // resolved them yet the way `MtmApp`'s own top-level watch does before
    // Settings is ever reached. Bounded pumps are enough for a layout check.
    await settleAroundSpinners(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(SettingsPage), findsOneWidget);
  });
}
