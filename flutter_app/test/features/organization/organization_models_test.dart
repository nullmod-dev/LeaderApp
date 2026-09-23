import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/organization/data/mock_organization_repository.dart';
import 'package:mtm/features/organization/domain/organization_models.dart';
import 'package:mtm/features/organization/domain/organization_repository.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';

/// Point 15 — the tenant-facing organisation read: the closed plan catalogue,
/// fail-safe parsing, the canonical effective-limit rule, factual standings,
/// usage visibility, offline/stale behaviour and what the read never carries.
void main() {
  final now = DateTime.utc(2026, 9, 12, 9);

  PlatformTenantStore store() => PlatformTenantStore(clock: () => now);

  OrganizationSnapshot project(String tenantId, {bool usage = true}) =>
      MockOrganizationRepository.project(
        store().byId(tenantId)!,
        now: now,
        usage: usage,
      );

  OrganizationLimit line(OrganizationSnapshot s, PlanLimitKey key) =>
      s.limits.items.singleWhere((item) => item.key == key);

  group('plan catalogue is exactly Basic, Standard and Advanced', () {
    test('the three platform plan ids map to the three tiers', () {
      expect(PlanTier.values, hasLength(3));
      expect(OrganizationPlan.fromWire('mtm_core'),
          const OrganizationPlanKnown(PlanTier.basic));
      expect(OrganizationPlan.fromWire('mtm_standard'),
          const OrganizationPlanKnown(PlanTier.standard));
      expect(OrganizationPlan.fromWire('mtm_advanced'),
          const OrganizationPlanKnown(PlanTier.advanced));
    });

    test('null is an explicit no-plan; an unknown id is never Basic', () {
      expect(OrganizationPlan.fromWire(null), isA<OrganizationPlanNone>());
      final unknown = OrganizationPlan.fromWire('mtm_enterprise');
      expect(unknown, isA<OrganizationPlanUnsupported>());
      expect(unknown, isNot(const OrganizationPlanKnown(PlanTier.basic)));
      expect(OrganizationPlan.fromWire(42), isA<OrganizationPlanUnsupported>());
    });
  });

  group('fail-safe parsing', () {
    Map<String, dynamic> wire() => {
          'organization': {
            'tenantId': 'saas_x',
            'displayName': 'مؤسسة',
            'lifecycleStatus': 'frozen_v9',
            'createdAt': '2025-01-08T00:00:00Z',
          },
          'subscription': {'status': 'paused_v9', 'planId': 'mtm_gold'},
          'limits': {
            'usageIncluded': true,
            'items': [
              {'key': 'detachments', 'effective': 10, 'usage': 3},
              {'key': 'rockets', 'effective': 5},
              {'key': 'members', 'effective': -4},
            ],
          },
          'readAt': '2026-09-12T09:00:00Z',
        };

    test('unknown lifecycle, status and plan become unsupported, not active',
        () {
      final snapshot = OrganizationSnapshot.fromJson(wire());
      expect(snapshot.lifecycle, isNull);
      expect(snapshot.subscription.status, isNull);
      expect(snapshot.subscription.plan, isA<OrganizationPlanUnsupported>());
      expect(snapshot.subscription.relevantDate, isNull);
    });

    test('unknown limit keys are counted, missing and invalid keys unavailable',
        () {
      final limits = OrganizationSnapshot.fromJson(wire()).limits;
      expect(limits.items.map((i) => i.key), PlanLimitKey.values);
      expect(limits.unsupportedCount, 1);
      final byKey = {for (final item in limits.items) item.key: item};
      expect(byKey[PlanLimitKey.detachments]!.standing, LimitStanding.within);
      // A negative figure is not a limit, and a missing key is not unlimited.
      expect(byKey[PlanLimitKey.members]!.standing, LimitStanding.unavailable);
      expect(byKey[PlanLimitKey.workshops]!.effective, isNull);
      expect(
          byKey[PlanLimitKey.workshops]!.standing, LimitStanding.unavailable);
    });

    test('readAt is required; a malformed optional date is dropped', () {
      final missing = wire()..remove('readAt');
      expect(
          () => OrganizationSnapshot.fromJson(missing), throwsFormatException);
      final bad = wire();
      (bad['organization'] as Map<String, dynamic>)['createdAt'] = 'yesterday';
      expect(OrganizationSnapshot.fromJson(bad).createdAt, isNull);
    });

    test('a projected snapshot survives its own wire round-trip', () {
      final original = project('saas_sahel');
      final again = OrganizationSnapshot.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(again.displayName, original.displayName);
      expect(again.lifecycle, original.lifecycle);
      expect(again.subscription.status, original.subscription.status);
      expect(again.subscription.plan, original.subscription.plan);
      for (final key in PlanLimitKey.values) {
        expect(line(again, key).effective, line(original, key).effective);
        expect(line(again, key).usage, line(original, key).usage);
        expect(line(again, key).overridden, line(original, key).overridden);
      }
    });
  });

  group('limits use the canonical effective rule', () {
    test('plan default when there is no override', () {
      final hilal = project('saas_hilal');
      final detachments = line(hilal, PlanLimitKey.detachments);
      expect(detachments.effective, 40); // Advanced default
      expect(detachments.planDefault, 40);
      expect(detachments.overridden, isFalse);
      expect(detachments.usage, 23);
      expect(detachments.standing, LimitStanding.within);
    });

    test('override wins over the plan default', () {
      final sahel = project('saas_sahel');
      final detachments = line(sahel, PlanLimitKey.detachments);
      expect(detachments.effective, 10);
      expect(detachments.planDefault, 15); // Standard default
      expect(detachments.overridden, isTrue);
      // Every other key still follows its default.
      expect(line(sahel, PlanLimitKey.members).overridden, isFalse);
      expect(line(sahel, PlanLimitKey.members).effective, 300);
    });

    test('an explicit no-plan reports no limit at all, never unlimited', () {
      final nabd = project('saas_nabd');
      expect(nabd.subscription.plan, isA<OrganizationPlanNone>());
      for (final item in nabd.limits.items) {
        expect(item.effective, isNull, reason: item.key.wire);
        expect(item.standing, LimitStanding.unavailable);
      }
    });

    test('standings are factual: within, at, over — no "near"', () {
      OrganizationLimit of(int limit, int usage) => OrganizationLimit(
            key: PlanLimitKey.members,
            effective: limit,
            usage: usage,
          );
      expect(of(10, 9).standing, LimitStanding.within);
      expect(of(10, 10).standing, LimitStanding.atLimit);
      expect(of(10, 11).standing, LimitStanding.overLimit);
      expect(of(0, 0).standing, LimitStanding.atLimit);
      expect(
        OrganizationLimit(key: PlanLimitKey.members, effective: 10).standing,
        LimitStanding.limitOnly,
      );
      expect(LimitStanding.values, hasLength(5));
    });

    test('ratio is zero-safe and clamped', () {
      OrganizationLimit of(int limit, int usage) => OrganizationLimit(
            key: PlanLimitKey.members,
            effective: limit,
            usage: usage,
          );
      expect(of(0, 0).ratio, 0);
      expect(of(0, 3).ratio, 1);
      expect(of(10, 25).ratio, 1);
      expect(of(40, 10).ratio, 0.25);
      expect(
        OrganizationLimit(key: PlanLimitKey.members, effective: 10).ratio,
        isNull,
      );
    });
  });

  group('the mock tenant adapter', () {
    MockOrganizationRepository repo({
      String? tenantId = 'saas_hilal',
      bool usage = true,
      MockOrganizationMode mode = MockOrganizationMode.loaded,
    }) =>
        MockOrganizationRepository(
          store: store(),
          clock: () => now,
          tenantId: () => tenantId,
          usageVisible: () => usage,
          mode: mode,
          latency: Duration.zero,
        );

    test('reads the session tenant, with the canonical record', () async {
      final result = await repo().readCurrent();
      final snapshot = (result as Success<OrganizationSnapshot>).data;
      expect(result.stale, isFalse);
      expect(snapshot.tenantId, 'saas_hilal');
      expect(snapshot.displayName, 'فرق الهلال الطبية');
      expect(snapshot.lifecycle, SaasTenantStatus.active);
      expect(snapshot.subscription.status, SubscriptionStatus.active);
      expect(snapshot.mainAdminName, 'سلمى الحارثي');
      expect(snapshot.readAt, now);
    });

    test('usage figures are withheld when the session may not see them',
        () async {
      final result = await repo(usage: false).readCurrent();
      final limits = (result as Success<OrganizationSnapshot>).data.limits;
      expect(limits.usageIncluded, isFalse);
      for (final item in limits.items) {
        expect(item.usage, isNull);
        expect(item.effective, isNotNull);
        expect(item.standing, LimitStanding.limitOnly);
      }
    });

    test('no tenant on the session is a typed, designed failure', () async {
      final result = await repo(tenantId: null).readCurrent();
      expect(result, isA<Failure<OrganizationSnapshot>>());
      expect(
        OrganizationProblemCode.parse((result as Failure).code),
        OrganizationProblemCode.contextUnavailable,
      );
    });

    test('offline returns the last read, or nothing before the first',
        () async {
      final mock = repo(mode: MockOrganizationMode.offline);
      final cold = await mock.readCurrent();
      expect((cold as Offline<OrganizationSnapshot>).cached, isNull);

      mock.mode = MockOrganizationMode.loaded;
      await mock.readCurrent();
      mock.mode = MockOrganizationMode.offline;
      final warm = await mock.readCurrent();
      expect((warm as Offline<OrganizationSnapshot>).cached?.tenantId,
          'saas_hilal');
    });

    test('stale is a flagged success; failure is a server problem', () async {
      final stale = await repo(mode: MockOrganizationMode.stale).readCurrent();
      expect((stale as Success).stale, isTrue);
      final failed =
          await repo(mode: MockOrganizationMode.failure).readCurrent();
      expect((failed as Failure).code, 'server');
    });

    test('unsupported values arrive as unsupported, not as defaults', () async {
      final result =
          await repo(mode: MockOrganizationMode.unsupported).readCurrent();
      final snapshot = (result as Success<OrganizationSnapshot>).data;
      expect(snapshot.lifecycle, isNull);
      expect(snapshot.subscription.status, isNull);
      expect(snapshot.subscription.plan, isA<OrganizationPlanUnsupported>());
      expect(snapshot.limits.unsupportedCount, 1);
      expect(line(snapshot, PlanLimitKey.workshops).standing,
          LimitStanding.unavailable);
    });

    test('the read carries no Team Code, login email or secret', () async {
      final record = store().byId('saas_hilal')!;
      final result = await repo().readCurrent();
      final json =
          jsonEncode((result as Success<OrganizationSnapshot>).data.toJson());
      expect(json, isNot(contains(record.teamCode)));
      expect(json, isNot(contains(record.mainAdmin.email)));
      for (final forbidden in [
        'teamCode',
        'email',
        'password',
        'token',
        'reason',
        'version',
        'price',
        'currency',
      ]) {
        expect(json, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });
}
