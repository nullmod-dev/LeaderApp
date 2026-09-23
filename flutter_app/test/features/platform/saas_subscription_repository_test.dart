import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_tenant_subscription_repository.dart';
import 'package:mtm/features/platform/data/platform_subscription_fixtures.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/data/saas_subscription_providers.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/domain/saas_subscription_models.dart';
import 'package:mtm/features/platform/domain/saas_subscription_repository.dart';
import 'package:mtm/features/platform/domain/saas_tenant_models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 8, 16);

  PlatformTenantStore store() => PlatformTenantStore(clock: () => now);

  MockTenantSubscriptionRepository repo({
    PlatformTenantStore? on,
    MockTenantSubscriptionMode mode = MockTenantSubscriptionMode.loaded,
    Duration latency = Duration.zero,
  }) =>
      MockTenantSubscriptionRepository(
        store: on ?? store(),
        clock: () => now,
        mode: mode,
        latency: latency,
      );

  T unwrap<T>(Result<T> result) => result.when(
        success: (data, {stale = false}) => data,
        failure: (message, code) => throw TestFailure('$code: $message'),
        offline: (_) => throw TestFailure('offline'),
      );

  String? failureCode<T>(Result<T> result) => result.when(
        success: (_, {stale = false}) => null,
        failure: (_, code) => code,
        offline: (_) => 'offline',
      );

  group('domain', () {
    test('subscription status parsing refuses unknown values', () {
      expect(SubscriptionStatus.parse('trial'), SubscriptionStatus.trial);
      expect(SubscriptionStatus.parse('active'), SubscriptionStatus.active);
      expect(SubscriptionStatus.parse('grace'), SubscriptionStatus.grace);
      expect(SubscriptionStatus.parse('suspended'), isNull,
          reason: 'suspended is tenant access, never billing');
    });

    test('tenant status and subscription status remain independent', () {
      final tenant = store().byId('saas_rukn')!;
      expect(tenant.tenantStatus, SaasTenantStatus.suspended);
      expect(tenant.subscription.status, SubscriptionStatus.inactive);
      expect(tenant.listStatus, SaasTenantListStatus.suspended);
    });

    test('effective limit uses override and reset falls back to plan', () {
      final plan = canonicalPlanById('mtm_standard')!;
      final tenant = store().byId('saas_afiah')!;
      expect(tenant.subscription.hasOverride(PlanLimitKey.detachments), isTrue);
      expect(
        tenant.subscription.effectiveLimit(PlanLimitKey.detachments, plan),
        20,
      );
      final reset = tenant.subscription.copyWith(limitOverrides: const {});
      expect(reset.effectiveLimit(PlanLimitKey.detachments, plan), 15);
    });

    test('usage comparisons handle zero and above-limit values safely', () {
      final usage = TenantPlanUsage({
        for (final key in PlanLimitKey.values)
          key: key == PlanLimitKey.members ? 8 : 0,
      });
      expect(usage.isAbove(PlanLimitKey.members, 5), isTrue);
      expect(usage.ratio(PlanLimitKey.members, 0), 1);
      expect(usage.ratio(PlanLimitKey.detachments, 0), 0);
    });
  });

  group('repository reads', () {
    test('reads the subscription and the small selectable catalogue', () async {
      final details = unwrap(await repo().getSubscription('saas_hilal'));
      final plans = unwrap(await repo().listPlans());
      expect(details.subscription.status, SubscriptionStatus.active);
      expect(details.currentPlan?.id, 'mtm_advanced');
      expect(plans, hasLength(3));
      expect(plans.where((plan) => plan.recommended), hasLength(1));
    });

    test('no-plan trial is explicit and limits refuse to invent a plan',
        () async {
      final r = repo();
      final details = unwrap(await r.getSubscription('saas_nabd'));
      expect(details.subscription.plan, isA<NoSaasPlan>());
      expect(
        failureCode(await r.getLimits('saas_nabd')),
        SubscriptionProblemCode.planNotFound.wire,
      );
    });

    test('limits combine platform aggregate usage with effective limits',
        () async {
      final snapshot = unwrap(await repo().getLimits('saas_afiah'));
      expect(snapshot.usage[PlanLimitKey.detachments], 15);
      expect(snapshot.effectiveLimit(PlanLimitKey.detachments), 20);
      expect(
          snapshot.subscription.hasOverride(PlanLimitKey.detachments), isTrue);
    });
  });

  group('legal transitions and deterministic Clock', () {
    test('trial activation assigns a plan and updates canonical truth',
        () async {
      final shared = store();
      final before = shared.byId('saas_nabd')!;
      final result = unwrap(await repo(on: shared).activate(
        ActivateSubscriptionCommand(
          tenantId: before.id,
          expectedVersion: before.subscription.version,
          planId: 'mtm_standard',
        ),
      ));
      expect(result.subscription.status, SubscriptionStatus.active);
      expect(result.subscription.renewsAt, now.add(const Duration(days: 365)));
      expect(shared.byId(before.id)!.subscription.status,
          SubscriptionStatus.active);
      expect(shared.tenantSummary().activeSubscriptions, 5);
      expect(shared.tenantSummary().activeTrials, 1);
    });

    test('trial extension must move the existing expiry forward', () async {
      final shared = store();
      final tenant = shared.byId('saas_masar')!;
      final newEnd =
          tenant.subscription.trialEndsAt!.add(const Duration(days: 7));
      final updated = unwrap(await repo(on: shared).extendTrial(
        ExtendTrialCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.subscription.version,
          newEndsAt: newEnd,
        ),
      ));
      expect(updated.subscription.trialEndsAt, newEnd);
      expect(updated.subscription.version, 2);
      expect(
        shared.historyOf(shared.byId(tenant.id)!).first.type,
        SaasTenantEventType.trialExtended,
      );
    });

    test('ending a trial starts grace without suspending the tenant', () async {
      final shared = store();
      final tenant = shared.byId('saas_nabd')!;
      final updated = unwrap(await repo(on: shared).endTrial(
        SubscriptionVersionedCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.subscription.version,
        ),
      ));
      expect(updated.subscription.status, SubscriptionStatus.grace);
      expect(
          updated.subscription.graceEndsAt, now.add(const Duration(days: 14)));
      expect(shared.byId(tenant.id)!.tenantStatus, SaasTenantStatus.active);
    });

    test('active moves to grace, and grace activates again', () async {
      final shared = store();
      final r = repo(on: shared);
      final active = shared.byId('saas_wadi')!;
      final grace = unwrap(await r.moveToGrace(
        SubscriptionVersionedCommand(
          tenantId: active.id,
          expectedVersion: active.subscription.version,
        ),
      ));
      expect(grace.subscription.status, SubscriptionStatus.grace);
      final restored = unwrap(await r.activate(
        ActivateSubscriptionCommand(
          tenantId: active.id,
          expectedVersion: grace.subscription.version,
          planId: 'mtm_core',
        ),
      ));
      expect(restored.subscription.status, SubscriptionStatus.active);
    });

    test('plan changes and tenant overrides survive the change', () async {
      final shared = store();
      final tenant = shared.byId('saas_afiah')!;
      final updated = unwrap(await repo(on: shared).changePlan(
        ChangePlanCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.subscription.version,
          planId: 'mtm_advanced',
        ),
      ));
      expect(updated.currentPlan?.id, 'mtm_advanced');
      expect(updated.subscription.limitOverrides[PlanLimitKey.detachments], 20);
    });

    test('a below-usage override is stored and deletes no data', () async {
      final shared = store();
      final tenant = shared.byId('saas_afiah')!;
      final countsBefore = tenant.counts.toJson();
      final snapshot = unwrap(await repo(on: shared).updateLimitOverride(
        UpdateLimitOverrideCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.subscription.version,
          key: PlanLimitKey.detachments,
          overrideValue: 5,
        ),
      ));
      expect(snapshot.isBelowUsage(PlanLimitKey.detachments, 5), isTrue);
      expect(snapshot.effectiveLimit(PlanLimitKey.detachments), 5);
      expect(shared.byId(tenant.id)!.counts.toJson(), countsBefore,
          reason: 'limit reduction is not data deletion');
    });

    test('reset removes only the override', () async {
      final shared = store();
      final tenant = shared.byId('saas_afiah')!;
      final snapshot = unwrap(await repo(on: shared).updateLimitOverride(
        UpdateLimitOverrideCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.subscription.version,
          key: PlanLimitKey.detachments,
        ),
      ));
      expect(
          snapshot.subscription.hasOverride(PlanLimitKey.detachments), isFalse);
      expect(snapshot.effectiveLimit(PlanLimitKey.detachments), 15);
    });
  });

  group('refusals', () {
    test('illegal transition is refused', () async {
      final tenant = store().byId('saas_hilal')!;
      expect(
        failureCode(await repo().endTrial(
          SubscriptionVersionedCommand(
            tenantId: tenant.id,
            expectedVersion: tenant.subscription.version,
          ),
        )),
        SubscriptionProblemCode.invalidTransition.wire,
      );
    });

    test('stale version is refused before mutation', () async {
      final shared = store();
      final before = shared.byId('saas_hilal')!;
      final result = await repo(on: shared).moveToGrace(
        SubscriptionVersionedCommand(
          tenantId: before.id,
          expectedVersion: 999,
        ),
      );
      expect(
          failureCode(result), SubscriptionProblemCode.staleSubscription.wire);
      expect(shared.byId(before.id)!.subscription.status,
          SubscriptionStatus.active);
    });

    test('offline writes are refused and never queued', () async {
      final tenant = store().byId('saas_hilal')!;
      final result = await repo(mode: MockTenantSubscriptionMode.offline)
          .moveToGrace(SubscriptionVersionedCommand(
        tenantId: tenant.id,
        expectedVersion: tenant.subscription.version,
      ));
      expect(result.isOffline, isTrue);
    });
  });

  group('controller', () {
    ProviderContainer container({
      MockTenantSubscriptionMode mode = MockTenantSubscriptionMode.loaded,
      Duration latency = Duration.zero,
    }) {
      final value = ProviderContainer(overrides: [
        clockProvider.overrideWithValue(() => now),
        tenantSubscriptionRepositoryProvider.overrideWith((ref) {
          return MockTenantSubscriptionRepository(
            store: ref.watch(platformTenantStoreProvider),
            clock: () => now,
            mode: mode,
            latency: latency,
          );
        }),
      ]);
      addTearDown(value.dispose);
      return value;
    }

    test('two quick actions produce one repository mutation', () async {
      final c = container(latency: const Duration(milliseconds: 30));
      final tenant = c.read(platformTenantStoreProvider).byId('saas_hilal')!;
      final controller = c.read(subscriptionActionControllerProvider.notifier);
      final command = SubscriptionVersionedCommand(
        tenantId: tenant.id,
        expectedVersion: tenant.subscription.version,
      );
      final first = controller.moveToGrace(command);
      final second = await controller.moveToGrace(command);
      expect(second, isA<SubscriptionActionIgnored>());
      expect(await first, isA<SubscriptionActionSucceeded>());
      expect(
          c
              .read(platformTenantStoreProvider)
              .byId(tenant.id)!
              .subscription
              .version,
          2);
    });

    test('stale and offline outcomes stay typed', () async {
      final stale = container();
      final staleController =
          stale.read(subscriptionActionControllerProvider.notifier);
      expect(
        await staleController.moveToGrace(const SubscriptionVersionedCommand(
          tenantId: 'saas_hilal',
          expectedVersion: 88,
        )),
        isA<SubscriptionActionStale>(),
      );

      final offline = container(mode: MockTenantSubscriptionMode.offline);
      final tenant =
          offline.read(platformTenantStoreProvider).byId('saas_hilal')!;
      expect(
        await offline
            .read(subscriptionActionControllerProvider.notifier)
            .moveToGrace(SubscriptionVersionedCommand(
              tenantId: tenant.id,
              expectedVersion: tenant.subscription.version,
            )),
        isA<SubscriptionActionOffline>(),
      );
    });
  });
}
