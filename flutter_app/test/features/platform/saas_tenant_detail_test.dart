import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_saas_tenant_repository.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/domain/saas_tenant_models.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_detail_page.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_routes.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

/// Point 6 — `/platform/tenants/:tenantId`, read-only by design.
void main() {
  final now = DateTime.utc(2026, 9, 8, 16);

  List<Override> overrides({
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

  Future<void> open(
    WidgetTester tester, {
    String tenantId = 'saas_hilal',
    MockSaasTenantMode mode = MockSaasTenantMode.loaded,
  }) async {
    final container =
        platformContainer(superAdmin, overrides: overrides(mode: mode));
    final router = await bootPlatform(tester, container, height: 3000);
    router.go(SaasTenantRoutes.detail(tenantId));
    await settlePlatform(tester);
  }

  group('a found subscriber', () {
    testWidgets('shows every Point 6 section', (tester) async {
      await open(tester);

      expect(find.byType(SaasTenantDetailPage), findsOneWidget);
      for (final key in const [
        'platform-tenant-identity',
        'platform-tenant-admin',
        'platform-tenant-subscription',
        'platform-tenant-usage',
        'platform-tenant-counts',
        'platform-tenant-history',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      }
    });

    testWidgets('shows the identity, the code and the Main Admin',
        (tester) async {
      await open(tester);

      expect(find.text('فرق الهلال الطبية'), findsOneWidget);
      expect(find.text('MTM-4K7P-QX92'), findsOneWidget);
      expect(find.text('سلمى الحارثي'), findsOneWidget);
      expect(find.text('salma@hilal-medical.org'), findsOneWidget);
      expect(find.text('اشتراك نشط'), findsWidgets);
    });

    testWidgets('never shows a credential', (tester) async {
      await open(tester, tenantId: 'saas_nabd');

      // The pending-setup note *describes* the later first-login password
      // change, which is the point of it; what must never appear is a
      // credential value or a control that hands one over.
      for (final forbidden in const [
        'كلمة مرور مؤقتة',
        'كلمة المرور المؤقتة',
        'نسخ كلمة المرور',
        'رمز التحقق',
        'password',
        'OTP',
      ]) {
        expect(find.textContaining(forbidden), findsNothing, reason: forbidden);
      }
      // Copy exists once, and it copies the Team Code.
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    });

    testWidgets('a pending Main Admin is stated, not hidden', (tester) async {
      await open(tester, tenantId: 'saas_nabd');

      expect(find.text(S.mainAdminStatusPending), findsOneWidget);
    });

    testWidgets('the lifecycle history is present and read-only',
        (tester) async {
      final container = platformContainer(
        superAdmin,
        overrides: overrides(),
      );
      final router = await bootPlatform(tester, container, height: 3600);
      router.go(SaasTenantRoutes.detail('saas_rukn'));
      await settlePlatform(tester);

      expect(find.byKey(const Key('platform-tenant-event-saas_rukn_suspended')),
          findsOneWidget);
      expect(find.byKey(const Key('platform-tenant-event-saas_rukn_created')),
          findsOneWidget);
    });

    testWidgets('links to Points 7 and 8 and exposes Point 9 lifecycle actions',
        (tester) async {
      await open(tester, tenantId: 'saas_afiah');

      expect(
          find.byKey(const Key('tenant-lifecycle-management')), findsOneWidget);
      expect(find.byKey(const Key('tenant-lifecycle-suspend')), findsOneWidget);
      expect(find.byKey(const Key('tenant-lifecycle-begin-delete')),
          findsOneWidget);
      expect(
          find.byKey(const Key('platform-tenant-copy-code')), findsOneWidget);
      expect(find.byKey(const Key('open-tenant-subscription')), findsOneWidget);
      expect(find.byKey(const Key('open-tenant-limits-from-detail')),
          findsOneWidget);
      expect(find.byKey(const Key('open-tenant-features-from-detail')),
          findsOneWidget);
    });
  });

  group('the states a detail can be in', () {
    testWidgets('an unknown id is a not-found state with a way back',
        (tester) async {
      await open(tester, tenantId: 'saas_nope');

      expect(
          find.byKey(const Key('platform-tenant-not-found')), findsOneWidget);
      expect(find.text('العودة إلى قائمة الفرق'), findsOneWidget);
    });

    testWidgets('offline with a cached record still renders it',
        (tester) async {
      await open(tester, mode: MockSaasTenantMode.offlineWithCache);

      expect(find.text('فرق الهلال الطبية'), findsOneWidget);
      expect(find.byKey(const Key('platform-tenant-identity')), findsOneWidget);
    });

    testWidgets('offline with nothing cached says so', (tester) async {
      await open(tester, mode: MockSaasTenantMode.offlineWithoutCache);

      expect(find.byKey(const Key('platform-tenant-offline-empty')),
          findsOneWidget);
    });

    testWidgets('a failure offers retry and leaks no exception text',
        (tester) async {
      await open(tester, mode: MockSaasTenantMode.failure);

      expect(find.byKey(const Key('platform-tenant-failure')), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('a finalized tenant renders only the restricted tombstone',
        (tester) async {
      final container = platformContainer(superAdmin, overrides: overrides());
      final store = container.read(platformTenantStoreProvider);
      _finalize(store, now, 'saas_hilal');
      final router = await bootPlatform(tester, container, height: 1200);
      router.go(SaasTenantRoutes.detail('saas_hilal'));
      await settlePlatform(tester);

      expect(
          find.byKey(const Key('platform-tenant-tombstone')), findsOneWidget);
      expect(find.text('فرق الهلال الطبية'), findsOneWidget);
      expect(find.text('saas_hilal'), findsOneWidget);
      expect(find.text('MTM-4K7P-QX92'), findsNothing);
      expect(find.text('salma@hilal-medical.org'), findsNothing);
      expect(
          find.byKey(const Key('platform-tenant-subscription')), findsNothing);
      expect(
          find.byKey(const Key('tenant-lifecycle-management')), findsNothing);
    });

    testWidgets('successful final request stays on a usable tombstone view',
        (tester) async {
      final container = platformContainer(superAdmin, overrides: overrides());
      final store = container.read(platformTenantStoreProvider);
      final tenant = _setPending(store, now, 'saas_hilal');
      final router = await bootPlatform(tester, container, height: 1800);
      router.go(SaasTenantRoutes.detail(tenant.id));
      await settlePlatform(tester);

      await tester.tap(
        find.byKey(const Key('tenant-lifecycle-finalize-delete')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('متابعة إلى التأكيد'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('final-delete-typed-confirmation')),
        tenant.displayName,
      );
      await tester.tap(
        find.byKey(const Key('final-delete-acknowledgement')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('final-delete-submit')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));

      expect(
          find.byKey(const Key('platform-tenant-tombstone')), findsOneWidget);
      expect(find.textContaining('اكتمل طلب الحذف النهائي'), findsOneWidget);
      expect(store.byId(tenant.id), isNull);
      expect(store.tombstoneById(tenant.id), isNotNull);

      await tester.tap(
        find.byKey(const Key('platform-tombstone-back-to-list')),
      );
      await settlePlatform(tester);
      expect(find.byKey(Key('platform-tenant-row-${tenant.id}')), findsNothing);
    });
  });

  group('responsive and RTL', () {
    testWidgets('320 dp at a 1.6 text scale renders without overflow',
        (tester) async {
      final container = platformContainer(superAdmin, overrides: overrides());
      final router = await bootPlatform(
        tester,
        container,
        width: 320,
        height: 3000,
        textScale: 1.6,
      );
      router.go(SaasTenantRoutes.detail('saas_hilal'));
      await settlePlatform(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(SaasTenantDetailPage), findsOneWidget);
    });

    testWidgets('the email and the code lay out LTR inside the RTL page',
        (tester) async {
      await open(tester);

      for (final value in const [
        'salma@hilal-medical.org',
        'MTM-4K7P-QX92',
      ]) {
        final finder = find.text(value);
        expect(finder, findsOneWidget, reason: value);
        expect(Directionality.of(tester.element(finder)), TextDirection.ltr,
            reason: value);
      }
    });
  });

  group('isolation', () {
    testWidgets('no tenant operational repository is built', (tester) async {
      final watch = TenantRepositoryWatch();
      final container = platformContainer(
        superAdmin,
        watch: watch,
        overrides: overrides(),
      );
      final router = await bootPlatform(tester, container, height: 2400);
      router.go(SaasTenantRoutes.detail('saas_hilal'));
      await settlePlatform(tester);

      expect(watch.built, isEmpty);
    });

    testWidgets('the feature screen builds no tenant operational repository',
        (tester) async {
      final watch = TenantRepositoryWatch();
      final container = platformContainer(
        superAdmin,
        watch: watch,
        overrides: overrides(),
      );
      final router = await bootPlatform(tester, container, height: 1600);
      router.go(SaasTenantRoutes.features('saas_hilal'));
      await settlePlatform(tester);

      expect(watch.built, isEmpty);
    });
  });
}

void _finalize(PlatformTenantStore store, DateTime now, String tenantId) {
  final tenant = _setPending(store, now, tenantId);
  final deleted = TenantLifecyclePolicy.transition(
    current: tenant.lifecycle,
    action: TenantLifecycleAction.finalizeDeletion,
    now: now,
  ) as TenantLifecycleTransitionAllowed;
  store.finalizeTenant(tenantId, deleted.next);
}

SaasTenant _setPending(
  PlatformTenantStore store,
  DateTime now,
  String tenantId,
) {
  final tenant = store.byId(tenantId)!;
  final pending = TenantLifecyclePolicy.transition(
    current: tenant.lifecycle,
    action: TenantLifecycleAction.beginDeletion,
    now: now.subtract(const Duration(days: 31)),
    reason: 'سبب لا يبقى في السجل المختصر',
    deletionGrace: const Duration(days: 30),
  ) as TenantLifecycleTransitionAllowed;
  return store.updateLifecycle(
    tenantId,
    pending.next,
    eventType: SaasTenantEventType.deletionRequested,
  );
}
