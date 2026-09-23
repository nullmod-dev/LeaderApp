import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_platform_overview_repository.dart';
import 'package:mtm/features/platform/data/platform_overview_providers.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/data/tenant_lifecycle_providers.dart';
import 'package:mtm/features/platform/data/mock_tenant_lifecycle_repository.dart';
import 'package:mtm/features/platform/domain/platform_area.dart';
import 'package:mtm/features/platform/domain/platform_overview_models.dart';
import 'package:mtm/features/platform/domain/platform_overview_repository.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';
import 'package:mtm/features/platform/presentation/platform_operations_routes.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_routes.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

void main() {
  final now = DateTime.utc(2026, 9, 8, 16);

  Future<PlatformOverviewSnapshot> snapshot() async {
    final result = await MockPlatformOverviewRepository(
      clock: () => now,
      latency: Duration.zero,
    ).loadOverview();
    return (result as Success<PlatformOverviewSnapshot>).data;
  }

  ProviderContainer containerFor(PlatformOverviewRepository repository,
      {TenantRepositoryWatch? watch}) {
    return platformContainer(
      superAdmin,
      watch: watch,
      overrides: [
        clockProvider.overrideWithValue(() => now),
        platformOverviewRepositoryProvider.overrideWithValue(repository),
      ],
    );
  }

  group('repository states', () {
    testWidgets('loading is a designed skeleton, not an empty dashboard',
        (tester) async {
      final pending = Completer<Result<PlatformOverviewSnapshot>>();
      await bootPlatform(tester, containerFor(_Repository(pending.future)));

      expect(
          find.byKey(const Key('platform-overview-loading')), findsOneWidget);
      expect(find.byKey(const Key('platform-overview-loaded')), findsNothing);
    });

    testWidgets('loaded data shows decision-first sections', (tester) async {
      await bootPlatform(
        tester,
        containerFor(_Repository(Future.value(Success(await snapshot())))),
        height: 1000,
      );

      expect(find.byKey(const Key('platform-overview-loaded')), findsOneWidget);
      // The app bar names the page; the body opens with the status strip
      // rather than repeating «منصة ليدر» under a 52 dp tile (Phase 2, P1-6).
      expect(find.text(S.platformBrand), findsNothing);
      expect(
        find.byKey(const Key('platform-overview-freshness')),
        findsOneWidget,
      );
      expect(find.textContaining('MTM'), findsNothing);
      expect(find.text(S.platformOverviewAttention), findsOneWidget);
      expect(find.text(S.platformOverviewSummary), findsOneWidget);
      expect(find.byKey(const Key('platform-overview-health')), findsOneWidget);
      expect(
          find.byKey(const Key('platform-overview-activity')), findsOneWidget);
    });

    testWidgets('failure uses safe client copy and offers retry',
        (tester) async {
      await bootPlatform(
        tester,
        containerFor(_Repository(Future.value(
          const Failure('raw backend exception', code: 'server'),
        ))),
      );

      expect(
          find.byKey(const Key('platform-overview-failure')), findsOneWidget);
      expect(find.text('raw backend exception'), findsNothing);
      expect(find.text(S.retry), findsOneWidget);
    });

    testWidgets('offline without cache is not described as empty data',
        (tester) async {
      await bootPlatform(
        tester,
        containerFor(_Repository(Future.value(const Offline()))),
      );

      expect(
        find.byKey(const Key('platform-overview-offline-empty')),
        findsOneWidget,
      );
      expect(find.text(S.offlineTitle), findsOneWidget);
      expect(find.text(S.platformOverviewMinimalTitle), findsNothing);
    });

    testWidgets('offline cache stays useful and is labelled truthfully',
        (tester) async {
      await bootPlatform(
        tester,
        containerFor(_Repository(Future.value(
          Offline(cached: await snapshot()),
        ))),
      );

      expect(find.byKey(const Key('platform-overview-loaded')), findsOneWidget);
      expect(find.text(S.platformOverviewOfflineCached), findsOneWidget);
    });

    testWidgets(
        'stale success is marked without claiming the device is offline',
        (tester) async {
      await bootPlatform(
        tester,
        containerFor(_Repository(Future.value(
          Success(await snapshot(), stale: true),
        ))),
      );

      expect(find.text(S.staleData), findsOneWidget);
      expect(find.text(S.platformOverviewOfflineCached), findsNothing);
    });

    testWidgets('minimal success hides attention and states that data is empty',
        (tester) async {
      await bootPlatform(
        tester,
        containerFor(_Repository(Future.value(
          Success(PlatformOverviewSnapshot.empty(now)),
        ))),
      );

      expect(
          find.byKey(const Key('platform-overview-minimal')), findsOneWidget);
      expect(find.text(S.platformOverviewMinimalTitle), findsOneWidget);
      expect(
        find.byKey(const Key('platform-overview-attention')),
        findsNothing,
      );
    });
  });

  group('navigation and isolation', () {
    testWidgets('a tenant metric opens the real Point 4 tenants landing',
        (tester) async {
      final router = await bootPlatform(
        tester,
        containerFor(_Repository(Future.value(Success(await snapshot())))),
        height: 1000,
      );
      await tester.ensureVisible(
        find.byKey(const Key('platform-metric-tenants')),
      );
      await tester.tap(find.byKey(const Key('platform-metric-tenants')));
      await settlePlatform(tester);

      expect(locationOf(router), PlatformArea.tenants.route);
    });

    testWidgets('a security attention row opens the real security module',
        (tester) async {
      final router = await bootPlatform(
        tester,
        containerFor(_Repository(Future.value(Success(await snapshot())))),
        height: 1000,
      );
      await tester.tap(
        find.byKey(const Key('platform-attention-attention_security')),
      );
      await settlePlatform(tester);

      expect(locationOf(router), PlatformOperationsRoutes.security);
    });

    testWidgets('deletion attention names and opens the concrete tenant',
        (tester) async {
      final container = platformContainer(superAdmin, overrides: [
        clockProvider.overrideWithValue(() => now),
        tenantLifecycleRepositoryProvider.overrideWith((ref) {
          return MockTenantLifecycleRepository(
            store: ref.watch(platformTenantStoreProvider),
            clock: () => now,
            latency: Duration.zero,
          );
        }),
        platformOverviewRepositoryProvider.overrideWith((ref) {
          return MockPlatformOverviewRepository(
            clock: () => now,
            store: ref.watch(platformTenantStoreProvider),
            latency: Duration.zero,
          );
        }),
      ]);
      final tenant =
          container.read(platformTenantStoreProvider).byId('saas_hilal')!;
      await container
          .read(tenantLifecycleRepositoryProvider)
          .beginDeletion(BeginTenantDeletionCommand(
            tenantId: tenant.id,
            expectedVersion: tenant.tenantVersion,
            idempotencyKey: 'overview-pending-navigation',
            reason: 'طلب حذف موثق',
          ));

      final router = await bootPlatform(tester, container, height: 1200);
      expect(find.textContaining(tenant.displayName), findsWidgets);
      expect(find.textContaining('متبقي ٣٠ يوماً'), findsOneWidget);

      await tester.tap(find.byKey(
        Key('platform-attention-attention_tenant_deletion_pending_${tenant.id}'),
      ));
      await settlePlatform(tester);

      expect(locationOf(router), SaasTenantRoutes.detail(tenant.id));
    });

    testWidgets('the overview reads no tenant operational repository',
        (tester) async {
      final watch = TenantRepositoryWatch();
      await bootPlatform(
        tester,
        containerFor(
          _Repository(Future.value(Success(await snapshot()))),
          watch: watch,
        ),
      );

      expect(watch.built, isEmpty);
    });
  });

  group('responsive overview composition', () {
    for (final (label, width, scale) in [
      ('320 dp at 1.6 text scale', 320.0, 1.6),
      ('expanded 900 dp', 900.0, 1.0),
    ]) {
      testWidgets('$label renders without layout errors', (tester) async {
        await bootPlatform(
          tester,
          containerFor(_Repository(Future.value(Success(await snapshot())))),
          width: width,
          height: 1200,
          textScale: scale,
        );

        expect(
            find.byKey(const Key('platform-overview-loaded')), findsOneWidget);
      });
    }
  });
}

class _Repository implements PlatformOverviewRepository {
  const _Repository(this.result);

  final Future<Result<PlatformOverviewSnapshot>> result;

  @override
  Future<Result<PlatformOverviewSnapshot>> loadOverview() => result;
}
