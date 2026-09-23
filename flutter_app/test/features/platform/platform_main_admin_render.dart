@Tags(['render'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/theme_choice.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_platform_main_admin_repository.dart';
import 'package:mtm/features/platform/data/platform_main_admin_fixtures.dart';
import 'package:mtm/features/platform/data/platform_main_admin_providers.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/domain/platform_main_admin_models.dart';
import 'package:mtm/features/platform/domain/platform_main_admin_repository.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_routes.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

/// Deliberate Point 14 visual-review harness. PNGs stay outside the repository.
///
/// MTM_RENDER_DIR=/tmp/mtm-main-admin flutter test
/// test/features/platform/platform_main_admin_render.dart \
///   --tags render --update-goldens
void main() {
  final outDir = Platform.environment['MTM_RENDER_DIR'];
  final now = DateTime.utc(2026, 9, 11, 9);

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

  /// A seat read built from the canonical store, optionally forcing the
  /// tenant lifecycle and the holder's status — for the combinations no
  /// fixture tenant carries (account suspended *and* tenant suspended).
  MainAdminAccountSnapshot snapshotFor(
    String tenantId, {
    SaasTenantStatus? tenantStatus,
    bool suspendAccount = false,
  }) {
    final store = PlatformTenantStore(clock: () => now);
    final tenant = store.byId(tenantId)!;
    final state = MainAdminFixtures.derive(tenant, now: now);
    final current = state.current;
    return MainAdminAccountSnapshot(
      tenant: MainAdminTenantReference(
        tenantId: tenant.id,
        displayName: tenant.displayName,
        lifecycleStatus: tenantStatus ?? tenant.tenantStatus,
        lifecycleVersion: tenant.tenantVersion,
      ),
      revision: state.revision,
      current: suspendAccount
          ? MainAdminAccount(
              accountId: current.accountId,
              displayName: current.displayName,
              loginEmail: current.loginEmail,
              status: MainAdminAccountStatus.suspended,
              createdAt: current.createdAt,
              activatedAt: current.activatedAt ?? current.createdAt,
              suspension: MainAdminSuspension(
                suspendedAt: now.subtract(const Duration(days: 2)),
                reason: MainAdminFixtures.suspensionReason,
              ),
            )
          : current,
      replacement: state.replacement,
      readAt: now,
    );
  }

  Future<void> shot(
    WidgetTester tester, {
    required String name,
    required String location,
    AppThemeChoice theme = AppThemeChoice.light,
    MockMainAdminMode mode = MockMainAdminMode.loaded,
    Result<MainAdminAccountSnapshot>? read,
    double width = 390,
    double height = 1300,
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
        mainAdminMockConfigProvider.overrideWithValue(
          MainAdminMockConfig(mode: mode, latency: Duration.zero),
        ),
        if (read != null)
          platformMainAdminRepositoryProvider.overrideWithValue(
            _FixedReadRepository(read),
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

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('tenant detail summary 390 light', (tester) async {
    await shot(
      tester,
      name: '01-summary-390-light',
      location: SaasTenantRoutes.detail(MainAdminFixtures.replacementTenantId),
      height: 1000,
      interact: (tester) async {
        await tester.scrollUntilVisible(
          find.byKey(const Key('open-tenant-main-admin')),
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text(S.mainAdminSummaryTitle));
      },
    );
  }, skip: outDir == null);

  testWidgets('active management 390 light', (tester) async {
    await shot(
      tester,
      name: '02-active-390-light',
      location: SaasTenantRoutes.mainAdmin('saas_hilal'),
    );
  }, skip: outDir == null);

  testWidgets('pending setup 390 dark cyber', (tester) async {
    await shot(
      tester,
      name: '03-pending-setup-390-dark-cyber',
      location:
          SaasTenantRoutes.mainAdmin(MainAdminFixtures.pendingSetupTenantId),
      theme: AppThemeChoice.darkCyber,
    );
  }, skip: outDir == null);

  testWidgets('suspended account 390 dark cyber', (tester) async {
    await shot(
      tester,
      name: '04-suspended-390-dark-cyber',
      location: SaasTenantRoutes.mainAdmin(
        MainAdminFixtures.suspendedAccountTenantId,
      ),
      theme: AppThemeChoice.darkCyber,
    );
  }, skip: outDir == null);

  testWidgets('pending replacement 390 purple arena', (tester) async {
    await shot(
      tester,
      name: '05-replacement-390-purple-arena',
      location:
          SaasTenantRoutes.mainAdmin(MainAdminFixtures.replacementTenantId),
      theme: AppThemeChoice.purpleArena,
      height: 1700,
    );
  }, skip: outDir == null);

  testWidgets('replace page with validation 390 light', (tester) async {
    await shot(
      tester,
      name: '06-replace-390-light',
      location: SaasTenantRoutes.mainAdminReplace('saas_hilal'),
      height: 1000,
      interact: (tester) => tapKey(tester, 'main-admin-replace-submit'),
    );
  }, skip: outDir == null);

  testWidgets('pending replacement 320 at 1.6x', (tester) async {
    await shot(
      tester,
      name: '07-replacement-320-large-text',
      location:
          SaasTenantRoutes.mainAdmin(MainAdminFixtures.replacementTenantId),
      theme: AppThemeChoice.darkCyber,
      width: 320,
      height: 3200,
      textScale: 1.6,
    );
  }, skip: outDir == null);

  testWidgets('account and tenant both suspended 600 light', (tester) async {
    await shot(
      tester,
      name: '08-both-suspended-600-light',
      location: SaasTenantRoutes.mainAdmin(MainAdminFixtures.suspendedTenantId),
      read: Success(
        snapshotFor(
          MainAdminFixtures.suspendedTenantId,
          suspendAccount: true,
        ),
      ),
      width: 600,
      height: 1300,
    );
  }, skip: outDir == null);

  testWidgets('pending replacement 900 light', (tester) async {
    await shot(
      tester,
      name: '09-replacement-900-light',
      location:
          SaasTenantRoutes.mainAdmin(MainAdminFixtures.replacementTenantId),
      width: 900,
      height: 1200,
    );
  }, skip: outDir == null);

  testWidgets('eye protection pending setup 390', (tester) async {
    await shot(
      tester,
      name: '10-pending-setup-390-eye-protection',
      location:
          SaasTenantRoutes.mainAdmin(MainAdminFixtures.pendingSetupTenantId),
      eyeProtect: true,
    );
  }, skip: outDir == null);

  testWidgets('offline cached 390 light', (tester) async {
    await shot(
      tester,
      name: '11-offline-cached-390-light',
      location: SaasTenantRoutes.mainAdmin('saas_hilal'),
      read: Offline(cached: snapshotFor('saas_hilal')),
    );
  }, skip: outDir == null);

  testWidgets('unsupported fail-closed 390 dark cyber', (tester) async {
    await shot(
      tester,
      name: '12-unsupported-390-dark-cyber',
      location: SaasTenantRoutes.mainAdmin('saas_hilal'),
      theme: AppThemeChoice.darkCyber,
      mode: MockMainAdminMode.unsupportedState,
    );
  }, skip: outDir == null);

  testWidgets('recent auth required 390 light', (tester) async {
    await shot(
      tester,
      name: '13-recent-auth-390-light',
      location:
          SaasTenantRoutes.mainAdmin(MainAdminFixtures.pendingSetupTenantId),
      mode: MockMainAdminMode.recentAuthRequired,
      height: 844,
      interact: (tester) async {
        await tapKey(tester, 'main-admin-action-resend_setup');
        await tester
            .tap(find.byKey(const Key('platform-confirmation-confirm')));
      },
    );
  }, skip: outDir == null);

  testWidgets('suspend confirmation 320 at 1.6x', (tester) async {
    await shot(
      tester,
      name: '14-suspend-dialog-320-large-text',
      location: SaasTenantRoutes.mainAdmin('saas_hilal'),
      width: 320,
      height: 900,
      textScale: 1.6,
      interact: (tester) async {
        await tapKey(tester, 'main-admin-action-suspend');
        await tester.enterText(
          find.byKey(const Key('main-admin-suspend-reason')),
          MainAdminFixtures.suspensionReason,
        );
      },
    );
  }, skip: outDir == null);

  testWidgets('cancel replacement confirmation 390 purple arena',
      (tester) async {
    await shot(
      tester,
      name: '15-cancel-dialog-390-purple-arena',
      location:
          SaasTenantRoutes.mainAdmin(MainAdminFixtures.replacementTenantId),
      theme: AppThemeChoice.purpleArena,
      height: 844,
      interact: (tester) =>
          tapKey(tester, 'main-admin-action-cancel_replacement'),
    );
  }, skip: outDir == null);

  testWidgets('reduced motion suspended account 390', (tester) async {
    await shot(
      tester,
      name: '16-suspended-390-reduced-motion',
      location: SaasTenantRoutes.mainAdmin(
        MainAdminFixtures.suspendedAccountTenantId,
      ),
      theme: AppThemeChoice.purpleArena,
      reduceMotion: true,
      interact: (tester) => tapKey(tester, 'main-admin-action-reactivate'),
    );
  }, skip: outDir == null);
}

class _FixedReadRepository implements PlatformMainAdminRepository {
  const _FixedReadRepository(this.read);

  final Result<MainAdminAccountSnapshot> read;

  @override
  Future<Result<MainAdminAccountSnapshot>> load(String tenantId) async => read;

  @override
  Future<Result<MainAdminMutationResult>> cancelReplacement(
          CancelMainAdminReplacementCommand command) =>
      throw UnsupportedError('read only');

  @override
  Future<Result<MainAdminMutationResult>> reactivate(
          ReactivateMainAdminCommand command) =>
      throw UnsupportedError('read only');

  @override
  Future<Result<MainAdminMutationResult>> replace(
          ReplaceMainAdminCommand command) =>
      throw UnsupportedError('read only');

  @override
  Future<Result<MainAdminMutationResult>> resendSetup(
          ResendMainAdminSetupCommand command) =>
      throw UnsupportedError('read only');

  @override
  Future<Result<MainAdminMutationResult>> suspend(
          SuspendMainAdminCommand command) =>
      throw UnsupportedError('read only');
}
