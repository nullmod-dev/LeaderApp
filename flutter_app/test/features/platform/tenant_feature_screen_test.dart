import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_features_page.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_routes.dart';
import 'package:mtm/features/tenant_feature/data/mock_tenant_feature_repository.dart';
import 'package:mtm/features/tenant_feature/data/tenant_feature_providers.dart';
import 'package:mtm/features/tenant_feature/domain/tenant_feature_models.dart';
import 'package:mtm/features/tenant_feature/domain/tenant_feature_repository.dart';

import 'platform_harness.dart';

void main() {
  final now = DateTime.utc(2026, 9, 9, 12);

  Future<void> open(
    WidgetTester tester, {
    String tenantId = 'saas_hilal',
    MockTenantFeatureMode mode = MockTenantFeatureMode.loaded,
    double width = 390,
    double textScale = 1,
    String? mutationFailureCode,
    bool pending = false,
  }) async {
    final container = platformContainer(superAdmin, overrides: [
      clockProvider.overrideWithValue(() => now),
      tenantFeatureRepositoryProvider.overrideWith((ref) {
        if (pending) return const _PendingFeatureRepository();
        if (mutationFailureCode != null) {
          return _MutationFailureRepository(
            ref.watch(platformTenantStoreProvider),
            mutationFailureCode,
          );
        }
        return MockTenantFeatureRepository(
          store: ref.watch(platformTenantStoreProvider),
          mode: mode,
          latency: Duration.zero,
        );
      }),
    ]);
    final router = await bootPlatform(
      tester,
      container,
      width: width,
      height: 1800,
      textScale: textScale,
    );
    router.go(SaasTenantRoutes.features(tenantId));
    await settlePlatform(tester);
  }

  testWidgets('loaded screen renders the canonical catalogue and tenant',
      (tester) async {
    await open(tester);

    expect(find.byType(SaasTenantFeaturesPage), findsOneWidget);
    expect(find.byKey(const Key('tenant-features-loaded')), findsOneWidget);
    expect(find.text('فرق الهلال الطبية'), findsOneWidget);
    for (final feature in tenantFeatureCatalog) {
      expect(find.byKey(Key('tenant-feature-row-${feature.key.wire}')),
          findsOneWidget);
      expect(find.text(feature.arabicLabel), findsWidgets);
    }
    expect(find.byKey(const Key('tenant-features-retention-note')),
        findsOneWidget);
  });

  testWidgets('loading is a deliberate platform state', (tester) async {
    await open(tester, pending: true);
    expect(find.byKey(const Key('tenant-features-loading')), findsOneWidget);
  });

  testWidgets('disable confirmation names impact and retained data',
      (tester) async {
    await open(tester);

    await tester.tap(
      find.byKey(const Key('tenant-feature-switch-inventory')),
    );
    await tester.pumpAndSettle();

    expect(find.text('تعطيل المخزون'), findsOneWidget);
    expect(find.textContaining('فرق الهلال الطبية'), findsWidgets);
    expect(find.textContaining('لن تُحذف البيانات الحالية'), findsOneWidget);
    expect(find.textContaining('تعيد إعادة التفعيل الوصول'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'تعطيل الميزة'));
    await settlePlatform(tester);

    final toggle = tester.widget<Switch>(
      find.byKey(const Key('tenant-feature-switch-inventory')),
    );
    expect(toggle.value, isFalse);
    expect(find.textContaining('الاحتفاظ بالبيانات'), findsOneWidget);
  });

  testWidgets('enable is a direct guarded action', (tester) async {
    await open(tester, tenantId: 'saas_najd');

    final before = tester.widget<Switch>(
      find.byKey(const Key('tenant-feature-switch-inventory')),
    );
    expect(before.value, isFalse);
    await tester.tap(find.byKey(const Key('tenant-feature-switch-inventory')));
    await settlePlatform(tester);

    expect(find.byType(AlertDialog), findsNothing);
    final after = tester.widget<Switch>(
      find.byKey(const Key('tenant-feature-switch-inventory')),
    );
    expect(after.value, isTrue);
  });

  testWidgets('offline cached state is honest and read only', (tester) async {
    await open(tester, mode: MockTenantFeatureMode.offlineWithCache);

    expect(find.byKey(const Key('tenant-features-offline-cached')),
        findsOneWidget);
    expect(find.textContaining('لا يُحفظ للإرسال لاحقًا'), findsOneWidget);
    final toggle = tester.widget<Switch>(
      find.byKey(const Key('tenant-feature-switch-inventory')),
    );
    expect(toggle.onChanged, isNull);
  });

  testWidgets('offline without cache has no guessed state', (tester) async {
    await open(tester, mode: MockTenantFeatureMode.offlineWithoutCache);
    expect(
        find.byKey(const Key('tenant-features-offline-empty')), findsOneWidget);
  });

  testWidgets('failure is safe and retryable', (tester) async {
    await open(tester, mode: MockTenantFeatureMode.failure);
    expect(find.byKey(const Key('tenant-features-failure')), findsOneWidget);
  });

  testWidgets('unavailable feature projection fails closed distinctly',
      (tester) async {
    await open(tester, mode: MockTenantFeatureMode.unavailable);
    expect(
        find.byKey(const Key('tenant-features-unavailable')), findsOneWidget);
  });

  testWidgets('stale mutation refreshes and leaves the visible state unchanged',
      (tester) async {
    await open(tester, mutationFailureCode: 'stale_feature_state');
    await tester.tap(find.byKey(const Key('tenant-feature-switch-inventory')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'تعطيل الميزة'));
    await settlePlatform(tester);

    expect(find.textContaining('تغيّرت الحالة لدى مشرف آخر'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(
              find.byKey(const Key('tenant-feature-switch-inventory')))
          .value,
      isTrue,
    );
  });

  testWidgets('safe mutation failure never claims or paints success',
      (tester) async {
    await open(tester, mutationFailureCode: 'server');
    await tester.tap(find.byKey(const Key('tenant-feature-switch-inventory')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'تعطيل الميزة'));
    await settlePlatform(tester);

    expect(find.textContaining('بقيت الحالة الحالية كما هي'), findsOneWidget);
    expect(
      tester
          .widget<Switch>(
              find.byKey(const Key('tenant-feature-switch-inventory')))
          .value,
      isTrue,
    );
  });

  testWidgets('tenant not found is distinct from failure', (tester) async {
    await open(tester, tenantId: 'missing');
    expect(find.byKey(const Key('tenant-features-not-found')), findsOneWidget);
  });

  testWidgets('320dp at 1.6 text scale has no overflow', (tester) async {
    await open(tester, width: 320, textScale: 1.6);
    expect(find.byKey(const Key('tenant-features-loaded')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _MutationFailureRepository implements TenantFeatureRepository {
  _MutationFailureRepository(this.store, this.code);

  final PlatformTenantStore store;
  final String code;

  @override
  Future<Result<TenantFeatureSet>> getFeatures(String tenantId) async {
    final features = store.featuresOf(tenantId);
    return features == null
        ? const Failure('غير موجود', code: 'tenant_not_found')
        : Success(features);
  }

  @override
  Future<Result<TenantFeatureState>> setFeatureEnabled(
    SetTenantFeatureCommand command,
  ) async =>
      Failure('تعذّر الحفظ', code: code);
}

class _PendingFeatureRepository implements TenantFeatureRepository {
  const _PendingFeatureRepository();

  @override
  Future<Result<TenantFeatureSet>> getFeatures(String tenantId) =>
      Completer<Result<TenantFeatureSet>>().future;

  @override
  Future<Result<TenantFeatureState>> setFeatureEnabled(
    SetTenantFeatureCommand command,
  ) =>
      Completer<Result<TenantFeatureState>>().future;
}
