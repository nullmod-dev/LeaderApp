import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/admin_experience.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/announcement/data/announcement_providers.dart';
import 'package:mtm/features/announcement/presentation/announcements_page.dart';
import 'package:mtm/features/detachment/presentation/tabs/detachment_stats_tab.dart';
import 'package:mtm/features/detachment/presentation/tabs/detachment_storage_tab.dart';
import 'package:mtm/features/inventory/data/inventory_providers.dart';
import 'package:mtm/features/notification/data/notification_providers.dart';
import 'package:mtm/features/notification/domain/notification_models.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/search/data/search_providers.dart';
import 'package:mtm/features/shell/main_shell.dart';
import 'package:mtm/features/tenant_feature/data/tenant_feature_providers.dart';
import 'package:mtm/features/tenant_feature/domain/tenant_feature_models.dart';
import 'package:mtm/features/tenant_feature/presentation/feature_disabled_page.dart';
import 'package:mtm/features/workshop/presentation/workshop_edit_page.dart';
import 'package:mtm/l10n/strings.dart';

import '../platform/platform_harness.dart';

void main() {
  const detachmentId = 'd_dam_central';

  Future<(ProviderContainer, GoRouter)> bootTenant(
    WidgetTester tester, {
    AuthUser? user,
    Set<TenantFeatureKey> disabled = const {},
    double width = 400,
    double textScale = 1,
  }) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(user ?? mainAdmin);
    final store = container.read(platformTenantStoreProvider);
    final tenantId = (user ?? mainAdmin).saasTenantId!;
    for (final key in disabled) {
      store.updateFeature(tenantId, key, false);
    }
    container.read(tenantFeatureRevisionProvider.notifier).changed();
    final router = await bootPlatform(
      tester,
      container,
      width: width,
      height: 1200,
      textScale: textScale,
    );
    return (container, router);
  }

  group('deep links and runtime changes', () {
    testWidgets('inventory route is refused, then restored after re-enable',
        (tester) async {
      final (container, router) = await bootTenant(tester);
      const route = '/detachment/$detachmentId/storage';
      router.go(route);
      await settlePlatform(tester);
      expect(find.byType(DetachmentStorageTab), findsOneWidget);

      final store = container.read(platformTenantStoreProvider);
      store.updateFeature(
        mainAdmin.saasTenantId!,
        TenantFeatureKey.inventory,
        false,
      );
      container.read(tenantFeatureRevisionProvider.notifier).changed();
      await settlePlatform(tester);
      expect(find.byType(FeatureDisabledPage), findsOneWidget);
      expect(find.textContaining('لم تُحذف البيانات'), findsOneWidget);

      store.updateFeature(
        mainAdmin.saasTenantId!,
        TenantFeatureKey.inventory,
        true,
      );
      container.read(tenantFeatureRevisionProvider.notifier).changed();
      router.go(route);
      await settlePlatform(tester);
      expect(find.byType(DetachmentStorageTab), findsOneWidget);
    });

    testWidgets('workshops and statistics direct routes fail closed',
        (tester) async {
      final (container, router) = await bootTenant(
        tester,
        disabled: const {
          TenantFeatureKey.workshops,
          TenantFeatureKey.statisticsReports,
        },
      );

      router.go('/workshop/new');
      await settlePlatform(tester);
      expect(find.byType(WorkshopEditPage), findsNothing);
      expect(find.byType(FeatureDisabledPage), findsOneWidget);

      router.go('/detachment/$detachmentId/stats');
      await settlePlatform(tester);
      expect(find.byType(DetachmentStatsTab), findsNothing);
      expect(find.byType(FeatureDisabledPage), findsOneWidget);

      final store = container.read(platformTenantStoreProvider);
      store.updateFeature(
        mainAdmin.saasTenantId!,
        TenantFeatureKey.workshops,
        true,
      );
      store.updateFeature(
        mainAdmin.saasTenantId!,
        TenantFeatureKey.statisticsReports,
        true,
      );
      container.read(tenantFeatureRevisionProvider.notifier).changed();

      router.go('/workshop/new');
      await settlePlatform(tester);
      expect(find.byType(WorkshopEditPage), findsOneWidget);
      router.go('/detachment/$detachmentId/stats');
      await settlePlatform(tester);
      expect(find.byType(DetachmentStatsTab), findsOneWidget);
    });

    testWidgets('announcement deep link is rejected and restored explicitly',
        (tester) async {
      final (container, router) = await bootTenant(
        tester,
        disabled: const {TenantFeatureKey.announcements},
      );
      router.go('/announcements');
      await settlePlatform(tester);
      expect(find.byType(AnnouncementsPage), findsNothing);
      expect(find.byType(FeatureDisabledPage), findsOneWidget);

      container.read(platformTenantStoreProvider).updateFeature(
            mainAdmin.saasTenantId!,
            TenantFeatureKey.announcements,
            true,
          );
      container.read(tenantFeatureRevisionProvider.notifier).changed();
      router.go('/announcements');
      await settlePlatform(tester);
      expect(find.byType(AnnouncementsPage), findsOneWidget);
    });

    testWidgets('disabled workshop disappears from tenant navigation',
        (tester) async {
      final (_, router) = await bootTenant(
        tester,
        disabled: const {TenantFeatureKey.workshops},
      );
      router.go('/home');
      await settlePlatform(tester);
      expect(find.byType(MainShell), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MainShell),
          matching: find.text(S.navWorkshop),
        ),
        findsNothing,
      );
    });

    testWidgets('remaining destinations stay stable at 320dp and 1.6 text',
        (tester) async {
      final (_, router) = await bootTenant(
        tester,
        disabled: const {TenantFeatureKey.workshops},
        width: 320,
        textScale: 1.6,
      );
      router.go('/home');
      await settlePlatform(tester);
      expect(find.byType(MainShell), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Home omits entry points for globally disabled modules',
        (tester) async {
      final (_, router) = await bootTenant(
        tester,
        disabled: const {
          TenantFeatureKey.inventory,
          TenantFeatureKey.statisticsReports,
          TenantFeatureKey.announcements,
        },
      );
      router.go('/home');
      await settlePlatform(tester);

      expect(find.byKey(const Key('dashboard-action-storage')), findsNothing);
      expect(find.byKey(const Key('dashboard-action-stats')), findsNothing);
      expect(
        find.byKey(const Key('dashboard-action-announcements')),
        findsNothing,
      );
    });
  });

  group('feature and capability precedence', () {
    const limited = AuthUser(
      id: 'u_limited',
      name: 'مشرف محدود',
      email: 'limited@example.test',
      role: AuthRole.admin,
      saasTenantId: kDemoSaasTenantId,
      capabilities: Capabilities(global: {Cap.detachmentView}),
      orgName: 'فريق',
    );

    testWidgets('enabled feature still requires the action capability',
        (tester) async {
      final (_, router) = await bootTenant(tester, user: limited);
      router.go('/detachment/$detachmentId/storage/new');
      await settlePlatform(tester);
      expect(find.byType(FeatureDisabledPage), findsNothing);
      expect(locationOf(router), '/home');
    });

    testWidgets('disabled feature wins before an allowed/denied capability',
        (tester) async {
      final (_, router) = await bootTenant(
        tester,
        user: limited,
        disabled: const {TenantFeatureKey.inventory},
      );
      router.go('/detachment/$detachmentId/storage/new');
      await settlePlatform(tester);
      expect(find.byType(FeatureDisabledPage), findsOneWidget);
    });

    test('Main and Simple Admin share tenant flags, not capabilities', () {
      expect(mainAdmin.saasTenantId, simpleAdmin.saasTenantId);
      expect(mainAdmin.capabilities, isNot(simpleAdmin.capabilities));
      final store =
          platformContainer(mainAdmin).read(platformTenantStoreProvider);
      expect(
        store.featuresOf(mainAdmin.saasTenantId!),
        same(store.featuresOf(simpleAdmin.saasTenantId!)),
      );
    });
  });

  test('disabling and re-enabling inventory preserves records and usage',
      () async {
    final container = platformContainer(mainAdmin);
    await container.read(currentUserProvider.future);
    final inventory = container.read(inventoryRepositoryProvider);
    final beforeResult = await inventory.listForDetachment(detachmentId);
    final before = beforeResult.when(
      success: (data, {stale = false}) => data,
      failure: (message, code) => throw TestFailure('$code: $message'),
      offline: (_) => throw TestFailure('offline'),
    );
    final store = container.read(platformTenantStoreProvider);
    final tenantBefore = store.byId(mainAdmin.saasTenantId!)!;
    final counts = tenantBefore.counts.toJson();
    final subscriptionVersion = tenantBefore.subscription.version;

    store.updateFeature(
      mainAdmin.saasTenantId!,
      TenantFeatureKey.inventory,
      false,
    );
    expect(store.byId(mainAdmin.saasTenantId!)!.counts.toJson(), counts);
    expect(store.byId(mainAdmin.saasTenantId!)!.subscription.version,
        subscriptionVersion);

    store.updateFeature(
      mainAdmin.saasTenantId!,
      TenantFeatureKey.inventory,
      true,
    );
    final afterResult = await inventory.listForDetachment(detachmentId);
    final after = afterResult.when(
      success: (data, {stale = false}) => data,
      failure: (message, code) => throw TestFailure('$code: $message'),
      offline: (_) => throw TestFailure('offline'),
    );
    expect(after.map((item) => item.id), before.map((item) => item.id));
  });

  test('disabled inventory is excluded before Search and Notification loads',
      () async {
    const user = AuthUser(
      id: 'u_najd',
      name: 'مشرف نجد',
      email: 'admin@najd.test',
      role: AuthRole.mainAdmin,
      saasTenantId: 'saas_najd',
      capabilities: Capabilities(global: Cap.all),
      orgName: 'فريق نجد',
    );
    final container = ProviderContainer(overrides: [
      currentUserResultProvider.overrideWith(
        (ref) async => const Success<AuthUser?>(user),
      ),
      clockProvider.overrideWithValue(() => DateTime.utc(2026, 9, 9, 12)),
      inventoryRepositoryProvider.overrideWith(
        (ref) => throw StateError('inventory source must not initialize'),
      ),
    ]);
    addTearDown(container.dispose);
    await container.read(currentUserProvider.future);

    final index = await container.read(searchIndexProvider.future);
    expect(index.allowed, isNot(contains(AdminDataCategory.inventory)));
    expect(
        index.results.where((r) => r.category == AdminDataCategory.inventory),
        isEmpty);

    final source =
        await container.read(notificationSourceProvider(detachmentId).future);
    final rows = source.valueOrNull ?? const <AppNotification>[];
    expect(
      rows.where((row) => row.kind.name.startsWith('stock')),
      isEmpty,
    );
  });

  test('disabled announcements never initialize or leak their feed source',
      () async {
    const user = AuthUser(
      id: 'u_wadi',
      name: 'مشرف الوادي',
      email: 'admin@wadi.test',
      role: AuthRole.mainAdmin,
      saasTenantId: 'saas_wadi',
      capabilities: Capabilities(global: Cap.all),
      orgName: 'فريق الوادي',
    );
    final container = ProviderContainer(overrides: [
      currentUserResultProvider.overrideWith(
        (ref) async => const Success<AuthUser?>(user),
      ),
      notificationSourceProvider.overrideWith(
        (ref, id) async => const Success<List<AppNotification>>([]),
      ),
      announcementRepositoryProvider.overrideWith(
        (ref) => throw StateError('announcement source must not initialize'),
      ),
    ]);
    addTearDown(container.dispose);
    await container.read(currentUserProvider.future);

    await container.read(notificationSourceProvider('d1').future);
    final result = container.read(notificationFeedProvider('d1')).value!;
    final rows = result.valueOrNull ?? const <AppNotification>[];
    expect(rows.where((row) => row.kind == NotificationKind.announcement),
        isEmpty);
  });
}

extension<T> on Result<T> {
  T? get valueOrNull => when(
        success: (data, {stale = false}) => data,
        failure: (_, __) => null,
        offline: (cached) => cached,
      );
}
