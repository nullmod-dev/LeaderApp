@Tags(['render'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/theme_choice.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/presentation/status_pages.dart';
import 'package:mtm/features/platform/data/mock_platform_overview_repository.dart';
import 'package:mtm/features/platform/data/mock_platform_health_repository.dart';
import 'package:mtm/features/platform/data/mock_platform_security_repository.dart';
import 'package:mtm/features/platform/data/mock_saas_tenant_repository.dart';
import 'package:mtm/features/platform/data/mock_tenant_subscription_repository.dart';
import 'package:mtm/features/platform/data/mock_tenant_lifecycle_repository.dart';
import 'package:mtm/features/platform/data/platform_overview_providers.dart';
import 'package:mtm/features/platform/data/platform_operations_providers.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/data/saas_subscription_providers.dart';
import 'package:mtm/features/platform/data/tenant_lifecycle_providers.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_routes.dart';
import 'package:mtm/features/platform/presentation/platform_operations_routes.dart';
import 'package:mtm/features/platform/domain/platform_area.dart';
import 'package:mtm/features/platform/domain/platform_overview_models.dart';
import 'package:mtm/features/platform/domain/platform_overview_repository.dart';
import 'package:mtm/features/platform/domain/saas_tenant_models.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';
import 'package:mtm/features/tenant_feature/data/mock_tenant_feature_repository.dart';
import 'package:mtm/features/tenant_feature/data/tenant_feature_providers.dart';
import 'package:mtm/features/tenant_feature/domain/tenant_feature_models.dart';

import 'platform_harness.dart';

/// **Not a test.** A one-off renderer that writes PNGs of the platform surface
/// so it can actually be *looked at* — `§44` asks for a visual inspection, and
/// the rest of the suite can only prove that nothing threw.
///
/// Run it deliberately:
///
///     flutter test test/features/platform/platform_render.dart \
///       --update-goldens --tags render
///
/// It is excluded from the ordinary run by its tag, writes into a scratch
/// directory rather than the repository, and asserts nothing — so it can never
/// fail the suite, and there are no golden files to regenerate when a hairline
/// moves (`§38`).
///
/// It loads the real IBM Plex Sans Arabic faces first; without them
/// `flutter test` renders every glyph as a placeholder box and an Arabic
/// layout cannot be judged at all.
void main() {
  final outDir = Platform.environment['MTM_RENDER_DIR'];

  setUpAll(() async {
    // One loader, three faces. A second `FontLoader` for the same family name
    // replaces the first, so registering them separately leaves only the last
    // weight and every other weight renders as a placeholder box.
    final loader = FontLoader('IBMPlexSansArabic');
    for (final path in const [
      'assets/fonts/IBMPlexSansArabic-Regular.ttf',
      'assets/fonts/IBMPlexSansArabic-Medium.ttf',
      'assets/fonts/IBMPlexSansArabic-SemiBold.ttf',
    ]) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();

    var flutterCache = File(Platform.resolvedExecutable).parent;
    while (!flutterCache.path.endsWith('/cache') &&
        flutterCache.parent.path != flutterCache.path) {
      flutterCache = flutterCache.parent;
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        File(
          '${flutterCache.path}/artifacts/material_fonts/'
          'MaterialIcons-Regular.otf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    await icons.load();
  });

  Future<void> shot(
    WidgetTester tester, {
    required String name,
    required AppThemeChoice choice,
    required bool eyeProtect,
    required String location,
    required double width,
    double height = 850,
    double textScale = 1,
    bool reduceMotion = false,
    PlatformOverviewRepository? repository,
    MockSaasTenantMode? tenantMode,
    MockTenantSubscriptionMode? subscriptionMode,
    MockTenantFeatureMode? featureMode,
    MockTenantLifecycleMode? lifecycleMode,
    MockPlatformHealthMode? healthMode,
    MockPlatformSecurityMode? securityMode,
    AuthUser? user,
    void Function(ProviderContainer container)? configure,
    String? typeIntoSearch,
    Future<void> Function(WidgetTester tester)? beforeCapture,
    Future<void> Function(
      WidgetTester tester,
      ProviderContainer container,
    )? beforeCaptureWithContainer,
  }) async {
    if (outDir == null) return;
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size(width * 2, height * 2);
    addTearDown(tester.view.reset);

    final container = platformContainer(
      user ?? superAdmin,
      overrides: [
        clockProvider.overrideWithValue(
          () => DateTime.utc(2026, 9, 8, 16),
        ),
        if (repository != null)
          platformOverviewRepositoryProvider.overrideWithValue(repository),
        if (healthMode != null)
          platformHealthRepositoryProvider.overrideWith((ref) {
            return MockPlatformHealthRepository(
              fixtures: ref.watch(platformOperationsFixturesProvider),
              mode: healthMode,
              latency: Duration.zero,
            );
          }),
        if (securityMode != null)
          platformSecurityRepositoryProvider.overrideWith((ref) {
            return MockPlatformSecurityRepository(
              fixtures: ref.watch(platformOperationsFixturesProvider),
              mode: securityMode,
              latency: Duration.zero,
            );
          }),
        if (tenantMode != null)
          saasTenantRepositoryProvider.overrideWith((ref) {
            return MockSaasTenantRepository(
              store: ref.watch(platformTenantStoreProvider),
              mode: tenantMode,
              latency: Duration.zero,
            );
          }),
        if (subscriptionMode != null)
          tenantSubscriptionRepositoryProvider.overrideWith((ref) {
            return MockTenantSubscriptionRepository(
              store: ref.watch(platformTenantStoreProvider),
              clock: ref.watch(clockProvider),
              mode: subscriptionMode,
              latency: Duration.zero,
            );
          }),
        if (featureMode != null)
          tenantFeatureRepositoryProvider.overrideWith((ref) {
            return MockTenantFeatureRepository(
              store: ref.watch(platformTenantStoreProvider),
              mode: featureMode,
              latency: Duration.zero,
            );
          }),
        if (lifecycleMode != null)
          tenantLifecycleRepositoryProvider.overrideWith((ref) {
            return MockTenantLifecycleRepository(
              store: ref.watch(platformTenantStoreProvider),
              clock: ref.watch(clockProvider),
              mode: lifecycleMode,
              latency: Duration.zero,
            );
          }),
      ],
    );
    configure?.call(container);
    final router = container.read(appRouterProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(choice.palette, eyeProtect: eyeProtect),
          darkTheme: AppTheme.dark(choice.palette, eyeProtect: eyeProtect),
          themeMode:
              choice == AppThemeChoice.light ? ThemeMode.light : ThemeMode.dark,
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
    if (typeIntoSearch != null) {
      await tester.enterText(
        find.byKey(const Key('platform-tenants-search')),
        typeIntoSearch,
      );
      await settlePlatform(tester);
    }
    if (beforeCapture != null) {
      await beforeCapture(tester);
      await settlePlatform(tester);
    }
    if (beforeCaptureWithContainer != null) {
      await beforeCaptureWithContainer(tester, container);
      await settlePlatform(tester);
    }

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$outDir/$name.png'),
    );
  }

  Future<void> statusShot(
    WidgetTester tester, {
    required String name,
    required Widget page,
    required AppThemeChoice choice,
    bool eyeProtect = false,
    double width = 390,
    double height = 850,
    double textScale = 1,
    bool reduceMotion = false,
  }) async {
    if (outDir == null) return;
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size(width * 2, height * 2);
    addTearDown(tester.view.reset);
    final container = platformContainer(mainAdmin);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(choice.palette, eyeProtect: eyeProtect),
        darkTheme: AppTheme.dark(choice.palette, eyeProtect: eyeProtect),
        themeMode:
            choice == AppThemeChoice.light ? ThemeMode.light : ThemeMode.dark,
        home: page,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: MotionScope(
              level:
                  reduceMotion ? MotionLevel.performance : MotionLevel.balanced,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$outDir/$name.png'),
    );
  }

  testWidgets('render the platform surface', (tester) async {
    if (outDir == null) {
      // Says so in the runner output rather than passing silently having done
      // nothing — this file is a tool, and a green tick that rendered nothing
      // would be the only misleading line in the suite.
      markTestSkipped('set MTM_RENDER_DIR to write the screenshots');
      return;
    }

    // The default theme, every destination, on a phone.
    for (final area in PlatformArea.values) {
      await shot(
        tester,
        name: 'dark-cyber-${area.name}',
        choice: AppThemeChoice.darkCyber,
        eyeProtect: false,
        location: area.route,
        width: 390,
      );
    }

    // The real overview and each repository state Point 5 introduces.
    await shot(
      tester,
      name: 'dark-cyber-overview-attention',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: PlatformArea.overview.route,
      width: 390,
      height: 1900,
    );
    await shot(
      tester,
      name: 'dark-cyber-overview-minimal',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: PlatformArea.overview.route,
      width: 390,
      repository: MockPlatformOverviewRepository(
        clock: () => DateTime.utc(2026, 9, 8, 16),
        mode: MockPlatformOverviewMode.empty,
        latency: Duration.zero,
      ),
    );
    await shot(
      tester,
      name: 'dark-cyber-overview-loading',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: PlatformArea.overview.route,
      width: 390,
      repository: const _PendingOverviewRepository(),
    );
    await shot(
      tester,
      name: 'dark-cyber-overview-failure',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: PlatformArea.overview.route,
      width: 390,
      repository: MockPlatformOverviewRepository(
        clock: () => DateTime.utc(2026, 9, 8, 16),
        mode: MockPlatformOverviewMode.failure,
        latency: Duration.zero,
      ),
    );

    // One nested page reached from More.
    await shot(
      tester,
      name: 'dark-cyber-profile',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: '${PlatformArea.more.route}/profile',
      width: 390,
    );

    // The other two themes, and eye protection.
    await shot(
      tester,
      name: 'purple-arena-overview',
      choice: AppThemeChoice.purpleArena,
      eyeProtect: false,
      location: PlatformArea.overview.route,
      width: 390,
    );
    await shot(
      tester,
      name: 'light-overview',
      choice: AppThemeChoice.light,
      eyeProtect: false,
      location: PlatformArea.overview.route,
      width: 390,
    );
    await shot(
      tester,
      name: 'light-eye-protect-overview',
      choice: AppThemeChoice.light,
      eyeProtect: true,
      location: PlatformArea.overview.route,
      width: 390,
    );

    // The two ends of the size range.
    await shot(
      tester,
      name: 'narrow-320-large-text-overview',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: PlatformArea.overview.route,
      width: 320,
      height: 1500,
      textScale: 1.6,
    );
    await shot(
      tester,
      name: 'expanded-900-overview',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: PlatformArea.overview.route,
      width: 900,
      height: 1200,
    );
    // ---- Point 6: the subscriber module ----
    await shot(
      tester,
      name: 'tenants-list',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.list,
      width: 390,
      height: 1600,
    );
    await shot(
      tester,
      name: 'tenants-search',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.list,
      width: 390,
      typeIntoSearch: 'فريق',
    );
    await shot(
      tester,
      name: 'tenants-no-results',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.list,
      width: 390,
      typeIntoSearch: 'لا يوجد',
    );
    await shot(
      tester,
      name: 'tenants-empty',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.list,
      width: 390,
      tenantMode: MockSaasTenantMode.empty,
    );
    await shot(
      tester,
      name: 'tenants-failure',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.list,
      width: 390,
      tenantMode: MockSaasTenantMode.failure,
    );
    await shot(
      tester,
      name: 'tenants-offline-no-cache',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.list,
      width: 390,
      tenantMode: MockSaasTenantMode.offlineWithoutCache,
    );
    await shot(
      tester,
      name: 'tenant-create',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.create,
      width: 390,
      height: 1100,
    );
    await shot(
      tester,
      name: 'tenant-detail',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_afiah'),
      width: 390,
      height: 2000,
    );
    await shot(
      tester,
      name: 'tenant-detail-pending-admin',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_nabd'),
      width: 390,
      height: 2000,
    );
    await shot(
      tester,
      name: 'purple-arena-tenants',
      choice: AppThemeChoice.purpleArena,
      eyeProtect: false,
      location: SaasTenantRoutes.list,
      width: 390,
      height: 1600,
    );
    await shot(
      tester,
      name: 'light-tenants',
      choice: AppThemeChoice.light,
      eyeProtect: false,
      location: SaasTenantRoutes.list,
      width: 390,
      height: 1600,
    );
    await shot(
      tester,
      name: 'light-eye-protect-tenant-detail',
      choice: AppThemeChoice.light,
      eyeProtect: true,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 390,
      height: 2000,
    );
    await shot(
      tester,
      name: 'narrow-320-large-text-tenants',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.list,
      width: 320,
      height: 2200,
      textScale: 1.6,
    );
    await shot(
      tester,
      name: 'narrow-320-large-text-tenant-create',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.create,
      width: 320,
      height: 1800,
      textScale: 1.6,
    );
    await shot(
      tester,
      name: 'expanded-900-tenants',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.list,
      width: 900,
      height: 1400,
    );
    await shot(
      tester,
      name: 'expanded-900-tenant-detail',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 900,
      height: 1600,
    );
    await shot(
      tester,
      name: 'reduced-motion-tenants',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.list,
      width: 390,
      height: 1400,
      reduceMotion: true,
    );

    // ---- Point 7: subscriptions, trials, plans, and plan limits ----
    await shot(
      tester,
      name: 'subscription-trial',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.subscription('saas_nabd'),
      width: 390,
      height: 1500,
    );
    await shot(
      tester,
      name: 'subscription-active',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.subscription('saas_hilal'),
      width: 390,
      height: 1500,
    );
    await shot(
      tester,
      name: 'subscription-grace',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.subscription('saas_afiah'),
      width: 390,
      height: 1500,
    );
    await shot(
      tester,
      name: 'subscription-plan-selection',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.subscription('saas_hilal'),
      width: 390,
      height: 1100,
      beforeCapture: (tester) async {
        await tester.tap(find.byKey(const Key('change-plan')));
      },
    );
    await shot(
      tester,
      name: 'subscription-trial-extension',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.subscription('saas_nabd'),
      width: 390,
      height: 900,
      beforeCapture: (tester) async {
        await tester.tap(find.byKey(const Key('extend-trial')));
      },
    );
    await shot(
      tester,
      name: 'limits-overridden',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.limits('saas_afiah'),
      width: 390,
      height: 2400,
    );
    await shot(
      tester,
      name: 'limits-below-usage-warning',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.limits('saas_afiah'),
      width: 390,
      height: 1200,
      beforeCapture: (tester) async {
        await tester.tap(find.byTooltip('تعديل حد المفارز'));
        await settlePlatform(tester);
        await tester.enterText(find.byKey(const Key('limit-value-field')), '5');
        await tester.tap(find.byKey(const Key('save-limit')));
      },
    );
    await shot(
      tester,
      name: 'limits-no-plan',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.limits('saas_nabd'),
      width: 390,
    );
    await shot(
      tester,
      name: 'subscription-offline',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.subscription('saas_hilal'),
      width: 390,
      subscriptionMode: MockTenantSubscriptionMode.offline,
    );
    await shot(
      tester,
      name: 'limits-failure',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.limits('saas_hilal'),
      width: 390,
      subscriptionMode: MockTenantSubscriptionMode.usageUnavailable,
    );
    await shot(
      tester,
      name: 'narrow-320-large-text-subscription',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.subscription('saas_nabd'),
      width: 320,
      height: 2200,
      textScale: 1.6,
    );
    await shot(
      tester,
      name: 'expanded-900-limits',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.limits('saas_afiah'),
      width: 900,
      height: 1500,
    );
    await shot(
      tester,
      name: 'purple-arena-subscription',
      choice: AppThemeChoice.purpleArena,
      eyeProtect: false,
      location: SaasTenantRoutes.subscription('saas_hilal'),
      width: 390,
      height: 1500,
    );
    await shot(
      tester,
      name: 'light-limits',
      choice: AppThemeChoice.light,
      eyeProtect: false,
      location: SaasTenantRoutes.limits('saas_afiah'),
      width: 390,
      height: 2400,
    );
    await shot(
      tester,
      name: 'light-eye-protect-subscription',
      choice: AppThemeChoice.light,
      eyeProtect: true,
      location: SaasTenantRoutes.subscription('saas_hilal'),
      width: 390,
      height: 1500,
    );
    await shot(
      tester,
      name: 'reduced-motion-subscription',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.subscription('saas_hilal'),
      width: 390,
      height: 1500,
      reduceMotion: true,
    );

    // ---- Point 8: tenant product features and tenant-side gating ----
    await shot(
      tester,
      name: 'features-all-enabled',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.features('saas_hilal'),
      width: 390,
      height: 1500,
    );
    await shot(
      tester,
      name: 'features-partially-disabled',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.features('saas_najd'),
      width: 390,
      height: 1500,
    );
    await shot(
      tester,
      name: 'features-disable-confirmation',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.features('saas_hilal'),
      width: 390,
      height: 1000,
      beforeCapture: (tester) async {
        await tester.tap(
          find.byKey(const Key('tenant-feature-switch-inventory')),
        );
      },
    );
    await shot(
      tester,
      name: 'features-offline-cached',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.features('saas_hilal'),
      width: 390,
      height: 1500,
      featureMode: MockTenantFeatureMode.offlineWithCache,
    );
    await shot(
      tester,
      name: 'features-failure',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.features('saas_hilal'),
      width: 390,
      featureMode: MockTenantFeatureMode.failure,
    );
    await shot(
      tester,
      name: 'features-narrow-320-large-text',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.features('saas_hilal'),
      width: 320,
      height: 2300,
      textScale: 1.6,
    );
    await shot(
      tester,
      name: 'features-expanded-900',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.features('saas_hilal'),
      width: 900,
      height: 1300,
    );
    await shot(
      tester,
      name: 'features-purple-arena',
      choice: AppThemeChoice.purpleArena,
      eyeProtect: false,
      location: SaasTenantRoutes.features('saas_hilal'),
      width: 390,
      height: 1500,
    );
    await shot(
      tester,
      name: 'features-light',
      choice: AppThemeChoice.light,
      eyeProtect: false,
      location: SaasTenantRoutes.features('saas_hilal'),
      width: 390,
      height: 1500,
    );
    await shot(
      tester,
      name: 'features-eye-protection',
      choice: AppThemeChoice.light,
      eyeProtect: true,
      location: SaasTenantRoutes.features('saas_hilal'),
      width: 390,
      height: 1500,
    );
    await shot(
      tester,
      name: 'features-reduced-motion',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.features('saas_hilal'),
      width: 390,
      height: 1500,
      reduceMotion: true,
    );
    await shot(
      tester,
      name: 'tenant-navigation-all-enabled',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: '/home',
      width: 390,
      height: 950,
      user: mainAdmin,
    );
    await shot(
      tester,
      name: 'tenant-navigation-workshops-disabled',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: '/home',
      width: 390,
      height: 950,
      user: mainAdmin,
      configure: (container) {
        container.read(platformTenantStoreProvider).updateFeature(
              mainAdmin.saasTenantId!,
              TenantFeatureKey.workshops,
              false,
            );
      },
    );
    await shot(
      tester,
      name: 'tenant-feature-disabled',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: '/detachment/d_dam_central/storage',
      width: 390,
      height: 850,
      user: mainAdmin,
      configure: (container) {
        container.read(platformTenantStoreProvider).updateFeature(
              mainAdmin.saasTenantId!,
              TenantFeatureKey.inventory,
              false,
            );
      },
    );

    // ---- Point 9B: tenant lifecycle UX and destructive-action safety ----
    await shot(
      tester,
      name: 'lifecycle-active-detail',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 390,
      height: 2200,
    );
    await shot(
      tester,
      name: 'lifecycle-suspended-detail',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_rukn'),
      width: 390,
      height: 2200,
    );
    await shot(
      tester,
      name: 'lifecycle-suspend-reason',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 390,
      height: 850,
      beforeCapture: (tester) async {
        await _tapVisible(
          tester,
          find.byKey(const Key('tenant-lifecycle-suspend')),
        );
      },
    );
    await shot(
      tester,
      name: 'lifecycle-suspend-confirmation',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 390,
      height: 850,
      beforeCapture: (tester) => _openReasonAndReview(
        tester,
        const Key('tenant-lifecycle-suspend'),
      ),
    );
    await shot(
      tester,
      name: 'lifecycle-reactivate-confirmation',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_rukn'),
      width: 390,
      height: 850,
      beforeCapture: (tester) async {
        await _tapVisible(
          tester,
          find.byKey(const Key('tenant-lifecycle-reactivate')),
        );
      },
    );
    await shot(
      tester,
      name: 'lifecycle-begin-deletion-confirmation',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 390,
      height: 900,
      beforeCapture: (tester) => _openReasonAndReview(
        tester,
        const Key('tenant-lifecycle-begin-delete'),
      ),
    );
    await shot(
      tester,
      name: 'lifecycle-pending-before-deadline',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 390,
      height: 2400,
      configure: (container) => _setPending(
        container,
        DateTime.utc(2026, 9, 8, 16),
        'saas_hilal',
      ),
    );
    await shot(
      tester,
      name: 'lifecycle-cancel-deletion-confirmation',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 390,
      height: 900,
      configure: (container) => _setPending(
        container,
        DateTime.utc(2026, 9, 8, 16),
        'saas_hilal',
      ),
      beforeCapture: (tester) async {
        await _tapVisible(
          tester,
          find.byKey(const Key('tenant-lifecycle-cancel-delete')),
        );
      },
    );
    await shot(
      tester,
      name: 'lifecycle-pending-deadline-reached',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 390,
      height: 2400,
      configure: (container) => _setPending(
        container,
        DateTime.utc(2026, 9, 8, 16),
        'saas_hilal',
        overdue: true,
      ),
    );
    await shot(
      tester,
      name: 'lifecycle-final-delete-step-1',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 390,
      height: 900,
      configure: (container) => _setPending(
        container,
        DateTime.utc(2026, 9, 8, 16),
        'saas_hilal',
        overdue: true,
      ),
      beforeCapture: (tester) async {
        await _tapVisible(
          tester,
          find.byKey(const Key('tenant-lifecycle-finalize-delete')),
        );
      },
    );
    await shot(
      tester,
      name: 'lifecycle-final-delete-step-2',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 390,
      height: 900,
      configure: (container) => _setPending(
        container,
        DateTime.utc(2026, 9, 8, 16),
        'saas_hilal',
        overdue: true,
      ),
      beforeCapture: _openFinalConfirmation,
    );
    await shot(
      tester,
      name: 'lifecycle-tombstone',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 390,
      height: 900,
      configure: (container) => _finalizeTenant(
        container,
        DateTime.utc(2026, 9, 8, 16),
        'saas_hilal',
      ),
    );
    await shot(
      tester,
      name: 'lifecycle-stale-refreshed',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 390,
      height: 1100,
      beforeCaptureWithContainer: (tester, container) async {
        _setSuspended(
          container,
          DateTime.utc(2026, 9, 8, 16),
          'saas_hilal',
        );
        await _openReasonAndReview(
          tester,
          const Key('tenant-lifecycle-suspend'),
        );
        await tester.tap(find.text('إيقاف الوصول').last);
        await tester.pump(const Duration(milliseconds: 600));
      },
    );
    await shot(
      tester,
      name: 'lifecycle-offline-write-refused',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 390,
      height: 1100,
      lifecycleMode: MockTenantLifecycleMode.offline,
      beforeCapture: (tester) async {
        await _openReasonAndReview(
          tester,
          const Key('tenant-lifecycle-suspend'),
        );
        await tester.tap(find.text('إيقاف الوصول').last);
      },
    );
    await shot(
      tester,
      name: 'lifecycle-narrow-final-confirmation',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 320,
      height: 1100,
      textScale: 1.6,
      configure: (container) => _setPending(
        container,
        DateTime.utc(2026, 9, 8, 16),
        'saas_hilal',
        overdue: true,
      ),
      beforeCapture: _openFinalConfirmation,
    );
    await shot(
      tester,
      name: 'lifecycle-expanded-900-pending',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 900,
      height: 1600,
      configure: (container) => _setPending(
        container,
        DateTime.utc(2026, 9, 8, 16),
        'saas_hilal',
      ),
    );
    for (final (name, choice, eyeProtect) in const [
      ('lifecycle-purple-arena', AppThemeChoice.purpleArena, false),
      ('lifecycle-light', AppThemeChoice.light, false),
      ('lifecycle-eye-protection', AppThemeChoice.light, true),
    ]) {
      await shot(
        tester,
        name: name,
        choice: choice,
        eyeProtect: eyeProtect,
        location: SaasTenantRoutes.detail('saas_rukn'),
        width: 390,
        height: 1400,
      );
    }
    await shot(
      tester,
      name: 'lifecycle-reduced-motion',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: SaasTenantRoutes.detail('saas_hilal'),
      width: 390,
      height: 1400,
      reduceMotion: true,
    );
    await statusShot(
      tester,
      name: 'lifecycle-tenant-suspended-status',
      page: const TenantSuspendedPage(),
      choice: AppThemeChoice.darkCyber,
    );
    await statusShot(
      tester,
      name: 'lifecycle-tenant-deletion-pending-status',
      page: const TenantDeletionPendingPage(),
      choice: AppThemeChoice.purpleArena,
    );
    await statusShot(
      tester,
      name: 'lifecycle-tenant-deleted-status',
      page: const TenantDeletedPage(),
      choice: AppThemeChoice.light,
      eyeProtect: true,
    );

    await shot(
      tester,
      name: 'reduced-motion-overview',
      choice: AppThemeChoice.darkCyber,
      eyeProtect: false,
      location: PlatformArea.overview.route,
      width: 390,
      height: 1200,
      reduceMotion: true,
    );
  });

  testWidgets('render Point 10 operations', (tester) async {
    if (outDir == null) {
      markTestSkipped('set MTM_RENDER_DIR to write the screenshots');
      return;
    }

    Future<void> point10Shot(
      String name,
      String location, {
      MockPlatformHealthMode? healthMode,
      MockPlatformSecurityMode? securityMode,
      AppThemeChoice choice = AppThemeChoice.darkCyber,
      bool eyeProtect = false,
      double width = 390,
      double height = 1100,
      double textScale = 1,
      bool reduceMotion = false,
    }) =>
        shot(
          tester,
          name: 'point10-$name',
          choice: choice,
          eyeProtect: eyeProtect,
          location: location,
          width: width,
          height: height,
          textScale: textScale,
          reduceMotion: reduceMotion,
          healthMode: healthMode,
          securityMode: securityMode,
        );

    await point10Shot('operations', PlatformArea.operations.route);
    for (final entry in const [
      ('health-healthy', MockPlatformHealthMode.healthy),
      ('health-degraded', MockPlatformHealthMode.degraded),
      ('health-partial', MockPlatformHealthMode.partial),
      ('health-stale', MockPlatformHealthMode.stale),
      ('health-offline', MockPlatformHealthMode.offlineWithoutCache),
      ('health-failure', MockPlatformHealthMode.failure),
    ]) {
      await point10Shot(
        entry.$1,
        PlatformOperationsRoutes.health,
        healthMode: entry.$2,
      );
    }
    for (final entry in const [
      ('security-alerts', MockPlatformSecurityMode.mixed),
      ('security-empty', MockPlatformSecurityMode.noAlerts),
      ('security-critical', MockPlatformSecurityMode.critical),
      ('security-tenant', MockPlatformSecurityMode.tenantLinked),
      ('security-stale', MockPlatformSecurityMode.stale),
      ('security-offline', MockPlatformSecurityMode.offlineWithoutCache),
    ]) {
      await point10Shot(
        entry.$1,
        PlatformOperationsRoutes.security,
        securityMode: entry.$2,
      );
    }
    await point10Shot(
      'health-320-large-text',
      PlatformOperationsRoutes.health,
      healthMode: MockPlatformHealthMode.partial,
      width: 320,
      height: 1400,
      textScale: 1.6,
    );
    await point10Shot(
      'security-320-large-text',
      PlatformOperationsRoutes.security,
      securityMode: MockPlatformSecurityMode.mixed,
      width: 320,
      height: 1600,
      textScale: 1.6,
    );
    await point10Shot(
      'health-600',
      PlatformOperationsRoutes.health,
      width: 600,
    );
    await point10Shot(
      'security-900',
      PlatformOperationsRoutes.security,
      width: 900,
    );
    await point10Shot(
      'purple-arena',
      PlatformOperationsRoutes.security,
      choice: AppThemeChoice.purpleArena,
    );
    await point10Shot(
      'light',
      PlatformOperationsRoutes.health,
      choice: AppThemeChoice.light,
    );
    await point10Shot(
      'eye-protection',
      PlatformOperationsRoutes.security,
      choice: AppThemeChoice.light,
      eyeProtect: true,
    );
    await point10Shot(
      'reduced-motion',
      PlatformOperationsRoutes.health,
      reduceMotion: true,
    );
  });

  /// Phase 2 of the UI quality programme — the Super Admin pass.
  ///
  /// The screens the audit ranked NEEDS REDESIGN / NEEDS CLEANUP on this
  /// surface, plus the two commerce editors, which had no render coverage at
  /// all before this phase. Same harness, same personas, no new framework:
  /// the seeds the control planes ship with give Commerce one offer and two
  /// coupons and Demo one running trial, so these are populated screens
  /// rather than empty states pretending to be layouts.
  testWidgets('render Phase 2 Super Admin screens', (tester) async {
    if (outDir == null) {
      markTestSkipped('set MTM_RENDER_DIR to write the screenshots');
      return;
    }

    Future<void> phase2Shot(
      String name,
      String location, {
      AppThemeChoice choice = AppThemeChoice.darkCyber,
      bool eyeProtect = false,
      double width = 390,
      double height = 1200,
      double textScale = 1,
      bool reduceMotion = false,
    }) =>
        shot(
          tester,
          name: 'phase2-$name',
          choice: choice,
          eyeProtect: eyeProtect,
          location: location,
          width: width,
          height: height,
          textScale: textScale,
          reduceMotion: reduceMotion,
        );

    const commerce = PlatformOperationsRoutes.commerce;
    const demo = PlatformOperationsRoutes.demo;
    const reports = PlatformOperationsRoutes.reports;
    const offerEdit = PlatformOperationsRoutes.commerceOffer;
    const couponEdit = PlatformOperationsRoutes.commerceCoupon;
    final overview = PlatformArea.overview.route;
    final operations = PlatformArea.operations.route;
    final tenants = PlatformArea.tenants.route;
    final tenantDetail = SaasTenantRoutes.detail('saas_hilal');

    // The default theme, one shot per redesigned screen.
    for (final entry in [
      ('overview', overview),
      ('operations', operations),
      ('commerce', commerce),
      ('offer-create', offerEdit),
      ('offer-edit', '$offerEdit/offer_seed_try2'),
      ('coupon-create', couponEdit),
      ('coupon-edit', '$couponEdit/coupon_seed_public'),
      ('demo', demo),
      ('reports', reports),
      ('tenants', tenants),
      ('tenant-detail', tenantDetail),
      ('audit', PlatformOperationsRoutes.audit),
      ('security', PlatformOperationsRoutes.security),
      ('health', PlatformOperationsRoutes.health),
    ]) {
      await phase2Shot(entry.$1, entry.$2);
    }

    // Light, and the eye-protect wash, on the two screens the phase changed
    // most.
    await phase2Shot('light-overview', overview,
        choice: AppThemeChoice.light);
    await phase2Shot('light-commerce', commerce, choice: AppThemeChoice.light);
    await phase2Shot('light-tenant-detail', tenantDetail,
        choice: AppThemeChoice.light);
    await phase2Shot('eye-protect-commerce', commerce,
        choice: AppThemeChoice.light, eyeProtect: true);
    await phase2Shot('purple-arena-overview', overview,
        choice: AppThemeChoice.purpleArena);

    // The overflow gate: 320 dp at a 1.6 text scale on every redesigned
    // screen. `shot` asserts no exception was thrown, so these fail on an
    // overflow rather than merely recording one.
    for (final entry in [
      ('overview', overview),
      ('operations', operations),
      ('commerce', commerce),
      ('offer-create', offerEdit),
      ('coupon-create', couponEdit),
      ('demo', demo),
      ('reports', reports),
      ('tenants', tenants),
      ('tenant-detail', tenantDetail),
      ('audit', PlatformOperationsRoutes.audit),
      ('security', PlatformOperationsRoutes.security),
    ]) {
      await phase2Shot(
        'narrow-320-large-text-${entry.$1}',
        entry.$2,
        width: 320,
        height: 1800,
        textScale: 1.6,
      );
    }

    // The widths where the platform surface reflows.
    for (final entry in [
      ('overview', overview),
      ('commerce', commerce),
      ('tenant-detail', tenantDetail),
      ('audit', PlatformOperationsRoutes.audit),
    ]) {
      await phase2Shot('expanded-600-${entry.$1}', entry.$2, width: 600);
      await phase2Shot('expanded-900-${entry.$1}', entry.$2, width: 900);
    }

    await phase2Shot('reduced-motion-commerce', commerce, reduceMotion: true);
  });
}

class _PendingOverviewRepository implements PlatformOverviewRepository {
  const _PendingOverviewRepository();

  @override
  Future<Result<PlatformOverviewSnapshot>> loadOverview() =>
      Completer<Result<PlatformOverviewSnapshot>>().future;
}

SaasTenant _setPending(
  ProviderContainer container,
  DateTime now,
  String tenantId, {
  bool overdue = false,
}) {
  final store = container.read(platformTenantStoreProvider);
  final tenant = store.byId(tenantId)!;
  final requestedAt = overdue ? now.subtract(const Duration(days: 31)) : now;
  final decision = TenantLifecyclePolicy.transition(
    current: tenant.lifecycle,
    action: TenantLifecycleAction.beginDeletion,
    now: requestedAt,
    reason: 'طلب إنهاء إداري موثّق',
    deletionGrace: const Duration(days: 30),
  ) as TenantLifecycleTransitionAllowed;
  return store.updateLifecycle(
    tenantId,
    decision.next,
    eventType: SaasTenantEventType.deletionRequested,
    note: 'طلب إنهاء إداري موثّق',
  );
}

void _setSuspended(
  ProviderContainer container,
  DateTime now,
  String tenantId,
) {
  final store = container.read(platformTenantStoreProvider);
  final tenant = store.byId(tenantId)!;
  final decision = TenantLifecyclePolicy.transition(
    current: tenant.lifecycle,
    action: TenantLifecycleAction.suspend,
    now: now,
    reason: 'مراجعة إدارية موثّقة',
  ) as TenantLifecycleTransitionAllowed;
  store.updateLifecycle(
    tenantId,
    decision.next,
    eventType: SaasTenantEventType.tenantSuspended,
    note: 'مراجعة إدارية موثّقة',
  );
}

void _finalizeTenant(
  ProviderContainer container,
  DateTime now,
  String tenantId,
) {
  final store = container.read(platformTenantStoreProvider);
  final pending = _setPending(container, now, tenantId, overdue: true);
  final decision = TenantLifecyclePolicy.transition(
    current: pending.lifecycle,
    action: TenantLifecycleAction.finalizeDeletion,
    now: now,
  ) as TenantLifecycleTransitionAllowed;
  store.finalizeTenant(tenantId, decision.next);
}

Future<void> _openReasonAndReview(
  WidgetTester tester,
  Key actionKey,
) async {
  await _tapVisible(tester, find.byKey(actionKey));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('tenant-lifecycle-reason')),
    'مراجعة إدارية موثّقة',
  );
  await tester.pump();
  await tester.tap(
    find.byKey(const Key('tenant-lifecycle-reason-continue')),
  );
  await tester.pumpAndSettle();
}

Future<void> _openFinalConfirmation(WidgetTester tester) async {
  await _tapVisible(
    tester,
    find.byKey(const Key('tenant-lifecycle-finalize-delete')),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('متابعة إلى التأكيد'));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
