import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_saas_tenant_repository.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/domain/saas_tenant_models.dart';
import 'package:mtm/features/platform/domain/saas_tenant_repository.dart';
import 'package:mtm/features/platform/presentation/platform_shell.dart';
import 'package:mtm/features/platform/presentation/platform_tenants_page.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_create_page.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_detail_page.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_routes.dart';
import 'package:mtm/features/shell/main_shell.dart';

import 'platform_harness.dart';

/// Point 6 — `/platform/tenants`, the real subscriber list.
void main() {
  final now = DateTime.utc(2026, 9, 8, 16);

  List<Override> tenantOverrides({
    MockSaasTenantMode mode = MockSaasTenantMode.loaded,
  }) =>
      [
        clockProvider.overrideWithValue(() => now),
        saasTenantRepositoryProvider.overrideWith((ref) {
          return MockSaasTenantRepository(
            store: ref.watch(platformTenantStoreProvider),
            mode: mode,
            latency: Duration.zero,
          );
        }),
      ];

  /// Tall enough that all eight fixture rows are laid out — a `ListView` only
  /// builds what fits, and a row that was never built is indistinguishable
  /// from a row that is missing.
  Future<void> openList(
    WidgetTester tester,
    ProviderContainer container, {
    double height = 1800,
  }) async {
    final router = await bootPlatform(tester, container, height: height);
    router.go(SaasTenantRoutes.list);
    await settlePlatform(tester);
  }

  group('the populated list', () {
    testWidgets('replaces the Point 4 landing with real rows', (tester) async {
      await openList(
        tester,
        platformContainer(superAdmin, overrides: tenantOverrides()),
      );

      expect(find.byType(PlatformTenantsPage), findsOneWidget);
      expect(find.byKey(const Key('platform-tenant-row-saas_hilal')),
          findsOneWidget);
      expect(find.byKey(const Key('platform-tenants-count')), findsOneWidget);
      expect(find.text('٨ فرق'), findsOneWidget);
      // The reserved-section copy is gone.
      expect(find.text('هذه الوحدة لم تُبنَ بعد'), findsNothing);
    });

    testWidgets('offers exactly one write: registering a subscriber',
        (tester) async {
      await openList(
        tester,
        platformContainer(superAdmin, overrides: tenantOverrides()),
      );

      expect(find.byKey(const Key('platform-tenants-create')), findsOneWidget);
      // No lifecycle action exists anywhere on this screen.
      for (final label in const ['إيقاف', 'تفعيل', 'حذف', 'تعليق']) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('a row opens the tenant detail', (tester) async {
      final container =
          platformContainer(superAdmin, overrides: tenantOverrides());
      final router = await bootPlatform(tester, container, height: 1800);
      router.go(SaasTenantRoutes.list);
      await settlePlatform(tester);

      await tester.tap(find.byKey(const Key('platform-tenant-row-saas_afiah')));
      await settlePlatform(tester);

      // Asserted on the rendered page rather than on
      // `currentConfiguration.uri`: an imperative `push` inside a
      // `StatefulShellRoute` branch stacks on that branch's navigator and the
      // shell's matched location stays the branch root. That is go_router's
      // behaviour, it is what the existing `/platform/more/*` rows already do,
      // and what matters is that the operator is on the detail.
      expect(find.byType(SaasTenantDetailPage), findsOneWidget);
      expect(find.byType(PlatformTenantsPage), findsNothing);
      // Still inside the shell: the platform navigation never disappears.
      expect(find.byType(PlatformShell), findsOneWidget);
    });

    testWidgets('the create action opens the form', (tester) async {
      final container =
          platformContainer(superAdmin, overrides: tenantOverrides());
      final router = await bootPlatform(tester, container, height: 1800);
      router.go(SaasTenantRoutes.list);
      await settlePlatform(tester);

      await tester.tap(find.byKey(const Key('platform-tenants-create')));
      await settlePlatform(tester);

      expect(find.byType(SaasTenantCreatePage), findsOneWidget);
      expect(find.byType(PlatformTenantsPage), findsNothing);
    });
  });

  group('search and filter', () {
    testWidgets('search narrows the rows and the count', (tester) async {
      await openList(
        tester,
        platformContainer(superAdmin, overrides: tenantOverrides()),
      );

      await tester.enterText(
        find.byKey(const Key('platform-tenants-search')),
        'عافية',
      );
      await settlePlatform(tester);

      expect(find.byKey(const Key('platform-tenant-row-saas_afiah')),
          findsOneWidget);
      expect(find.byKey(const Key('platform-tenant-row-saas_hilal')),
          findsNothing);
      expect(find.text('فريق واحد'), findsOneWidget);
    });

    testWidgets('a status chip filters', (tester) async {
      await openList(
        tester,
        platformContainer(superAdmin, overrides: tenantOverrides()),
      );

      await tester.tap(find.byKey(const Key('platform-tenants-filter-trial')));
      await settlePlatform(tester);

      expect(find.text('فريقان'), findsOneWidget);
      expect(find.byKey(const Key('platform-tenant-row-saas_nabd')),
          findsOneWidget);
      expect(find.byKey(const Key('platform-tenant-row-saas_hilal')),
          findsNothing);
    });

    testWidgets('normal list exposes lifecycle filters but no deleted filter',
        (tester) async {
      await openList(
        tester,
        platformContainer(superAdmin, overrides: tenantOverrides()),
      );

      expect(
        find.byKey(const Key('platform-tenants-filter-suspended')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('platform-tenants-filter-deletion_pending')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('platform-tenants-filter-deleted')),
        findsNothing,
      );
      expect(find.text('الحالة التجارية أو حالة الوصول'), findsOneWidget);
    });

    testWidgets('no matches is a distinct state with a way out',
        (tester) async {
      await openList(
        tester,
        platformContainer(superAdmin, overrides: tenantOverrides()),
      );

      await tester.enterText(
        find.byKey(const Key('platform-tenants-search')),
        'لا يوجد فريق بهذا الاسم',
      );
      await settlePlatform(tester);

      expect(
          find.byKey(const Key('platform-tenants-no-results')), findsOneWidget);
      expect(find.byKey(const Key('platform-tenants-empty')), findsNothing);

      await tester.tap(find.text('إظهار كل الفرق'));
      await settlePlatform(tester);

      expect(find.byKey(const Key('platform-tenant-row-saas_hilal')),
          findsOneWidget);
    });

    testWidgets('an empty platform is a different state from no matches',
        (tester) async {
      await openList(
        tester,
        platformContainer(
          superAdmin,
          overrides: tenantOverrides(mode: MockSaasTenantMode.empty),
        ),
      );

      expect(find.byKey(const Key('platform-tenants-empty')), findsOneWidget);
      expect(
          find.byKey(const Key('platform-tenants-no-results')), findsNothing);
    });
  });

  group('offline and failure', () {
    testWidgets('offline with a cached copy shows the rows and says so',
        (tester) async {
      await openList(
        tester,
        platformContainer(
          superAdmin,
          overrides: tenantOverrides(mode: MockSaasTenantMode.offlineWithCache),
        ),
      );

      expect(find.byKey(const Key('platform-tenant-row-saas_hilal')),
          findsOneWidget);
      expect(find.byKey(const Key('platform-tenants-count')), findsOneWidget);
    });

    testWidgets('offline with nothing cached is an honest empty state',
        (tester) async {
      await openList(
        tester,
        platformContainer(
          superAdmin,
          overrides:
              tenantOverrides(mode: MockSaasTenantMode.offlineWithoutCache),
        ),
      );

      expect(find.byKey(const Key('platform-tenants-offline-empty')),
          findsOneWidget);
    });

    testWidgets('a failure shows retry copy and no exception text',
        (tester) async {
      await openList(
        tester,
        platformContainer(
          superAdmin,
          overrides: tenantOverrides(mode: MockSaasTenantMode.failure),
        ),
      );

      expect(find.byKey(const Key('platform-tenants-failure')), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });
  });

  group('paging', () {
    testWidgets('a cut list says so rather than hiding a customer',
        (tester) async {
      // A tiny page size is the only way to reach this state with eight
      // fixtures, which is the point: the note is reachable and tested rather
      // than a branch nothing ever runs.
      final container = platformContainer(
        superAdmin,
        overrides: [
          clockProvider.overrideWithValue(() => now),
          saasTenantRepositoryProvider.overrideWith((ref) {
            return _SmallPageRepository(
              MockSaasTenantRepository(
                store: ref.watch(platformTenantStoreProvider),
                latency: Duration.zero,
              ),
            );
          }),
        ],
      );
      await openList(tester, container);

      expect(
          find.byKey(const Key('platform-tenants-more-note')), findsOneWidget);
      expect(find.text('٨ فرق'), findsOneWidget);
    });
  });

  group('access and isolation', () {
    testWidgets('a tenant admin is refused every Point 6 location',
        (tester) async {
      ignoreKnownTenantComplaints();
      final router =
          await bootPlatform(tester, platformContainer(fullTenantAdmin));

      for (final location in [
        SaasTenantRoutes.list,
        SaasTenantRoutes.create,
        SaasTenantRoutes.detail('saas_hilal'),
      ]) {
        router.go(location);
        await settlePlatform(tester);

        expect(locationOf(router), '/home', reason: location);
        expect(find.byType(MainShell), findsOneWidget, reason: location);
        expect(find.byType(PlatformShell), findsNothing, reason: location);
      }
    });

    testWidgets('no tenant operational repository is built by any of them',
        (tester) async {
      final watch = TenantRepositoryWatch();
      final container = platformContainer(
        superAdmin,
        watch: watch,
        overrides: tenantOverrides(),
      );
      final router = await bootPlatform(tester, container, height: 1800);

      for (final location in [
        SaasTenantRoutes.list,
        SaasTenantRoutes.create,
        SaasTenantRoutes.detail('saas_hilal'),
      ]) {
        router.go(location);
        await settlePlatform(tester);
      }

      expect(watch.built, isEmpty);
    });
  });

  group('responsive and RTL', () {
    testWidgets('320 dp at a 1.6 text scale renders without overflow',
        (tester) async {
      final router = await bootPlatform(
        tester,
        platformContainer(superAdmin, overrides: tenantOverrides()),
        width: 320,
        height: 1400,
        textScale: 1.6,
      );
      router.go(SaasTenantRoutes.list);
      await settlePlatform(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(PlatformTenantsPage), findsOneWidget);
    });

    testWidgets('the expanded layout keeps the rail and the list',
        (tester) async {
      final router = await bootPlatform(
        tester,
        platformContainer(superAdmin, overrides: tenantOverrides()),
        width: 900,
        height: 1200,
      );
      router.go(SaasTenantRoutes.list);
      await settlePlatform(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(PlatformTenantsPage), findsOneWidget);
      expect(find.byKey(const Key('platform-tenant-row-saas_hilal')),
          findsOneWidget);
    });

    testWidgets('a Team Code lays out LTR inside the RTL list', (tester) async {
      await openList(
        tester,
        platformContainer(superAdmin, overrides: tenantOverrides()),
      );

      final code = find.text('MTM-4K7P-QX92');
      expect(code, findsOneWidget);
      expect(
        Directionality.of(tester.element(code)),
        TextDirection.ltr,
      );
    });
  });
}

/// Wraps the mock and forces a three-row page, so the "results were cut"
/// branch is reachable with the canonical eight fixtures.
class _SmallPageRepository implements SaasTenantRepository {
  _SmallPageRepository(this._inner);

  final SaasTenantRepository _inner;

  @override
  Future<Result<SaasTenantPage>> list(SaasTenantQuery query) =>
      _inner.list(query.copyWith(limit: 3));

  @override
  Future<Result<SaasTenant>> byId(String tenantId) => _inner.byId(tenantId);

  @override
  Future<Result<SaasTenant>> create(SaasTenantDraft draft) =>
      _inner.create(draft);

  @override
  Future<Result<List<SaasTenantEvent>>> statusHistory(String tenantId) =>
      _inner.statusHistory(tenantId);
}
