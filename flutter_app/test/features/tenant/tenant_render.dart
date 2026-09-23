@Tags(['render'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/theme_choice.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';

import '../platform/platform_harness.dart';
import '../render_fonts.dart';

/// The tenant render harness — the Main Admin half of the product, by eye.
///
/// **Why it exists.** The 2026-09-19 UI audit produced 202 renders and had to
/// open with a coverage confession: harnesses existed for the platform
/// surface, break-glass, audit, the Main Admin seat, Organization/Plan,
/// Simple Admin and onboarding, and for *none* of the tenant operational
/// screens. Home, Detachments, Team, Shifts, Inventory, Statistics,
/// Workshops, Notifications and Sync were audited from source. The audit's
/// own work item 0 was to fix that before any redesign pass, because
/// everything Phase 2 and Phase 3 will change is on these screens and
/// "verified by eye or it is not verified".
///
/// **What this is not.** Not a new screenshot framework and not a pixel gate.
/// It boots the same real app through the same `appRouterProvider` the
/// platform harness uses, at a chosen size, text scale, palette and
/// appearance, and writes a PNG. Nothing here is committed: the goldens go to
/// `MTM_RENDER_DIR` and the tests skip entirely when that is unset, so the
/// ordinary suite neither runs them nor depends on a checked-in image.
///
///     MTM_RENDER_DIR=/tmp/leader-tenant flutter test \
///       test/features/tenant/tenant_render.dart --tags render --update-goldens
///
/// Every shot also asserts `takeException() == null`, which is the part that
/// runs for free: an overflow at 320 dp and 1.6× fails the render rather than
/// quietly drawing a yellow stripe into the PNG.
void main() {
  final outDir = Platform.environment['MTM_RENDER_DIR'];

  // A Saturday inside the seeded week, early enough that no shift has opened
  // its attendance window — so the schedule renders the same way on every
  // run rather than depending on the hour the suite happens to start.
  final now = DateTime(2026, 9, 12, 9);

  setUpAll(loadRenderFonts);

  Future<void> shot(
    WidgetTester tester, {
    required String name,
    required String location,
    AuthUser? user,
    AppThemeChoice theme = AppThemeChoice.medical,
    // Appearance is its own axis: every palette ships Light, Dark and
    // System, and `AppThemeChoice.defaultMode` answers Light for all six
    // (`theme_choice.dart`). Reading it here rendered the two shots named
    // "dark" in *light*, which is how a dark-mode regression could have sat
    // in this set unseen — caught in the Phase 3C render review.
    ThemeMode mode = ThemeMode.light,
    double width = 390,
    double height = 1500,
    double textScale = 1,
    bool eyeProtect = false,
    bool reduceMotion = false,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size(width * 2, height * 2);
    addTearDown(tester.view.reset);
    ignoreKnownTenantComplaints();

    final container = platformContainer(
      user ?? mainAdmin,
      overrides: [clockProvider.overrideWithValue(() => now)],
    );
    final router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(theme.palette, eyeProtect: eyeProtect),
          darkTheme: AppTheme.dark(theme.palette, eyeProtect: eyeProtect),
          themeMode: mode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reduceMotion,
            ),
            // The product ships Arabic; a render that is not RTL is a render
            // of a screen nobody uses.
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: MotionScope(
                level: reduceMotion
                    ? MotionLevel.performance
                    : MotionLevel.balanced,
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    await settlePlatform(tester);
    router.go(location);
    await settlePlatform(tester);

    expect(tester.takeException(), isNull, reason: '$name must fit');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$outDir/$name.png'),
    );
  }

  // The seeded detachment with the fullest data — a roster, a worked week,
  // stock movements and enough history for the statistics tab.
  const detachment = 'd_dam_central';
  const home = '/home';
  const detachments = '/detachment';
  const team = '/detachment/$detachment/team';
  const shifts = '/detachment/$detachment/shifts';
  const storage = '/detachment/$detachment/storage';
  const stats = '/detachment/$detachment/stats';
  const workshops = '/workshop';
  const workshopRegister = '/workshop/w1/members';
  const settings = '/more';
  const themes = '/more/themes';
  const organization = '/more/organization';
  const plan = '/more/plan';
  const pricing = '/more/pricing';
  const notifications = '/notifications';
  const needsReview = '/needs-review';
  const sync = '/more/sync';

  /// Every Phase 3 target at the reference size, so a redesign has a
  /// before to compare against.
  const reference = <(String, String, double)>[
    ('01-home', home, 1500),
    ('02-detachments', detachments, 1500),
    ('03-team', team, 1700),
    ('04-shifts', shifts, 1700),
    ('05-storage', storage, 1700),
    ('06-stats', stats, 2600),
    ('07-workshops', workshops, 1600),
    ('07b-workshop-register', workshopRegister, 1900),
    ('08-settings', settings, 2000),
    ('09-themes', themes, 2600),
    ('10-organization', organization, 1400),
    ('11-plan', plan, 2300),
    ('12-pricing', pricing, 2200),
    ('13-notifications', notifications, 1500),
    ('14-needs-review', needsReview, 1400),
    ('15-sync', sync, 1800),
  ];

  group('390 dp light — the reference set', () {
    for (final (name, location, height) in reference) {
      testWidgets('$name 390 light', (tester) async {
        await shot(
          tester,
          name: '$name-390-light',
          location: location,
          height: height,
        );
      }, skip: outDir == null);
    }
  });

  group('320 dp at 1.6× — the size that breaks layouts', () {
    // The narrow phone with large text is where an unwrapped filter row, a
    // two-column metric grid or a long Arabic label actually fails. Every
    // shot asserts no exception, so this group is a real overflow gate.
    for (final (name, location, height) in reference) {
      testWidgets('$name 320 1.6x', (tester) async {
        await shot(
          tester,
          name: '$name-320-1.6x',
          location: location,
          width: 320,
          height: height * 1.7,
          textScale: 1.6,
        );
      }, skip: outDir == null);
    }
  });

  group('wide layouts — where the tenant surface used to stretch', () {
    const wide = <(String, String)>[
      ('01-home', home),
      ('02-detachments', detachments),
      ('04-shifts', shifts),
      ('05-storage', storage),
      ('06-stats', stats),
      ('07b-workshop-register', workshopRegister),
      ('08-settings', settings),
      ('10-organization', organization),
      ('11-plan', plan),
      ('12-pricing', pricing),
    ];
    for (final (name, location) in wide) {
      testWidgets('$name 600', (tester) async {
        await shot(
          tester,
          name: '$name-600-light',
          location: location,
          width: 600,
          height: 2000,
        );
      }, skip: outDir == null);

      testWidgets('$name 900', (tester) async {
        await shot(
          tester,
          name: '$name-900-light',
          location: location,
          width: 900,
          height: 1600,
        );
      }, skip: outDir == null);
    }
  });

  group('appearance', () {
    testWidgets('home dark', (tester) async {
      await shot(
        tester,
        name: '01-home-390-dark',
        location: home,
        theme: AppThemeChoice.slate,
        mode: ThemeMode.dark,
      );
    }, skip: outDir == null);

    testWidgets('shifts dark', (tester) async {
      await shot(
        tester,
        name: '04-shifts-390-dark',
        location: shifts,
        theme: AppThemeChoice.slate,
        mode: ThemeMode.dark,
        height: 1700,
      );
    }, skip: outDir == null);

    testWidgets('home eye protection', (tester) async {
      await shot(
        tester,
        name: '01-home-390-eye-protect',
        location: home,
        eyeProtect: true,
      );
    }, skip: outDir == null);

    testWidgets('plan eye protection', (tester) async {
      await shot(
        tester,
        name: '11-plan-390-eye-protect',
        location: plan,
        eyeProtect: true,
        height: 2300,
      );
    }, skip: outDir == null);

    testWidgets('statistics teal', (tester) async {
      await shot(
        tester,
        name: '06-stats-390-teal',
        location: stats,
        theme: AppThemeChoice.teal,
        height: 2600,
      );
    }, skip: outDir == null);

    testWidgets('workshops copper reduced motion', (tester) async {
      await shot(
        tester,
        name: '07-workshops-390-copper-reduced-motion',
        location: workshops,
        theme: AppThemeChoice.copper,
        reduceMotion: true,
        height: 1600,
      );
    }, skip: outDir == null);
  });

  group('the other tenant role', () {
    // A Simple Admin sees fewer controls on the same screens; a render that
    // only ever shows the Main Admin hides every capability-gated difference.
    testWidgets('home as a simple admin', (tester) async {
      await shot(
        tester,
        name: '01-home-390-simple-admin',
        location: home,
        user: simpleAdmin,
      );
    }, skip: outDir == null);

    testWidgets('settings as a simple admin', (tester) async {
      await shot(
        tester,
        name: '08-settings-390-simple-admin',
        location: settings,
        user: simpleAdmin,
        height: 2000,
      );
    }, skip: outDir == null);

    testWidgets('team as a simple admin', (tester) async {
      await shot(
        tester,
        name: '03-team-390-simple-admin',
        location: team,
        user: simpleAdmin,
        height: 1700,
      );
    }, skip: outDir == null);
  });
}
