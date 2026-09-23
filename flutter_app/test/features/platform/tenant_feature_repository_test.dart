import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/domain/saas_tenant_models.dart';
import 'package:mtm/features/tenant_feature/data/mock_tenant_feature_repository.dart';
import 'package:mtm/features/tenant_feature/data/tenant_feature_fixtures.dart';
import 'package:mtm/features/tenant_feature/data/tenant_feature_providers.dart';
import 'package:mtm/features/tenant_feature/domain/tenant_feature_models.dart';
import 'package:mtm/features/tenant_feature/domain/tenant_feature_repository.dart';

void main() {
  final now = DateTime.utc(2026, 9, 9, 12);

  PlatformTenantStore store() => PlatformTenantStore(clock: () => now);

  MockTenantFeatureRepository repo({
    PlatformTenantStore? on,
    MockTenantFeatureMode mode = MockTenantFeatureMode.loaded,
    Duration latency = Duration.zero,
  }) =>
      MockTenantFeatureRepository(
        store: on ?? store(),
        mode: mode,
        latency: latency,
      );

  T unwrap<T>(Result<T> result) => result.when(
        success: (data, {stale = false}) => data,
        failure: (message, code) => throw TestFailure('$code: $message'),
        offline: (_) => throw TestFailure('offline'),
      );

  String? codeOf<T>(Result<T> result) => result.when(
        success: (_, {stale = false}) => null,
        failure: (_, code) => code,
        offline: (_) => 'offline',
      );

  group('domain and catalogue', () {
    test('catalogue keys and wire values are unique', () {
      expect(tenantFeatureCatalog.map((d) => d.key).toSet(),
          hasLength(tenantFeatureCatalog.length));
      expect(TenantFeatureKey.values.map((k) => k.wire).toSet(),
          hasLength(TenantFeatureKey.values.length));
    });

    test('unknown, missing and unsupported state all fail closed', () {
      final parsed = TenantFeatureSet.fromJson({
        'tenantId': 't1',
        'tenantName': 'فريق',
        'features': [
          {
            'key': 'inventory',
            'enabled': 'preview',
            'version': 3,
            'updatedAt': now.toIso8601String(),
          },
          {
            'key': 'future_module',
            'enabled': true,
            'version': 1,
            'updatedAt': now.toIso8601String(),
          },
        ],
      });

      expect(TenantFeatureKey.parse('future_module'), isNull);
      expect(parsed.isEnabled(TenantFeatureKey.inventory), isFalse,
          reason: 'unsupported state is not interpreted as enabled');
      expect(parsed.isEnabled(TenantFeatureKey.workshops), isFalse,
          reason: 'known-but-missing state is disabled');
      expect(parsed.unknownWireKeys, {'future_module'});
      expect(parsed.toJson().toString(), isNot(contains('future_module')));
    });

    test('route families use one typed mapping', () {
      expect(tenantFeaturesForLocation('/detachment/d1/storage'),
          {TenantFeatureKey.inventory});
      expect(tenantFeaturesForLocation('/detachment/d1/report/preview'),
          {TenantFeatureKey.statisticsReports});
      expect(tenantFeaturesForLocation('/workshop/w1/stats'), {
        TenantFeatureKey.workshops,
        TenantFeatureKey.statisticsReports,
      });
      expect(tenantFeaturesForLocation('/home'), isEmpty);
    });
  });

  group('canonical store and defaults', () {
    test('the eight tenants cover deterministic feature scenarios', () {
      final shared = store();
      expect(canonicalTenantFeatureConfiguration, hasLength(8));
      expect(
        TenantFeatureKey.values
            .every(shared.featuresOf('saas_hilal')!.isEnabled),
        isTrue,
      );
      expect(
          shared.featuresOf('saas_najd')!.isEnabled(TenantFeatureKey.inventory),
          isFalse);
      expect(
          shared
              .featuresOf('saas_sahel')!
              .isEnabled(TenantFeatureKey.workshops),
          isFalse);
      expect(
        shared
            .featuresOf('saas_wadi')!
            .states
            .values
            .where((state) => !state.enabled)
            .length,
        greaterThanOrEqualTo(2),
      );
    });

    test('new tenant gets explicit defaults independent of a plan', () {
      final shared = store();
      final created = shared.create(const SaasTenantDraft(
        displayName: 'فريق جديد',
        mainAdminName: 'مشرف جديد',
        mainAdminEmail: 'new@example.test',
        teamCode: 'MTM-ABCD-2345',
      ));
      final features = shared.featuresOf(created.id)!;
      for (final key in TenantFeatureKey.values) {
        expect(features.isEnabled(key),
            defaultEnabledTenantFeatures.contains(key));
      }
      expect(created.subscription.plan.hasPlan, isFalse,
          reason: 'feature defaults are not inferred from plan assignment');
    });
  });

  group('repository', () {
    test('get, disable and enable persist in the canonical store', () async {
      final shared = store();
      final r = repo(on: shared);
      final before = unwrap(await r.getFeatures('saas_hilal'));
      final current = before.stateOf(TenantFeatureKey.inventory)!;
      final disabled = unwrap(await r.setFeatureEnabled(
        SetTenantFeatureCommand(
          tenantId: before.tenantId,
          key: current.key,
          enabled: false,
          expectedVersion: current.version,
        ),
      ));
      expect(disabled.enabled, isFalse);
      expect(
          shared.featuresOf(before.tenantId)!.isEnabled(current.key), isFalse);

      final enabled = unwrap(await r.setFeatureEnabled(
        SetTenantFeatureCommand(
          tenantId: before.tenantId,
          key: current.key,
          enabled: true,
          expectedVersion: disabled.version,
        ),
      ));
      expect(enabled.enabled, isTrue);
      expect(
          shared.featuresOf(before.tenantId)!.isEnabled(current.key), isTrue);
    });

    test('stale version refuses overwrite and offline refuses writes',
        () async {
      final shared = store();
      final state =
          shared.featuresOf('saas_hilal')!.stateOf(TenantFeatureKey.workshops)!;
      final stale = await repo(on: shared).setFeatureEnabled(
        SetTenantFeatureCommand(
          tenantId: 'saas_hilal',
          key: state.key,
          enabled: false,
          expectedVersion: 999,
        ),
      );
      expect(codeOf(stale), TenantFeatureProblemCode.staleFeatureState.wire);
      expect(shared.featuresOf('saas_hilal')!.isEnabled(state.key), isTrue);

      final offline = await repo(
        on: shared,
        mode: MockTenantFeatureMode.offlineWithCache,
      ).setFeatureEnabled(SetTenantFeatureCommand(
        tenantId: 'saas_hilal',
        key: state.key,
        enabled: false,
        expectedVersion: state.version,
      ));
      expect(offline.isOffline, isTrue);
      expect(shared.featuresOf('saas_hilal')!.isEnabled(state.key), isTrue);
    });

    test('offline cached read is explicit', () async {
      final result = await repo(mode: MockTenantFeatureMode.offlineWithCache)
          .getFeatures('saas_hilal');
      expect(result, isA<Offline<TenantFeatureSet>>());
      expect((result as Offline<TenantFeatureSet>).cached, isNotNull);
    });
  });

  test('controller drops a duplicate mutation', () async {
    final container = ProviderContainer(overrides: [
      clockProvider.overrideWithValue(() => now),
      tenantFeatureRepositoryProvider.overrideWith((ref) {
        return MockTenantFeatureRepository(
          store: ref.watch(platformTenantStoreProvider),
          latency: const Duration(milliseconds: 40),
        );
      }),
    ]);
    addTearDown(container.dispose);
    final feature = container
        .read(platformTenantStoreProvider)
        .featuresOf('saas_hilal')!
        .stateOf(TenantFeatureKey.inventory)!;
    final command = SetTenantFeatureCommand(
      tenantId: 'saas_hilal',
      key: feature.key,
      enabled: false,
      expectedVersion: feature.version,
    );
    final controller =
        container.read(tenantFeatureActionControllerProvider.notifier);
    final first = controller.setEnabled(command);
    final second = await controller.setEnabled(command);
    expect(second, isA<TenantFeatureActionIgnored>());
    expect(await first, isA<TenantFeatureActionSucceeded>());
    expect(
        container
            .read(platformTenantStoreProvider)
            .featuresOf('saas_hilal')!
            .stateOf(feature.key)!
            .version,
        feature.version + 1);
  });
}
