@Tags(['render'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/theme_choice.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_platform_break_glass_repository.dart';
import 'package:mtm/features/platform/data/platform_break_glass_fixtures.dart';
import 'package:mtm/features/platform/data/platform_break_glass_providers.dart';
import 'package:mtm/features/platform/presentation/platform_operations_routes.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

/// Deliberate Point 12 visual-review harness. PNGs stay outside the repository.
///
/// MTM_RENDER_DIR=/tmp/mtm-break-glass flutter test
/// test/features/platform/platform_break_glass_render.dart \
///   --tags render --update-goldens
void main() {
  final outDir = Platform.environment['MTM_RENDER_DIR'];
  final now = DateTime.utc(2026, 9, 11, 12);

  setUpAll(() async {
    final arabic = FontLoader('IBMPlexSansArabic');
    for (final weight in ['Regular', 'Medium', 'SemiBold']) {
      arabic.addFont(
        File('assets/fonts/IBMPlexSansArabic-$weight.ttf')
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    }
    await arabic.load();
    var cache = File(Platform.resolvedExecutable).parent;
    while (!cache.path.endsWith('/cache') && cache.parent.path != cache.path) {
      cache = cache.parent;
    }
    await (FontLoader('MaterialIcons')
          ..addFont(
            File(
              '${cache.path}/artifacts/material_fonts/'
              'MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
        .load();
  });

  Future<void> shot(
    WidgetTester tester, {
    required String name,
    required String location,
    AppThemeChoice theme = AppThemeChoice.light,
    BreakGlassFixtureScenario seed = BreakGlassFixtureScenario.none,
    MockBreakGlassMode mode = MockBreakGlassMode.loaded,
    double width = 390,
    double height = 844,
    double textScale = 1,
    bool eyeProtect = false,
    bool reduceMotion = false,
    Future<void> Function(WidgetTester tester)? interact,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size(width * 2, height * 2);
    addTearDown(tester.view.reset);

    final watch = TenantRepositoryWatch();
    final container = platformContainer(
      superAdmin,
      watch: watch,
      overrides: [
        clockProvider.overrideWithValue(() => now),
        breakGlassMockConfigProvider.overrideWithValue(
          BreakGlassMockConfig(
            seed: seed,
            mode: mode,
            latency: Duration.zero,
          ),
        ),
      ],
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
          themeMode: theme.defaultMode,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reduceMotion,
            ),
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
    if (interact != null) {
      await interact(tester);
      await settlePlatform(tester);
    }

    expect(watch.built, isEmpty);
    expect(tester.takeException(), isNull, reason: '$name must fit');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$outDir/$name.png'),
    );
  }

  testWidgets('no grant management 390 light', (tester) async {
    await shot(
      tester,
      name: '01-management-none-390-light',
      location: PlatformOperationsRoutes.access,
    );
  }, skip: outDir == null);

  testWidgets('request 390 light', (tester) async {
    await shot(
      tester,
      name: '02-request-390-light',
      location: PlatformOperationsRoutes.accessRequest,
    );
  }, skip: outDir == null);

  testWidgets('active grant and strip 390 dark cyber', (tester) async {
    await shot(
      tester,
      name: '03-active-390-dark-cyber',
      location: PlatformOperationsRoutes.access,
      theme: AppThemeChoice.darkCyber,
      seed: BreakGlassFixtureScenario.active,
    );
  }, skip: outDir == null);

  testWidgets('near expiry 390', (tester) async {
    await shot(
      tester,
      name: '04-near-expiry-390-light',
      location: PlatformOperationsRoutes.access,
      seed: BreakGlassFixtureScenario.nearExpiry,
    );
  }, skip: outDir == null);

  testWidgets('stale unverified grant 390', (tester) async {
    await shot(
      tester,
      name: '05-stale-unverified-390-dark-cyber',
      location: PlatformOperationsRoutes.access,
      theme: AppThemeChoice.darkCyber,
      seed: BreakGlassFixtureScenario.active,
      mode: MockBreakGlassMode.stale,
    );
  }, skip: outDir == null);

  testWidgets('recent auth required 390', (tester) async {
    await shot(
      tester,
      name: '06-recent-auth-390-light',
      location: PlatformOperationsRoutes.accessRequest,
      mode: MockBreakGlassMode.recentAuthRequired,
      interact: (tester) async {
        await tester.tap(find.byKey(const Key('break-glass-tenant')));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('فرق الهلال الطبية').last);
        await tester.enterText(
          find.byKey(const Key('break-glass-reason')),
          'حاجة إدارية موثقة',
        );
        await tester.tap(find.byKey(const Key('break-glass-activate')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilledButton, S.breakGlassActivateAction).last,
        );
      },
    );
  }, skip: outDir == null);

  testWidgets('offline with no usable authority 390', (tester) async {
    await shot(
      tester,
      name: '07-offline-390-light',
      location: PlatformOperationsRoutes.access,
      mode: MockBreakGlassMode.offline,
    );
  }, skip: outDir == null);

  testWidgets('320 large text active grant', (tester) async {
    await shot(
      tester,
      name: '08-active-320-large-text',
      location: PlatformOperationsRoutes.access,
      theme: AppThemeChoice.darkCyber,
      seed: BreakGlassFixtureScenario.active,
      width: 320,
      height: 1000,
      textScale: 1.6,
    );
  }, skip: outDir == null);

  testWidgets('600 purple arena', (tester) async {
    await shot(
      tester,
      name: '09-active-600-purple-arena',
      location: PlatformOperationsRoutes.access,
      theme: AppThemeChoice.purpleArena,
      seed: BreakGlassFixtureScenario.active,
      width: 600,
      height: 900,
    );
  }, skip: outDir == null);

  testWidgets('900 light request', (tester) async {
    await shot(
      tester,
      name: '10-request-900-light',
      location: PlatformOperationsRoutes.accessRequest,
      width: 900,
      height: 900,
    );
  }, skip: outDir == null);

  testWidgets('eye protection active grant', (tester) async {
    await shot(
      tester,
      name: '11-active-390-eye-protection',
      location: PlatformOperationsRoutes.access,
      theme: AppThemeChoice.darkCyber,
      seed: BreakGlassFixtureScenario.active,
      eyeProtect: true,
    );
  }, skip: outDir == null);

  testWidgets('reduced motion active grant', (tester) async {
    await shot(
      tester,
      name: '12-active-390-reduced-motion',
      location: PlatformOperationsRoutes.access,
      theme: AppThemeChoice.darkCyber,
      seed: BreakGlassFixtureScenario.active,
      reduceMotion: true,
    );
  }, skip: outDir == null);
}
