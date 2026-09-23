import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_tenant_subscription_repository.dart';
import 'package:mtm/features/platform/data/saas_subscription_providers.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/domain/saas_subscription_models.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_limits_page.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_routes.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_subscription_page.dart';

import 'platform_harness.dart';

void main() {
  final now = DateTime.utc(2026, 9, 8, 16);

  List<Override> overrides({
    MockTenantSubscriptionMode mode = MockTenantSubscriptionMode.loaded,
    Duration latency = Duration.zero,
  }) =>
      [
        clockProvider.overrideWithValue(() => now),
        tenantSubscriptionRepositoryProvider.overrideWith((ref) {
          return MockTenantSubscriptionRepository(
            store: ref.watch(platformTenantStoreProvider),
            clock: () => now,
            mode: mode,
            latency: latency,
          );
        }),
      ];

  Future<(ProviderContainer, GoRouter)> open(
    WidgetTester tester,
    String route, {
    MockTenantSubscriptionMode mode = MockTenantSubscriptionMode.loaded,
    double width = 390,
    double height = 1600,
    double textScale = 1,
    bool reduceMotion = false,
  }) async {
    final container = platformContainer(
      superAdmin,
      overrides: overrides(mode: mode),
    );
    final router = await bootPlatform(
      tester,
      container,
      width: width,
      height: height,
      textScale: textScale,
      reduceMotion: reduceMotion,
    );
    router.go(route);
    await settlePlatform(tester);
    return (container, router);
  }

  group('subscription screen', () {
    testWidgets('trial shows only valid trial actions and a no-plan state',
        (tester) async {
      await open(tester, SaasTenantRoutes.subscription('saas_nabd'));

      expect(find.byType(SaasTenantSubscriptionPage), findsOneWidget);
      expect(find.byKey(const Key('subscription-loaded')), findsOneWidget);
      expect(find.text('فترة تجريبية'), findsWidgets);
      expect(find.text('لا توجد خطة معيّنة'), findsOneWidget);
      expect(find.byKey(const Key('activate-subscription')), findsOneWidget);
      expect(find.byKey(const Key('extend-trial')), findsOneWidget);
      expect(find.byKey(const Key('end-trial')), findsOneWidget);
      expect(find.byKey(const Key('move-to-grace')), findsNothing);
    });

    testWidgets('active and grace states expose only legal actions',
        (tester) async {
      final opened = await open(
        tester,
        SaasTenantRoutes.subscription('saas_hilal'),
      );
      final router = opened.$2;
      expect(find.text('اشتراك فعّال'), findsWidgets);
      expect(find.byKey(const Key('move-to-grace')), findsOneWidget);
      expect(find.byKey(const Key('activate-subscription')), findsNothing);
      expect(find.byKey(const Key('extend-trial')), findsNothing);

      router.go(SaasTenantRoutes.subscription('saas_afiah'));
      await settlePlatform(tester);
      expect(find.text('فترة سماح'), findsWidgets);
      expect(find.byKey(const Key('activate-subscription')), findsOneWidget);
      expect(find.byKey(const Key('move-to-grace')), findsNothing);
    });

    testWidgets('plan selection is stacked and compares relevant limits',
        (tester) async {
      await open(tester, SaasTenantRoutes.subscription('saas_nabd'));
      await tester.tap(find.byKey(const Key('change-plan')));
      await tester.pumpAndSettle();

      for (final id in ['mtm_core', 'mtm_standard', 'mtm_advanced']) {
        expect(find.byKey(Key('plan-option-$id')), findsOneWidget);
      }
      expect(find.text('المفارز: ٥'), findsOneWidget);
      expect(find.textContaining('تم الدفع'), findsNothing);
      expect(find.textContaining('تم الخصم'), findsNothing);
    });

    testWidgets('activation confirmation explicitly denies payment claims',
        (tester) async {
      await open(tester, SaasTenantRoutes.subscription('saas_masar'));
      await tester.tap(find.byKey(const Key('activate-subscription')));
      await tester.pumpAndSettle();

      expect(find.text('تفعيل الاشتراك'), findsWidgets);
      expect(find.textContaining('لن تُنفّذ دفعة'), findsOneWidget);
      expect(find.textContaining('حالة وصوله'), findsOneWidget);
    });

    testWidgets('trial extension offers positive deterministic durations',
        (tester) async {
      await open(tester, SaasTenantRoutes.subscription('saas_masar'));
      await tester.tap(find.byKey(const Key('extend-trial')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('extend-trial-7')), findsOneWidget);
      expect(find.byKey(const Key('extend-trial-14')), findsOneWidget);
      expect(find.byKey(const Key('extend-trial-30')), findsOneWidget);
      expect(find.textContaining('إضافة 0'), findsNothing);
    });

    testWidgets('offline is an honest designed state', (tester) async {
      await open(
        tester,
        SaasTenantRoutes.subscription('saas_hilal'),
        mode: MockTenantSubscriptionMode.offline,
      );
      expect(find.byKey(const Key('subscription-offline')), findsOneWidget);
      expect(find.textContaining('لا تُحفظ للإرسال لاحقًا'), findsOneWidget);
    });

    testWidgets('failure is safe and retryable', (tester) async {
      await open(
        tester,
        SaasTenantRoutes.subscription('saas_hilal'),
        mode: MockTenantSubscriptionMode.failure,
      );
      expect(find.byKey(const Key('subscription-failure')), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsOneWidget);
    });
  });

  group('limits screen', () {
    testWidgets('shows current usage beside every effective limit',
        (tester) async {
      await open(tester, SaasTenantRoutes.limits('saas_afiah'));

      expect(find.byType(SaasTenantLimitsPage), findsOneWidget);
      for (final key in PlanLimitKey.values) {
        expect(find.byKey(Key('limit-${key.wire}')), findsOneWidget,
            reason: key.wire);
      }
      expect(find.text('١٥ / ٢٠'), findsOneWidget);
      expect(find.textContaining('حد مخصص'), findsWidgets);
      expect(find.byKey(const Key('limits-no-deletion-note')), findsOneWidget);
    });

    testWidgets('below-usage confirmation is warning copy, never deletion',
        (tester) async {
      final opened = await open(
        tester,
        SaasTenantRoutes.limits('saas_afiah'),
      );
      final container = opened.$1;
      final card = find.byKey(const Key('limit-detachments'));
      await tester.tap(find.descendant(
          of: card, matching: find.byIcon(Icons.edit_outlined)));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('limit-value-field')), '5');
      await tester.tap(find.byKey(const Key('save-limit')));
      await tester.pumpAndSettle();

      expect(find.text('الحد الجديد أقل من الاستخدام'), findsOneWidget);
      expect(find.textContaining('لن تُحذف البيانات الحالية'), findsOneWidget);
      expect(find.textContaining('سيتوقف إنشاء عناصر إضافية'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'حفظ الحد'));
      await settlePlatform(tester);
      final tenant =
          container.read(platformTenantStoreProvider).byId('saas_afiah')!;
      expect(tenant.subscription.limitOverrides[PlanLimitKey.detachments], 5);
      expect(tenant.counts.detachments, 15,
          reason: 'existing records remain untouched');
    });

    testWidgets('an override can reset to the selected plan default',
        (tester) async {
      final opened = await open(
        tester,
        SaasTenantRoutes.limits('saas_afiah'),
      );
      final container = opened.$1;
      final card = find.byKey(const Key('limit-detachments'));
      await tester.tap(find.descendant(
          of: card, matching: find.byIcon(Icons.edit_outlined)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reset-limit')));
      await settlePlatform(tester);

      final tenant =
          container.read(platformTenantStoreProvider).byId('saas_afiah')!;
      expect(
          tenant.subscription.hasOverride(PlanLimitKey.detachments), isFalse);
    });

    testWidgets('no-plan is distinct from a failed usage read', (tester) async {
      await open(tester, SaasTenantRoutes.limits('saas_nabd'));
      expect(find.byKey(const Key('limits-no-plan')), findsOneWidget);
    });

    testWidgets('usage failure refuses to show unconfirmed numbers',
        (tester) async {
      await open(
        tester,
        SaasTenantRoutes.limits('saas_afiah'),
        mode: MockTenantSubscriptionMode.usageUnavailable,
      );
      expect(find.byKey(const Key('limits-failure')), findsOneWidget);
    });

    testWidgets('320dp, 1.6 text scale and reduced motion do not overflow',
        (tester) async {
      await open(
        tester,
        SaasTenantRoutes.limits('saas_afiah'),
        width: 320,
        height: 2200,
        textScale: 1.6,
        reduceMotion: true,
      );
      expect(find.byKey(const Key('limits-loaded')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('Point 7 initializes no tenant operational repository',
      (tester) async {
    final watch = TenantRepositoryWatch();
    final container = platformContainer(
      superAdmin,
      watch: watch,
      overrides: overrides(),
    );
    final router = await bootPlatform(tester, container, height: 1600);
    for (final route in [
      SaasTenantRoutes.subscription('saas_hilal'),
      SaasTenantRoutes.limits('saas_hilal'),
    ]) {
      router.go(route);
      await settlePlatform(tester);
    }
    expect(watch.built, isEmpty);
  });
}
