@Tags(['render'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/theme_choice.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/organization/data/mock_organization_repository.dart';
import 'package:mtm/features/organization/data/organization_providers.dart';
import 'package:mtm/features/organization/domain/organization_models.dart';
import 'package:mtm/features/organization/domain/organization_repository.dart';
import 'package:mtm/features/organization/presentation/organization_page.dart';
import 'package:mtm/features/organization/presentation/plan_page.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';

import '../platform/platform_harness.dart';

/// Deliberate Point 15 visual-review harness. PNGs stay outside the repository.
///
/// MTM_RENDER_DIR=/tmp/mtm-org-plan flutter test
/// test/features/organization/organization_plan_render.dart \
///   --tags render --update-goldens
void main() {
  final outDir = Platform.environment['MTM_RENDER_DIR'];
  final now = DateTime.utc(2026, 9, 12, 9);

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

  AuthUser tenantUser(String tenantId, {bool simple = false}) => AuthUser(
        id: simple ? 'u_render_simple' : 'u_render_main',
        name: simple ? 'سامر الحلبي' : 'ليلى',
        email: 'render@mtm.org',
        role: simple ? AuthRole.admin : AuthRole.mainAdmin,
        saasTenantId: tenantId,
        capabilities: simple
            ? simpleAdmin.capabilities
            : const Capabilities(global: Cap.all),
        orgName: 'MTM',
      );

  Future<void> shot(
    WidgetTester tester, {
    required String name,
    required String location,
    String tenantId = 'saas_hilal',
    bool simple = false,
    AppThemeChoice theme = AppThemeChoice.light,
    MockOrganizationMode mode = MockOrganizationMode.loaded,
    Result<OrganizationSnapshot>? read,
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
      tenantUser(tenantId, simple: simple),
      overrides: [
        clockProvider.overrideWithValue(() => now),
        organizationMockConfigProvider.overrideWithValue(
          OrganizationMockConfig(mode: mode, latency: Duration.zero),
        ),
        if (read != null)
          organizationRepositoryProvider.overrideWithValue(_FixedRead(read)),
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

    expect(tester.takeException(), isNull, reason: '$name must fit');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$outDir/$name.png'),
    );
  }

  OrganizationSnapshot snapshotOf(String tenantId, {bool usage = true}) {
    final store = PlatformTenantStore(clock: () => now);
    return MockOrganizationRepository.project(
      store.byId(tenantId)!,
      now: now.subtract(const Duration(hours: 3)),
      usage: usage,
    );
  }

  /// The canonical record with two limits pushed to the factual edges no
  /// fixture tenant sits on: detachments exactly at the limit, members over
  /// a lowered override.
  OrganizationSnapshot atAndOver(String tenantId) {
    final base = snapshotOf(tenantId);
    return OrganizationSnapshot(
      tenantId: base.tenantId,
      displayName: base.displayName,
      lifecycle: base.lifecycle,
      createdAt: base.createdAt,
      mainAdminName: base.mainAdminName,
      subscription: base.subscription,
      readAt: now,
      limits: OrganizationLimits(
        usageIncluded: true,
        items: [
          for (final line in base.limits.items)
            switch (line.key) {
              PlanLimitKey.detachments => OrganizationLimit(
                  key: line.key,
                  effective: 20,
                  planDefault: line.planDefault,
                  overridden: true,
                  usage: 20,
                ),
              PlanLimitKey.members => OrganizationLimit(
                  key: line.key,
                  effective: 200,
                  planDefault: line.planDefault,
                  overridden: true,
                  usage: 233,
                ),
              _ => line,
            },
        ],
      ),
    );
  }

  const org = OrganizationPage.routePath;
  const plan = PlanPage.routePath;

  testWidgets('01 organization 390 light', (tester) async {
    await shot(tester, name: '01-org-390-light', location: org);
  }, skip: outDir == null);

  testWidgets('02 organization 320 x1.6', (tester) async {
    await shot(
      tester,
      name: '02-org-320-1.6x',
      location: org,
      width: 320,
      height: 1700,
      textScale: 1.6,
    );
  }, skip: outDir == null);

  testWidgets('03 organization 900 light', (tester) async {
    await shot(
      tester,
      name: '03-org-900-light',
      location: org,
      width: 900,
      height: 900,
    );
  }, skip: outDir == null);

  testWidgets('04 organization offline cached dark cyber', (tester) async {
    await shot(
      tester,
      name: '04-org-offline-cached-dark-cyber',
      location: org,
      theme: AppThemeChoice.darkCyber,
      read: Offline(cached: snapshotOf('saas_hilal')),
    );
  }, skip: outDir == null);

  testWidgets('05 plan basic 390 light', (tester) async {
    await shot(
      tester,
      name: '05-plan-basic-390-light',
      location: plan,
      tenantId: 'saas_wadi',
      height: 2300,
    );
  }, skip: outDir == null);

  testWidgets('06 plan standard override 390 dark cyber', (tester) async {
    await shot(
      tester,
      name: '06-plan-standard-390-dark-cyber',
      location: plan,
      tenantId: 'saas_sahel',
      theme: AppThemeChoice.darkCyber,
      height: 2300,
    );
  }, skip: outDir == null);

  testWidgets('07 plan advanced 390 purple arena', (tester) async {
    await shot(
      tester,
      name: '07-plan-advanced-390-purple-arena',
      location: plan,
      theme: AppThemeChoice.purpleArena,
      height: 2300,
    );
  }, skip: outDir == null);

  testWidgets('08 plan grace over-limit 320 x1.6', (tester) async {
    await shot(
      tester,
      name: '08-plan-grace-320-1.6x',
      location: plan,
      tenantId: 'saas_afiah',
      read: Success(atAndOver('saas_afiah')),
      width: 320,
      height: 3600,
      textScale: 1.6,
    );
  }, skip: outDir == null);

  testWidgets('09 plan 600 light', (tester) async {
    await shot(
      tester,
      name: '09-plan-600-light',
      location: plan,
      width: 600,
      height: 2100,
    );
  }, skip: outDir == null);

  testWidgets('10 plan 900 light', (tester) async {
    await shot(
      tester,
      name: '10-plan-900-light',
      location: plan,
      tenantId: 'saas_afiah',
      read: Success(atAndOver('saas_afiah')),
      width: 900,
      height: 1500,
    );
  }, skip: outDir == null);

  testWidgets('11 plan eye protection', (tester) async {
    await shot(
      tester,
      name: '11-plan-eye-protect',
      location: plan,
      eyeProtect: true,
      height: 2300,
    );
  }, skip: outDir == null);

  testWidgets('12 plan stale cached', (tester) async {
    await shot(
      tester,
      name: '12-plan-stale',
      location: plan,
      mode: MockOrganizationMode.stale,
      height: 2500,
    );
  }, skip: outDir == null);

  testWidgets('13 plan unsupported data', (tester) async {
    await shot(
      tester,
      name: '13-plan-unsupported',
      location: plan,
      mode: MockOrganizationMode.unsupported,
      height: 2400,
    );
  }, skip: outDir == null);

  testWidgets('14 plan simple admin', (tester) async {
    await shot(
      tester,
      name: '14-plan-simple-admin-390',
      location: plan,
      simple: true,
      height: 2300,
    );
  }, skip: outDir == null);

  testWidgets('15 plan no plan trial dark cyber reduced motion',
      (tester) async {
    await shot(
      tester,
      name: '15-plan-no-plan-trial-dark-cyber',
      location: plan,
      tenantId: 'saas_nabd',
      theme: AppThemeChoice.darkCyber,
      reduceMotion: true,
      height: 1800,
    );
  }, skip: outDir == null);

  testWidgets('16 organization offline without cache', (tester) async {
    await shot(
      tester,
      name: '16-org-offline-no-cache',
      location: org,
      mode: MockOrganizationMode.offline,
      height: 900,
    );
  }, skip: outDir == null);
}

class _FixedRead implements OrganizationRepository {
  const _FixedRead(this.result);
  final Result<OrganizationSnapshot> result;

  @override
  Future<Result<OrganizationSnapshot>> readCurrent() async => result;
}
