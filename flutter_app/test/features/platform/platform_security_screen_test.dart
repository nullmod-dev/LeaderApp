import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_platform_security_repository.dart';
import 'package:mtm/features/platform/data/platform_operations_providers.dart';
import 'package:mtm/features/platform/domain/platform_security_models.dart';
import 'package:mtm/features/platform/domain/platform_security_repository.dart';
import 'package:mtm/features/platform/presentation/platform_operations_routes.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_routes.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10, 16);

  ProviderContainer containerFor({
    MockPlatformSecurityMode mode = MockPlatformSecurityMode.mixed,
    PlatformSecurityRepository? repository,
    TenantRepositoryWatch? watch,
  }) =>
      platformContainer(
        superAdmin,
        watch: watch,
        overrides: [
          clockProvider.overrideWithValue(() => now),
          platformSecurityRepositoryProvider.overrideWith((ref) {
            return repository ??
                MockPlatformSecurityRepository(
                  fixtures: ref.watch(platformOperationsFixturesProvider),
                  mode: mode,
                  latency: Duration.zero,
                );
          }),
        ],
      );

  Future<GoRouter> open(
    WidgetTester tester, {
    MockPlatformSecurityMode mode = MockPlatformSecurityMode.mixed,
    PlatformSecurityRepository? repository,
    TenantRepositoryWatch? watch,
    double width = 390,
    double height = 1100,
    double textScale = 1,
  }) async {
    final container = containerFor(
      mode: mode,
      repository: repository,
      watch: watch,
    );
    final router = await bootPlatform(
      tester,
      container,
      width: width,
      height: height,
      textScale: textScale,
    );
    router.go(PlatformOperationsRoutes.security);
    await settlePlatform(tester);
    return router;
  }

  testWidgets('loading is a designed state', (tester) async {
    await open(tester, repository: _PendingSecurityRepository());
    expect(find.byKey(const Key('platform-security-loading')), findsOneWidget);
    expect(find.byKey(const Key('platform-security-loaded')), findsNothing);
  });

  testWidgets('mixed alerts expose severity and safe alert context',
      (tester) async {
    await open(tester);
    expect(find.byKey(const Key('platform-security-loaded')), findsOneWidget);
    expect(find.text(S.platformSecuritySeverityCritical), findsWidgets);
    expect(find.text(S.platformSecuritySeverityWarning), findsWidgets);
    expect(find.text(S.platformSecuritySeverityInfo), findsWidgets);
    expect(find.text(S.platformSecurityCategoryAuthentication), findsWidgets);
  });

  testWidgets('no-alert state makes only a snapshot-bounded claim',
      (tester) async {
    await open(tester, mode: MockPlatformSecurityMode.noAlerts);
    expect(
      find.byKey(const Key('platform-security-no-alerts')),
      findsOneWidget,
    );
    expect(find.text(S.platformSecurityNoAlertsTitle), findsWidgets);
    expect(find.textContaining('100%'), findsNothing);
    expect(find.textContaining('آمنة تماما'), findsNothing);
  });

  testWidgets('unknown alert state remains visible and non-benign',
      (tester) async {
    await open(tester, mode: MockPlatformSecurityMode.unknown);
    expect(find.text(S.platformSecuritySeverityUnknown), findsWidgets);
    expect(find.text(S.platformSecurityCategoryUnknown), findsOneWidget);
    expect(find.text(S.platformSecuritySummaryUnknown), findsOneWidget);
    expect(find.byKey(const Key('platform-security-no-alerts')), findsNothing);
  });

  testWidgets('stale and offline cache stay useful and labelled truthfully',
      (tester) async {
    await open(tester, mode: MockPlatformSecurityMode.stale);
    expect(find.byKey(const Key('platform-security-loaded')), findsOneWidget);
    expect(find.text(S.staleData), findsOneWidget);

    await open(tester, mode: MockPlatformSecurityMode.offlineWithCache);
    expect(find.byKey(const Key('platform-security-loaded')), findsOneWidget);
    expect(find.text(S.platformSecurityOfflineCached), findsOneWidget);
  });

  testWidgets('offline without cache and failure are safe retry states',
      (tester) async {
    await open(tester, mode: MockPlatformSecurityMode.offlineWithoutCache);
    expect(
      find.byKey(const Key('platform-security-offline-empty')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('platform-security-no-alerts')), findsNothing);

    await open(
      tester,
      repository: const _SecurityResultRepository(
        Failure('Bearer secret raw stack trace', code: 'server'),
      ),
    );
    expect(find.byKey(const Key('platform-security-failure')), findsOneWidget);
    expect(find.text('Bearer secret raw stack trace'), findsNothing);
    expect(find.text(S.retry), findsOneWidget);
  });

  testWidgets('valid tenant alert opens only the platform tenant resource',
      (tester) async {
    final router = await open(
      tester,
      mode: MockPlatformSecurityMode.tenantLinked,
    );
    await tester.tap(
      find.byKey(const Key('platform-security-tenant-security_tenant_sign_in')),
    );
    await settlePlatform(tester);
    expect(locationOf(router), SaasTenantRoutes.detail('saas_hilal'));
  });

  testWidgets('platform-wide alert has no dead tenant tap target',
      (tester) async {
    await open(tester, mode: MockPlatformSecurityMode.platformWide);
    expect(
      find.byKey(
          const Key('platform-security-tenant-security_repeated_sign_in')),
      findsNothing,
    );
  });

  testWidgets('an unknown tenant reference remains noninteractive',
      (tester) async {
    final snapshot = PlatformSecuritySnapshot(
      generatedAt: now,
      alerts: [
        PlatformSecurityAlert(
          id: 'missing_tenant',
          severity: PlatformSecurityAlertSeverity.warning,
          category: PlatformSecurityAlertCategory.authentication,
          title: 'تنبيه مرتبط بمرجع قديم',
          description: 'يبقى الوصف قابلا للقراءة من دون إنشاء رابط ميت.',
          detectedAt: now,
          affectedTenant: PlatformSecurityTenantReference(
            id: 'saas_missing',
            displayName: 'مرجع غير متاح',
            isDeleted: false,
          ),
        ),
      ],
    );
    await open(
      tester,
      repository: _SecurityResultRepository(Success(snapshot)),
    );

    expect(
      find.byKey(const Key('platform-security-alert-missing_tenant')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('platform-security-tenant-missing_tenant')),
      findsNothing,
    );
  });

  testWidgets('alert severity and action are announced explicitly',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester, mode: MockPlatformSecurityMode.tenantLinked);
    final node = tester.getSemantics(
      find.byKey(const Key('platform-security-alert-security_tenant_sign_in')),
    );
    expect(node.label, contains(S.platformSecuritySeverityCritical));
    expect(node.label, contains(S.platformSecurityOpenTenant));
    expect(node.flagsCollection.isButton, isTrue);
    expect(find.byTooltip(S.platformSecurityRefresh), findsOneWidget);
    semantics.dispose();
  });

  for (final (label, width, scale) in [
    ('320dp at 1.6 text scale', 320.0, 1.6),
    ('600dp', 600.0, 1.0),
    ('900dp', 900.0, 1.0),
  ]) {
    testWidgets('$label renders wrapped alerts without overflow',
        (tester) async {
      await open(
        tester,
        width: width,
        height: 1400,
        textScale: scale,
      );
      expect(find.byKey(const Key('platform-security-loaded')), findsOneWidget);
    });
  }

  testWidgets('security never initializes tenant operational repositories',
      (tester) async {
    final watch = TenantRepositoryWatch();
    await open(tester, watch: watch);
    expect(watch.built, isEmpty);
  });
}

class _PendingSecurityRepository implements PlatformSecurityRepository {
  final Completer<Result<PlatformSecuritySnapshot>> _pending = Completer();

  @override
  Future<Result<PlatformSecuritySnapshot>> loadSecurityAlerts() =>
      _pending.future;
}

class _SecurityResultRepository implements PlatformSecurityRepository {
  const _SecurityResultRepository(this.result);

  final Result<PlatformSecuritySnapshot> result;

  @override
  Future<Result<PlatformSecuritySnapshot>> loadSecurityAlerts() async => result;
}
