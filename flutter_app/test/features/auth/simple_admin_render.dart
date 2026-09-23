@Tags(['render'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_presets.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/theme_choice.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/organization/data/mock_organization_repository.dart';
import 'package:mtm/features/organization/data/organization_providers.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/data/tenant_lifecycle_providers.dart';
import 'package:mtm/features/tenant_feature/data/tenant_feature_providers.dart';
import 'package:mtm/features/tenant_feature/domain/tenant_feature_models.dart';

import '../platform/platform_harness.dart';

/// Deliberate Point 16 visual-review harness — the Simple Admin experience.
/// PNGs stay outside the repository.
///
///     MTM_RENDER_DIR=/tmp/mtm-simple-admin flutter test \
///       test/features/auth/simple_admin_render.dart --tags render --update-goldens
void main() {
  final outDir = Platform.environment['MTM_RENDER_DIR'];
  final now = DateTime.utc(2026, 9, 12, 9);
  const mine = 'd_dam_central';

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

  AuthUser simple(Capabilities caps) => AuthUser(
        id: 'u_render_simple',
        name: 'سامر الحلبي',
        email: 's.halabi@mtm.org',
        role: AuthRole.admin,
        saasTenantId: kDemoSaasTenantId,
        capabilities: caps,
        orgName: 'MTM',
      );

  Capabilities only(Set<String> keys) => Capabilities(scoped: {mine: keys});

  final minimal = simple(only(const {Cap.detachmentView}));
  final operations = simple(only(const {
    Cap.detachmentView,
    Cap.memberView,
    Cap.shiftManage,
    Cap.shiftAssign,
    Cap.shiftAttendanceRecord,
  }));
  final inventory = simple(only(const {
    Cap.detachmentView,
    Cap.inventoryAdjust,
    Cap.inventoryItemManage,
  }));
  final reports = simple(only(const {Cap.detachmentView, Cap.statsView}));
  final archiver = simple(only(const {
    Cap.detachmentView,
    Cap.detachmentArchive,
    Cap.memberView,
  }));
  final broad = simple(() {
    final preset = CapabilityPreset.subAdmin.grant(detachments: const [mine]);
    return preset.copyWith(scoped: {
      mine: {...preset.scoped[mine]!, Cap.announcementPublish},
    });
  }());

  Future<void> shot(
    WidgetTester tester, {
    required String name,
    required String location,
    AuthUser? user,
    String? pushed,
    AppThemeChoice theme = AppThemeChoice.light,
    Set<TenantFeatureKey> disabled = const {},
    SessionAccess access = SessionAccess.normal,
    MockOrganizationMode orgMode = MockOrganizationMode.loaded,
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
      user ?? simpleAdmin,
      overrides: [
        clockProvider.overrideWithValue(() => now),
        effectiveSessionAccessProvider.overrideWithValue(access),
        organizationMockConfigProvider.overrideWithValue(
          OrganizationMockConfig(mode: orgMode, latency: Duration.zero),
        ),
      ],
    );
    final store = container.read(platformTenantStoreProvider);
    for (final key in TenantFeatureKey.values) {
      store.updateFeature(kDemoSaasTenantId, key, !disabled.contains(key));
    }
    container.read(tenantFeatureRevisionProvider.notifier).changed();

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
    if (pushed != null) {
      router.push(pushed);
      await settlePlatform(tester);
    }

    expect(tester.takeException(), isNull, reason: '$name must fit');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$outDir/$name.png'),
    );
  }

  final skip = outDir == null;

  testWidgets('01 home 390 light', (tester) async {
    await shot(tester, name: '01-home-390-light', location: '/home');
  }, skip: skip);

  testWidgets('02 home 320 x1.6', (tester) async {
    await shot(
      tester,
      name: '02-home-320-1.6x',
      location: '/home',
      width: 320,
      height: 2400,
      textScale: 1.6,
    );
  }, skip: skip);

  testWidgets('03 more minimal grant', (tester) async {
    await shot(
      tester,
      name: '03-more-minimal-390-light',
      location: '/more',
      user: minimal,
      height: 1700,
    );
  }, skip: skip);

  testWidgets('04 more broad grant dark cyber', (tester) async {
    await shot(
      tester,
      name: '04-more-broad-390-dark-cyber',
      location: '/more',
      user: broad,
      theme: AppThemeChoice.darkCyber,
      height: 1700,
    );
  }, skip: skip);

  testWidgets('05 feature disabled inventory', (tester) async {
    await shot(
      tester,
      name: '05-feature-disabled-inventory-390-light',
      location: '/detachment/$mine/storage',
      user: broad,
      disabled: const {TenantFeatureKey.inventory},
      height: 900,
    );
  }, skip: skip);

  testWidgets('06 missing capability stats denied', (tester) async {
    await shot(
      tester,
      name: '06-stats-not-permitted-390-light',
      location: '/detachment/$mine/stats',
      user: operations,
      height: 900,
    );
  }, skip: skip);

  testWidgets('07 minimal grant detachment tabs dark cyber', (tester) async {
    await shot(
      tester,
      name: '07-minimal-tabs-390-dark-cyber',
      location: '/detachment/$mine/storage',
      user: minimal,
      theme: AppThemeChoice.darkCyber,
      height: 1200,
    );
  }, skip: skip);

  testWidgets('08 tenant suspended', (tester) async {
    await shot(
      tester,
      name: '08-tenant-suspended-390-light',
      location: '/detachment/$mine/team',
      access: const SessionAccess(tenant: SaasTenantStatus.suspended),
      height: 900,
    );
  }, skip: skip);

  testWidgets('09 organization simple admin', (tester) async {
    await shot(
      tester,
      name: '09-organization-390-light',
      location: '/more/organization',
      height: 1600,
    );
  }, skip: skip);

  testWidgets('10 plan simple admin (limits as maxima)', (tester) async {
    await shot(
      tester,
      name: '10-plan-390-light',
      location: '/more/plan',
      height: 2400,
    );
  }, skip: skip);

  testWidgets('11 inventory grant storage tab', (tester) async {
    await shot(
      tester,
      name: '11-inventory-storage-390-light',
      location: '/detachment/$mine/storage',
      user: inventory,
      height: 1500,
    );
  }, skip: skip);

  testWidgets('12 reports grant report composer', (tester) async {
    await shot(
      tester,
      name: '12-reports-composer-390-light',
      location: '/detachment/$mine/report',
      user: reports,
      height: 1800,
    );
  }, skip: skip);

  testWidgets('13 offline organization', (tester) async {
    await shot(
      tester,
      name: '13-organization-offline-390-dark-cyber',
      location: '/more/organization',
      theme: AppThemeChoice.darkCyber,
      orgMode: MockOrganizationMode.offline,
      height: 1200,
    );
  }, skip: skip);

  testWidgets('14 status-only edit form eye protection', (tester) async {
    await shot(
      tester,
      name: '14-edit-status-only-390-eye-protect',
      location: '/detachment',
      pushed: '/detachment/$mine/edit',
      user: archiver,
      eyeProtect: true,
      height: 1400,
    );
  }, skip: skip);

  testWidgets('15 status-only edit form 320 x1.6', (tester) async {
    await shot(
      tester,
      name: '15-edit-status-only-320-1.6x',
      location: '/detachment',
      pushed: '/detachment/$mine/edit',
      user: archiver,
      width: 320,
      height: 2000,
      textScale: 1.6,
    );
  }, skip: skip);

  testWidgets('16 notification prefs modules off purple arena', (tester) async {
    await shot(
      tester,
      name: '16-notif-prefs-modules-off-390-purple-arena',
      location: '/more/notifications',
      user: broad,
      theme: AppThemeChoice.purpleArena,
      disabled: const {TenantFeatureKey.inventory, TenantFeatureKey.workshops},
      height: 900,
    );
  }, skip: skip);

  testWidgets('17 stats denied 320 x1.6', (tester) async {
    await shot(
      tester,
      name: '17-stats-not-permitted-320-1.6x',
      location: '/detachment/$mine/stats',
      user: archiver,
      width: 320,
      height: 1200,
      textScale: 1.6,
    );
  }, skip: skip);

  testWidgets('18 home broad dark cyber reduced motion', (tester) async {
    await shot(
      tester,
      name: '18-home-broad-390-dark-cyber-reduced-motion',
      location: '/home',
      user: broad,
      theme: AppThemeChoice.darkCyber,
      reduceMotion: true,
      height: 2000,
    );
  }, skip: skip);
}
