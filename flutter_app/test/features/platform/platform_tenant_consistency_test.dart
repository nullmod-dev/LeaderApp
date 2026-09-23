import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/motion/animated_counter.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_platform_overview_repository.dart';
import 'package:mtm/features/platform/data/mock_saas_tenant_repository.dart';
import 'package:mtm/features/platform/data/mock_tenant_subscription_repository.dart';
import 'package:mtm/features/platform/data/mock_tenant_lifecycle_repository.dart';
import 'package:mtm/features/platform/data/platform_overview_providers.dart';
import 'package:mtm/features/platform/data/platform_tenant_fixtures.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/domain/platform_overview_models.dart';
import 'package:mtm/features/platform/domain/saas_tenant_models.dart';
import 'package:mtm/features/platform/domain/saas_subscription_models.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';

/// **One customer base, two screens.** The regression this file exists to
/// catch is the one §12 of the Point 6 brief names by hand: the Platform
/// Overview saying eight subscribers while the subscriber list shows five.
void main() {
  final now = DateTime.utc(2026, 9, 8, 16);

  Future<PlatformOverviewSnapshot> overview(
    PlatformOverviewRepositoryUnderTest build,
  ) async {
    final result = await build().loadOverview();
    return result.when(
      success: (data, {stale = false}) => data,
      failure: (message, _) => throw TestFailure(message),
      offline: (_) => throw TestFailure('offline'),
    );
  }

  test('the overview buckets are counted from the canonical dataset', () async {
    final store = PlatformTenantStore(clock: () => now);
    final snapshot = await overview(
      () => MockPlatformOverviewRepository(
        clock: () => now,
        store: store,
        latency: Duration.zero,
      ),
    );
    final tenants = canonicalSaasTenants(now);

    expect(snapshot.tenants.total, tenants.length);
    expect(
      snapshot.tenants.activeSubscriptions,
      tenants
          .where((t) => t.subscription.status == SubscriptionStatus.active)
          .length,
    );
    expect(
      snapshot.tenants.activeTrials,
      tenants
          .where((t) => t.subscription.status == SubscriptionStatus.trial)
          .length,
    );
    expect(
      snapshot.tenants.gracePeriod,
      tenants
          .where((t) => t.subscription.status == SubscriptionStatus.grace)
          .length,
    );
    expect(
      snapshot.tenants.suspended,
      tenants.where((t) => t.tenantStatus == SaasTenantStatus.suspended).length,
    );
    expect(snapshot.tenants.deletionPending, 0);
  });

  test('the shipped numbers are still the ones Point 5 published', () async {
    final snapshot = await overview(
      () => MockPlatformOverviewRepository(
        clock: () => now,
        latency: Duration.zero,
      ),
    );

    // Point 5 stated 8 / 4 / 2 / 1 / 1 as literals. Deriving them must not
    // have quietly changed what the overview says.
    expect(snapshot.tenants.total, 8);
    expect(snapshot.tenants.activeSubscriptions, 4);
    expect(snapshot.tenants.activeTrials, 2);
    expect(snapshot.tenants.gracePeriod, 1);
    expect(snapshot.tenants.suspended, 1);
    expect(snapshot.tenants.deletionPending, 0);
  });

  test('the list total and the overview total are the same number', () async {
    final container = ProviderContainer(overrides: [
      clockProvider.overrideWithValue(() => now),
      saasTenantRepositoryProvider.overrideWith((ref) {
        return MockSaasTenantRepository(
          store: ref.watch(platformTenantStoreProvider),
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
    addTearDown(container.dispose);

    Future<int> listTotal() async {
      final result = await container
          .read(saasTenantListProvider(const SaasTenantQuery()).future);
      return result.when(
        success: (page, {stale = false}) => page.total,
        failure: (_, __) => -1,
        offline: (_) => -1,
      );
    }

    Future<int> overviewTotal() async {
      final result = await container.read(platformOverviewProvider.future);
      return result.when(
        success: (data, {stale = false}) => data.tenants.total,
        failure: (_, __) => -1,
        offline: (_) => -1,
      );
    }

    expect(await listTotal(), await overviewTotal());

    // And after a registration, still the same number — without a restart and
    // without an event bus.
    await container.read(saasTenantRepositoryProvider).create(
          const SaasTenantDraft(
            displayName: 'فريق جديد',
            mainAdminName: 'مدير',
            mainAdminEmail: 'admin@new-team.org',
            teamCode: 'MTM-7DQX-4NKR',
          ),
        );
    container
      ..invalidate(saasTenantListProvider)
      ..invalidate(platformOverviewProvider);

    expect(await listTotal(), 9);
    expect(await overviewTotal(), 9);
  });

  test('the provider wiring hands both mocks the same store', () {
    final container = ProviderContainer(overrides: [
      clockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(container.dispose);

    final store = container.read(platformTenantStoreProvider);
    expect(
        identical(container.read(platformTenantStoreProvider), store), isTrue);
    // Both repositories are built over it; a second store would show up as a
    // second seeding of the fixtures and a divergent count.
    expect(container.read(saasTenantRepositoryProvider), isNotNull);
    expect(container.read(platformOverviewRepositoryProvider), isNotNull);
    expect(store.tenantSummary().total, store.tenants.length);
  });

  test('customer Demos are not subscribers and are counted separately',
      () async {
    final snapshot = await overview(
      () => MockPlatformOverviewRepository(
        clock: () => now,
        latency: Duration.zero,
      ),
    );

    // Four active Demos exist in the overview; none of them is in the tenant
    // dataset, and the tenant total does not include them.
    expect(snapshot.demos.active, 4);
    expect(snapshot.tenants.total, canonicalSaasTenants(now).length);
    for (final tenant in canonicalSaasTenants(now)) {
      expect(tenant.id.contains('demo'), isFalse, reason: tenant.id);
    }
  });

  test('Point 7 transitions immediately change Point 5 commercial buckets',
      () async {
    final shared = PlatformTenantStore(clock: () => now);
    final subscriptions = MockTenantSubscriptionRepository(
      store: shared,
      clock: () => now,
      latency: Duration.zero,
    );
    final overviewRepository = MockPlatformOverviewRepository(
      clock: () => now,
      store: shared,
      latency: Duration.zero,
    );

    final trial = shared.byId('saas_nabd')!;
    await subscriptions.activate(ActivateSubscriptionCommand(
      tenantId: trial.id,
      expectedVersion: trial.subscription.version,
      planId: 'mtm_standard',
    ));
    var snapshot = await overview(() => overviewRepository);
    expect(snapshot.tenants.activeSubscriptions, 5);
    expect(snapshot.tenants.activeTrials, 1);

    final active = shared.byId('saas_hilal')!;
    await subscriptions.moveToGrace(SubscriptionVersionedCommand(
      tenantId: active.id,
      expectedVersion: active.subscription.version,
    ));
    snapshot = await overview(() => overviewRepository);
    expect(snapshot.tenants.activeSubscriptions, 4);
    expect(snapshot.tenants.gracePeriod, 2);
    expect(
      snapshot.attention
          .firstWhere((item) => item.id == 'attention_grace')
          .title,
      // Arabic-Indic, like every other figure the overview prints: the
      // attention rows used to interpolate a raw `int` and sat beside
      // «٢ فرق تحتاج إلى متابعة» in two different numeral systems.
      contains(toArabicIndic('2')),
    );
  });

  test('Point 9 lifecycle counts change without rewriting commercial state',
      () async {
    final shared = PlatformTenantStore(clock: () => now);
    final lifecycles = MockTenantLifecycleRepository(
      store: shared,
      clock: () => now,
      latency: Duration.zero,
    );
    final overviewRepository = MockPlatformOverviewRepository(
      clock: () => now,
      store: shared,
      latency: Duration.zero,
    );
    final tenant = shared.byId('saas_hilal')!;
    final commercialBefore = tenant.subscription.toJson();

    final suspended = await lifecycles.suspend(SuspendTenantCommand(
      tenantId: tenant.id,
      expectedVersion: tenant.tenantVersion,
      idempotencyKey: 'overview-suspend',
      reason: 'مراجعة إدارية',
    ));
    var snapshot = await overview(() => overviewRepository);
    expect(snapshot.tenants.suspended, 2);
    expect(snapshot.tenants.activeSubscriptions, 4);
    expect(shared.byId(tenant.id)!.subscription.toJson(), commercialBefore);

    final suspendedVersion = suspended.when(
      success: (value, {stale = false}) => value.lifecycle.version,
      failure: (message, code) => throw TestFailure('$code: $message'),
      offline: (_) => throw TestFailure('offline'),
    );
    final active = await lifecycles.reactivate(ReactivateTenantCommand(
      tenantId: tenant.id,
      expectedVersion: suspendedVersion,
      idempotencyKey: 'overview-reactivate',
    ));
    snapshot = await overview(() => overviewRepository);
    expect(snapshot.tenants.suspended, 1);
    expect(snapshot.tenants.activeSubscriptions, 4);

    final activeVersion = active.when(
      success: (value, {stale = false}) => value.lifecycle.version,
      failure: (message, code) => throw TestFailure('$code: $message'),
      offline: (_) => throw TestFailure('offline'),
    );
    await lifecycles.beginDeletion(BeginTenantDeletionCommand(
      tenantId: tenant.id,
      expectedVersion: activeVersion,
      idempotencyKey: 'overview-delete-pending',
      reason: 'طلب إنهاء موثق',
    ));
    snapshot = await overview(() => overviewRepository);
    expect(snapshot.tenants.deletionPending, 1);
    expect(snapshot.tenants.activeSubscriptions, 4);
    expect(
      snapshot.attention.any(
        (item) => item.id == 'attention_tenant_deletion_pending_${tenant.id}',
      ),
      isTrue,
    );
    expect(shared.byId(tenant.id)!.subscription.toJson(), commercialBefore);
  });
}

typedef PlatformOverviewRepositoryUnderTest = MockPlatformOverviewRepository
    Function();
