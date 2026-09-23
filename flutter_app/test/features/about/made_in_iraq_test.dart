import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/app_info.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/core/widgets/made_in_iraq.dart';
import 'package:mtm/features/about/presentation/about_page.dart';
import 'package:mtm/features/demo/data/demo_control_plane.dart';
import 'package:mtm/l10n/strings.dart';

import '../platform/platform_harness.dart';

/// Scrolls the page to its end so the sign-off is built.
///
/// A `ListView` builds lazily, so the last child of a long page does not
/// exist until something scrolls to it — which is exactly the claim being
/// made about this footer: it is reached by scrolling, not pinned.
Future<Finder> revealFooter(WidgetTester tester) async {
  final footer = find.byKey(MadeInIraqFooter.widgetKey);
  await tester.scrollUntilVisible(
    footer,
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  return footer;
}

/// **«حول ليدر», and the line the product signs itself with.**
///
/// Two screens end with «صنع بفخر في العراق» — About, and the Settings hub —
/// and nothing else does. These tests hold both ends of that: the sign-off is
/// where it should be, it is reached by scrolling rather than pinned, and it
/// reads in every appearance the product ships.
void main() {
  final now = DateTime.utc(2026, 9, 16, 12);

  Future<GoRouter> boot(
    WidgetTester tester, {
    double width = 400,
    double textScale = 1,
  }) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(fullTenantAdmin, overrides: [
      clockProvider.overrideWithValue(() => now),
      demoControlPlaneSeedProvider.overrideWithValue(const []),
    ]);
    return bootPlatform(
      tester,
      container,
      width: width,
      height: 1200,
      textScale: textScale,
    );
  }

  group('the About destination', () {
    testWidgets('Settings names it after the product and opens it',
        (tester) async {
      final router = await boot(tester);
      router.go('/more');
      await settlePlatform(tester);

      // «حول ليدر» — built from the brand constant, never a literal.
      expect(S.aboutTitle, 'حول ${S.productNameAr}');
      final row = find.byKey(const Key('settings-about-row'));
      expect(row, findsOneWidget);
      expect(find.text(S.aboutTitle), findsOneWidget);
      // The row carries the installed version, so the hub answers "which
      // build" without opening anything.
      expect(find.text(AppInfo.version), findsOneWidget);

      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await settlePlatform(tester);

      expect(find.byType(AboutPage), findsOneWidget);
    });

    testWidgets('it is one destination, not three', (tester) async {
      final router = await boot(tester);
      router.go('/more');
      await settlePlatform(tester);

      // No separate Support or Contact-us row: the addresses live on the one
      // screen this row opens.
      expect(find.byKey(const Key('settings-about-row')), findsOneWidget);
      expect(find.text(S.contactSupport), findsNothing);
      expect(find.text(S.aboutSupport), findsNothing);
    });
  });

  group('the About page', () {
    testWidgets('says what Leader is, in Leader branding', (tester) async {
      final router = await boot(tester);
      router.go(AboutPage.routePath);
      await settlePlatform(tester);

      expect(find.text(S.productNameAr), findsWidgets);
      expect(find.text(S.productNameEn), findsOneWidget);
      expect(find.text(S.aboutDescription), findsOneWidget);
      // The purpose names every module the product actually manages.
      for (final subject in ['الفرق', 'المفارز', 'الورش', 'الشفتات']) {
        expect(S.aboutDescription, contains(subject), reason: subject);
      }
      // Role-based management is claimed, and the version is real.
      expect(find.text(S.aboutCapabilityRoles), findsOneWidget);
      expect(find.text(S.aboutCapabilitySync), findsOneWidget);
      expect(find.byKey(const Key('about-version')), findsOneWidget);
      // No obsolete branding anywhere on the screen.
      expect(find.textContaining('MTM'), findsNothing);
    });

    testWidgets('ends with the Iraq line, below everything else',
        (tester) async {
      final router = await boot(tester);
      router.go(AboutPage.routePath);
      await settlePlatform(tester);

      final footer = await revealFooter(tester);
      expect(footer, findsOneWidget);
      expect(find.text(S.madeInIraq), findsOneWidget);
      expect(S.madeInIraq, 'صنع بفخر في العراق');

      // Below the support block — the last thing on the page, not a header.
      final support = tester.getTopLeft(find.byKey(const Key('about-telegram')));
      expect(tester.getTopLeft(footer).dy, greaterThan(support.dy));
    });
  });

  group('the Settings hub', () {
    testWidgets('ends with the same line, after sign-out', (tester) async {
      final router = await boot(tester);
      router.go('/more');
      await settlePlatform(tester);

      // Reached by scrolling, never pinned: it does not exist until the list
      // is scrolled to its end, and sign-out is still above it afterwards.
      expect(find.byKey(MadeInIraqFooter.widgetKey), findsNothing);
      final footer = await revealFooter(tester);
      expect(footer, findsOneWidget);
      final signOut = find.widgetWithText(OutlinedButton, S.signOut);
      expect(
        tester.getTopLeft(footer).dy,
        greaterThan(tester.getTopLeft(signOut).dy),
      );
      expect(find.text(S.madeInIraq), findsOneWidget);
    });

    testWidgets('it is not a settings row and leads nowhere', (tester) async {
      final router = await boot(tester);
      router.go('/more');
      await settlePlatform(tester);

      final footer = await revealFooter(tester);

      // Nothing to tap: no gesture detector, no ink, nowhere to go.
      expect(
        find.ancestor(of: footer, matching: find.byType(InkWell)),
        findsNothing,
      );
      await tester.tap(footer);
      await settlePlatform(tester);
      expect(locationOf(router), '/more');
    });
  });

  group('the sign-off holds up everywhere', () {
    testWidgets('at 320dp and a 1.6 text scale, on both screens',
        (tester) async {
      final router = await boot(tester, width: 320, textScale: 1.6);

      router.go('/more');
      await settlePlatform(tester);
      await revealFooter(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(S.madeInIraq), findsOneWidget);

      router.go(AboutPage.routePath);
      await settlePlatform(tester);
      await revealFooter(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(S.madeInIraq), findsOneWidget);
    });

    for (final appearance in _appearances) {
      testWidgets('in ${appearance.name}', (tester) async {
        ignoreKnownTenantComplaints();
        final container = platformContainer(fullTenantAdmin, overrides: [
          clockProvider.overrideWithValue(() => now),
          demoControlPlaneSeedProvider.overrideWithValue(const []),
        ]);
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(400, 1200);
        addTearDown(tester.view.reset);

        final router = container.read(appRouterProvider);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              debugShowCheckedModeBanner: false,
              theme: appearance.theme(),
              builder: (context, child) => Directionality(
                textDirection: TextDirection.rtl,
                child: child!,
              ),
            ),
          ),
        );
        await settlePlatform(tester);
        router.go(AboutPage.routePath);
        await settlePlatform(tester);

        await revealFooter(tester);
        expect(find.text(S.madeInIraq), findsOneWidget);
        // The line takes its colour from the palette, so it is never the
        // page's own background — the one way a footer becomes invisible.
        final text = tester.widget<Text>(
          find.byKey(MadeInIraqFooter.widgetKey),
        );
        expect(text.style?.color, isNotNull);
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// Light, dark and the eye-protect wash — the three grounds the line has to
/// stay readable on. The palette sweep itself is `palette_contrast_test.dart`;
/// this only proves the footer renders and is coloured in each.
final _appearances = <({String name, ThemeData Function() theme})>[
  (
    name: 'light',
    theme: () => AppTheme.light(PaletteId.medical),
  ),
  (
    name: 'dark',
    theme: () => AppTheme.dark(PaletteId.medical),
  ),
  (
    name: 'eye protection',
    theme: () => AppTheme.light(PaletteId.medical, eyeProtect: true),
  ),
];
