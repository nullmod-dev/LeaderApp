import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/theme_choice.dart';
import 'package:mtm/features/platform/domain/platform_area.dart';
import 'package:mtm/features/platform/presentation/platform_operations_routes.dart';
import 'package:mtm/features/platform/presentation/platform_shell.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_routes.dart';
import 'package:mtm/features/platform/presentation/widgets/platform_navigation.dart';

import 'platform_harness.dart';

/// Point 4 — every platform surface rendered in every appearance the product
/// ships, at both ends of the size range.
///
/// **What this replaces.** `§44` asks for the platform surface to be looked at
/// in Dark Cyber, Purple Arena, Light, with Eye Protection, at 320 dp and at
/// ≥600 dp, and under reduced motion. Looking is how the *design* is judged;
/// this is how the classes of defect a screenshot catches by accident are
/// caught on purpose and stay caught — an overflow, a layout exception, a
/// widget that only builds under one brightness.
///
/// It asserts no pixels. Goldens over four screens × four appearances × two
/// widths would be thirty-two files to regenerate every time a hairline moves,
/// which `§38` rules out; the assertion here is that every combination builds
/// clean and still renders its navigation and its content.

void main() {
  /// Every appearance the product offers, as the theme pair the app builds.
  final appearances =
      <String, ({ThemeData light, ThemeData dark, ThemeMode mode})>{
    for (final choice in AppThemeChoice.values)
      for (final eyeProtect in [false, true])
        '${choice.name}${eyeProtect ? ' + eye-protect' : ''}': (
          light: AppTheme.light(choice.palette, eyeProtect: eyeProtect),
          dark: AppTheme.dark(choice.palette, eyeProtect: eyeProtect),
          // The two dark themes are fixed-dark; only `light` carries a mode.
          mode:
              choice == AppThemeChoice.light ? ThemeMode.light : ThemeMode.dark,
        ),
  };

  Future<GoRouter> boot(
    WidgetTester tester, {
    required ({ThemeData light, ThemeData dark, ThemeMode mode}) appearance,
    required double width,
    double height = 900,
    double textScale = 1,
    bool reduceMotion = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.reset);

    final container = platformContainer(superAdmin);
    final router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          theme: appearance.light,
          darkTheme: appearance.dark,
          themeMode: appearance.mode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reduceMotion,
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              // The real app binds this at its root; the platform navigation
              // reads it for its selection transition.
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
    return router;
  }

  /// Walks the whole surface: the four destinations plus the five pages inside
  /// More, which is every screen a Super Admin can reach in this build.
  Future<void> walk(WidgetTester tester, GoRouter router) async {
    for (final location in [
      for (final area in PlatformArea.values) area.route,
      ...PlatformOperationsRoutes.all,
      '${PlatformArea.more.route}/profile',
      '${PlatformArea.more.route}/security',
      '${PlatformArea.more.route}/themes',
      '${PlatformArea.more.route}/about',
      SaasTenantRoutes.subscription('saas_nabd'),
      SaasTenantRoutes.subscription('saas_hilal'),
      SaasTenantRoutes.subscription('saas_afiah'),
      SaasTenantRoutes.limits('saas_afiah'),
      SaasTenantRoutes.limits('saas_nabd'),
      SaasTenantRoutes.features('saas_hilal'),
      SaasTenantRoutes.features('saas_najd'),
    ]) {
      router.go(location);
      await settlePlatform(tester);
      expect(locationOf(router), location, reason: location);
      expect(find.byType(PlatformShell), findsOneWidget, reason: location);
    }
  }

  group('every appearance, on a phone', () {
    for (final entry in appearances.entries) {
      testWidgets('${entry.key} renders every platform screen', (tester) async {
        // No `FlutterError.onError` override anywhere in this file: an
        // overflow or a failed assertion on any screen, in any theme, fails
        // the test that produced it.
        final router = await boot(tester, appearance: entry.value, width: 390);
        await walk(tester, router);
        expect(find.byType(PlatformNavigationBar), findsOneWidget);
      });
    }
  });

  group('the narrowest phone the app targets', () {
    for (final entry in appearances.entries) {
      testWidgets('${entry.key} survives 320 dp at a 1.6 text scale',
          (tester) async {
        final router = await boot(
          tester,
          appearance: entry.value,
          width: 320,
          textScale: 1.6,
        );
        await walk(tester, router);
      });
    }
  });

  group('the expanded layout', () {
    for (final entry in appearances.entries) {
      testWidgets('${entry.key} renders with the rail at 900 dp',
          (tester) async {
        final router = await boot(tester, appearance: entry.value, width: 900);
        await walk(tester, router);
        expect(find.byType(PlatformNavigationRail), findsOneWidget);
        expect(find.byType(PlatformNavigationBar), findsNothing);
      });
    }
  });

  group('reduced motion and the cheapest performance preset', () {
    testWidgets('every screen still renders, in the default theme',
        (tester) async {
      final router = await boot(
        tester,
        appearance: appearances[AppThemeChoice.darkCyber.name]!,
        width: 390,
        reduceMotion: true,
      );
      await walk(tester, router);
      expect(find.byType(PlatformNavigationBar), findsOneWidget);
    });

    testWidgets('and at 320 dp with a large text scale as well',
        (tester) async {
      final router = await boot(
        tester,
        appearance: appearances[AppThemeChoice.darkCyber.name]!,
        width: 320,
        textScale: 1.6,
        reduceMotion: true,
      );
      await walk(tester, router);
    });
  });
}
