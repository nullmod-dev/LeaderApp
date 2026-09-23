import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_platform_audit_repository.dart';
import 'package:mtm/features/platform/data/mock_platform_reports_repository.dart';
import 'package:mtm/features/platform/data/mock_tenant_subscription_repository.dart';
import 'package:mtm/features/platform/data/platform_audit_fixtures.dart';
import 'package:mtm/features/platform/data/platform_reports_providers.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/domain/platform_audit_models.dart';
import 'package:mtm/features/platform/domain/platform_report_datasets.dart';
import 'package:mtm/features/platform/domain/platform_report_models.dart';
import 'package:mtm/features/platform/domain/saas_subscription_models.dart';
import 'package:mtm/features/tenant_feature/domain/tenant_feature_models.dart';

import 'platform_harness.dart';

/// Point 13A — the deterministic mock, its states, pagination, consistency
/// with Points 5–11, and the control-plane separation guarantees.
void main() {
  final now = DateTime.utc(2026, 9, 11, 9);
  DateTime clock() => now;

  late PlatformTenantStore store;
  late PlatformAuditFixtures audit;

  setUp(() {
    store = PlatformTenantStore(clock: clock);
    audit = PlatformAuditFixtures(clock: clock);
  });

  MockPlatformReportsRepository repo({
    MockPlatformReportsMode mode = MockPlatformReportsMode.loaded,
    Duration? auditRetention,
  }) =>
      MockPlatformReportsRepository(
        store: store,
        auditFixtures: audit,
        clock: clock,
        mode: mode,
        auditRetention: auditRetention,
      );

  T ok<T>(Result<T> result) {
    expect(result, isA<Success<T>>(), reason: '$result');
    return (result as Success<T>).data;
  }

  group('subscriptions report', () {
    test('agrees with the canonical store and the Point 5 counts', () async {
      final report = ok(await repo().loadSubscriptions(
        SubscriptionReportQuery(),
      ));
      final summary = store.tenantSummary();
      expect(report.summary.tenantCount, store.tenants.length);
      expect(report.summary.byStatus[SubscriptionStatus.active],
          summary.activeSubscriptions);
      expect(report.summary.byStatus[SubscriptionStatus.trial],
          summary.activeTrials);
      expect(report.summary.byStatus[SubscriptionStatus.grace],
          summary.gracePeriod);
      expect(report.summary.byLifecycle[SaasTenantStatus.suspended],
          summary.suspended);
      expect(report.summary.byStatus.unsupported, 0);
      expect(report.meta.generatedAt, now);
      expect(report.rows.items.length, store.tenants.length);
    });

    test('rows are canonically ordered and carry only control-plane fields',
        () async {
      final report = ok(await repo().loadSubscriptions(
        SubscriptionReportQuery(),
      ));
      final sorted = [...report.rows.items]..sort(compareSubscriptionRows);
      expect(report.rows.items.map((r) => r.tenant.id),
          sorted.map((r) => r.tenant.id));
      for (final row in report.rows.items) {
        final tenant = store.byId(row.tenant.id)!;
        expect(row.tenant.displayName, tenant.displayName);
        expect(row.plan?.id, tenant.subscription.plan.planId);
        expect(row.relevantDate, tenant.subscription.relevantDate);
      }
      final plans =
          report.summary.byPlan.fold<int>(0, (sum, b) => sum + b.count);
      expect(plans, report.summary.tenantCount);
      if (report.summary.byPlan.any((b) => b.plan == null)) {
        expect(report.summary.byPlan.last.plan, isNull);
      }
    });

    test('filters apply before the summary; filtered-empty is distinct',
        () async {
      final grace = ok(await repo().loadSubscriptions(
        SubscriptionReportQuery(statuses: const {SubscriptionStatus.grace}),
      ));
      expect(grace.summary.tenantCount, store.tenantSummary().gracePeriod);
      expect(
        grace.rows.items.every(
          (r) => r.status.valueOrNull == SubscriptionStatus.grace,
        ),
        isTrue,
      );

      final soon = ok(await repo().loadSubscriptions(
        SubscriptionReportQuery(dueBefore: now.add(const Duration(days: 30))),
      ));
      for (final row in soon.rows.items) {
        expect(row.relevantDate!.isBefore(now.add(const Duration(days: 30))),
            isTrue);
      }

      final none = await repo().loadSubscriptions(SubscriptionReportQuery(
        statuses: const {SubscriptionStatus.grace},
        lifecycles: const {SaasTenantStatus.deletionPending},
      ));
      expect(
          platformReportViewState(none), PlatformReportViewState.filteredEmpty);
    });

    test('pages one frozen snapshot with opaque cursors', () async {
      final r = repo();
      final first = ok(await r.loadSubscriptions(
        SubscriptionReportQuery(limit: 3),
      ));
      var state = PlatformReportRowsState.firstPage(
        snapshotId: first.meta.snapshotId,
        page: first.rows,
      );
      var guard = 0;
      while (state.canLoadMore && guard++ < 10) {
        final cursor = state.nextCursor!;
        final next = ok(await r.loadSubscriptions(
          SubscriptionReportQuery(limit: 3).withCursor(cursor),
        ));
        expect(next.meta.snapshotId, first.meta.snapshotId);
        expect(next.meta.generatedAt, first.meta.generatedAt);
        state = state.appendPage(
          cursor: cursor,
          snapshotId: next.meta.snapshotId,
          page: next.rows,
          keyOf: (row) => row.tenant.id,
        );
      }
      final all = ok(await r.loadSubscriptions(SubscriptionReportQuery()));
      expect(state.items.map((row) => row.tenant.id),
          all.rows.items.map((row) => row.tenant.id));
      expect(state.mustReload, isFalse);
    });

    test('a cursor is refused for another query, when malformed, or expired',
        () async {
      final r = repo();
      final first = ok(await r.loadSubscriptions(
        SubscriptionReportQuery(limit: 2),
      ));
      final cursor = first.rows.nextCursor!;

      final other = await r.loadSubscriptions(SubscriptionReportQuery(
        statuses: const {SubscriptionStatus.active},
        limit: 2,
        cursor: cursor,
      ));
      expect((other as Failure).code, 'validation');

      final garbage = await r.loadSubscriptions(
        SubscriptionReportQuery(limit: 2, cursor: 'not/a*cursor'),
      );
      expect((garbage as Failure).code, 'validation');

      // Eight newer snapshots evict the first one.
      for (var i = 0; i < 8; i++) {
        await r.loadSubscriptions(SubscriptionReportQuery(limit: 2));
      }
      final expired = await r.loadSubscriptions(
        SubscriptionReportQuery(limit: 2, cursor: cursor),
      );
      expect((expired as Failure).code,
          PlatformReportProblemCode.cursorExpired.wire);
    });
  });

  group('states', () {
    test('empty platform is empty, not filtered-empty', () async {
      final r = repo(mode: MockPlatformReportsMode.empty);
      final result = await r.loadSubscriptions(SubscriptionReportQuery());
      expect(platformReportViewState(result), PlatformReportViewState.empty);
      expect(ok(result).summary.byPlan, isEmpty);
      final activity = await r.loadPlatformActivity(
        PlatformActivityReportQuery.defaultAt(now),
      );
      expect(platformReportViewState(activity), PlatformReportViewState.empty);
    });

    test('stale and offline-cached results keep their older generation time',
        () async {
      final stale = await repo(mode: MockPlatformReportsMode.stale)
          .loadUsageLimits(UsageLimitsReportQuery());
      expect(platformReportFreshness(stale), PlatformReportFreshness.stale);
      expect(ok(stale).meta.generatedAt, now.subtract(kMockReportCacheAge));

      final offline = repo(mode: MockPlatformReportsMode.offlineWithCache);
      final cached = await offline.loadFeatureAvailability(
        FeatureAvailabilityReportQuery(limit: 2),
      );
      expect(platformReportFreshness(cached),
          PlatformReportFreshness.offlineCached);
      final report = (cached as Offline<FeatureAvailabilityReport>).cached!;
      expect(report.meta.generatedAt, now.subtract(kMockReportCacheAge));
      expect(platformReportViewState(cached), PlatformReportViewState.loaded);

      // Paging is online-only: a cached page cannot be continued.
      final next = await offline.loadFeatureAvailability(
        FeatureAvailabilityReportQuery(limit: 2)
            .withCursor(report.rows.nextCursor),
      );
      expect(next, isA<Offline<FeatureAvailabilityReport>>());
      expect((next as Offline).cached, isNull);
    });

    test('offline without cache, failure and not-permitted are distinct',
        () async {
      final query = SubscriptionReportQuery();
      expect(
        platformReportViewState(
          await repo(mode: MockPlatformReportsMode.offlineWithoutCache)
              .loadSubscriptions(query),
        ),
        PlatformReportViewState.offlineNoData,
      );
      expect(
        platformReportViewState(
          await repo(mode: MockPlatformReportsMode.failure)
              .loadSubscriptions(query),
        ),
        PlatformReportViewState.failure,
      );
      expect(
        platformReportViewState(
          await repo(mode: MockPlatformReportsMode.notPermitted)
              .loadPlatformActivity(PlatformActivityReportQuery.defaultAt(now)),
        ),
        PlatformReportViewState.notPermitted,
      );
    });

    test('a next-page failure keeps loaded rows; an expired cursor reloads',
        () async {
      for (final mode in [
        MockPlatformReportsMode.nextPageFailure,
        MockPlatformReportsMode.cursorExpired,
      ]) {
        final r = repo(mode: mode);
        final first = ok(await r.loadSubscriptions(
          SubscriptionReportQuery(limit: 2),
        ));
        final state = PlatformReportRowsState.firstPage(
          snapshotId: first.meta.snapshotId,
          page: first.rows,
        );
        final next = await r.loadSubscriptions(
          SubscriptionReportQuery(limit: 2).withCursor(state.nextCursor),
        );
        final after = state.pageFailure(code: (next as Failure).code);
        expect(after.items.length, 2);
        if (mode == MockPlatformReportsMode.nextPageFailure) {
          expect(after.pageFailed, isTrue);
          expect(after.canLoadMore, isTrue);
        } else {
          expect(after.mustReload, isTrue);
        }
      }
    });

    test('unsupported values land in unsupported buckets, never in known ones',
        () async {
      final r = repo(mode: MockPlatformReportsMode.unsupportedValues);
      final report = ok(await r.loadSubscriptions(SubscriptionReportQuery()));
      expect(report.summary.tenantCount, store.tenants.length + 1);
      expect(report.summary.byStatus.unsupported, 1);
      expect(report.summary.byLifecycle.unsupported, 1);
      expect(
          report.rows.items.where((row) => !row.status.isSupported).length, 1);

      final filtered = ok(await r.loadSubscriptions(SubscriptionReportQuery(
        lifecycles: const {SaasTenantStatus.active},
      )));
      expect(filtered.rows.items.every((row) => row.lifecycle.isSupported),
          isTrue);

      final features = ok(await r.loadFeatureAvailability(
        FeatureAvailabilityReportQuery(),
      ));
      for (final key in TenantFeatureKey.values) {
        expect(features.summary.byFeature[key]!.unsupported, 1);
      }
    });

    test('the Clock alone positions results; repeated reads are identical',
        () async {
      final a = ok(await repo().loadPlatformActivity(
        PlatformActivityReportQuery.defaultAt(now),
      ));
      final b = ok(await repo().loadPlatformActivity(
        PlatformActivityReportQuery.defaultAt(now),
      ));
      expect(a.meta.generatedAt, now);
      expect(b.byAction.counts, a.byAction.counts);
      expect(b.byAction.unsupported, a.byAction.unsupported);
    });
  });

  group('usage & limits report', () {
    test('matches the Point 7 limits snapshot for every tenant', () async {
      final report = ok(await repo().loadUsageLimits(UsageLimitsReportQuery()));
      final limits = MockTenantSubscriptionRepository(
        store: store,
        clock: clock,
        latency: Duration.zero,
      );
      for (final row in report.rows.items) {
        final snapshot = await limits.getLimits(row.tenant.id);
        if (row.plan == null) {
          expect(row.cells.values.every((c) => c.limit == null), isTrue);
          continue;
        }
        final data = ok(snapshot);
        for (final key in PlanLimitKey.values) {
          expect(row.cells[key]!.usage, data.usage[key], reason: key.wire);
          expect(row.cells[key]!.limit, data.effectiveLimit(key));
          expect(
              row.cells[key]!.overridden, data.subscription.hasOverride(key));
        }
      }
      for (final key in PlanLimitKey.values) {
        expect(report.summary.byKey[key]!.total, report.summary.tenantCount);
      }
    });

    test('ranks by the chosen limit and filters by factual band', () async {
      final ranked = ok(await repo().loadUsageLimits(
        UsageLimitsReportQuery(limitKey: PlanLimitKey.members),
      ));
      final sorted = [...ranked.rows.items]
        ..sort((a, b) => compareUsageRows(a, b, key: PlanLimitKey.members));
      expect(ranked.rows.items.map((r) => r.tenant.id),
          sorted.map((r) => r.tenant.id));

      final noLimit = ok(await repo().loadUsageLimits(UsageLimitsReportQuery(
        limitKey: PlanLimitKey.members,
        bands: const {UsageLimitBand.noLimit},
      )));
      expect(noLimit.rows.items.every((r) => r.plan == null), isTrue);
      expect(
        noLimit.summary.tenantCount,
        store.tenants.where((t) => t.subscription.plan.planId == null).length,
      );
    });
  });

  group('feature availability report', () {
    test('counts module entitlement only, per key, from the canonical store',
        () async {
      final report = ok(await repo().loadFeatureAvailability(
        FeatureAvailabilityReportQuery(),
      ));
      for (final key in TenantFeatureKey.values) {
        final enabled =
            store.tenants.where((t) => store.featuresOf(t.id)!.isEnabled(key));
        final breakdown = report.summary.byFeature[key]!;
        expect(breakdown[TenantFeatureAvailability.enabled], enabled.length);
        expect(breakdown[TenantFeatureAvailability.disabled],
            store.tenants.length - enabled.length);
        expect(breakdown.unsupported, 0);
      }

      final disabledWorkshops = ok(await repo().loadFeatureAvailability(
        FeatureAvailabilityReportQuery(
          featureKey: TenantFeatureKey.workshops,
          state: TenantFeatureAvailability.disabled,
        ),
      ));
      expect(
        disabledWorkshops.rows.items.every(
          (r) =>
              r.states[TenantFeatureKey.workshops]!.valueOrNull ==
              TenantFeatureAvailability.disabled,
        ),
        isTrue,
      );
    });
  });

  group('platform activity report', () {
    test('counts exactly the Audit events in range; unknown kept apart',
        () async {
      final query = PlatformActivityReportQuery.defaultAt(now);
      final report = ok(await repo().loadPlatformActivity(query));
      final inRange =
          audit.events.where((e) => query.range.contains(e.occurredAt));
      expect(report.total, inRange.length);
      expect(
        report.byAction.unsupported,
        inRange.where((e) => e.action == PlatformAuditAction.unknown).length,
      );
      expect(report.byAction.unsupported, greaterThan(0));
      expect(report.isCoveragePartial, isFalse);
    });

    test('every count opens exactly its events in the Audit Log', () async {
      final report = ok(await repo().loadPlatformActivity(
        PlatformActivityReportQuery.defaultAt(now),
      ));
      final auditRepo = MockPlatformAuditRepository(
        fixtures: audit,
        latency: Duration.zero,
      );
      for (final action in kReportableAuditActions) {
        final page = ok(await auditRepo.listAuditEvents(
          report.auditQueryFor(action),
        ));
        expect(page.items.length, report.byAction[action], reason: action.wire);
      }
    });

    test('category filter and retention coverage', () async {
      final lifecycle = ok(await repo().loadPlatformActivity(
        PlatformActivityReportQuery(
          range: PlatformReportRange.defaultAt(now),
          category: PlatformAuditCategory.lifecycle,
        ),
      ));
      expect(lifecycle.byCategory[PlatformAuditCategory.lifecycle],
          lifecycle.total);
      expect(lifecycle.total, greaterThan(0));

      final partial = ok(await repo(auditRetention: const Duration(days: 3))
          .loadPlatformActivity(PlatformActivityReportQuery.defaultAt(now)));
      expect(partial.isCoveragePartial, isTrue);
      expect(
          partial.evidenceAvailableFrom, now.subtract(const Duration(days: 3)));
      expect(
        partial.total,
        audit.events
            .where((e) =>
                !e.occurredAt.isBefore(now.subtract(const Duration(days: 3))))
            .length,
      );
    });
  });

  group('control-plane boundary and separation', () {
    test('reads mutate neither the tenant store nor Audit', () async {
      final tenantsBefore = store.tenants.map((t) => t.toJson()).toList();
      final auditBefore = audit.events.map((e) => e.toJson()).toList();
      final r = repo();
      await r.loadSubscriptions(SubscriptionReportQuery());
      await r.loadUsageLimits(UsageLimitsReportQuery());
      await r.loadFeatureAvailability(FeatureAvailabilityReportQuery());
      await r.loadPlatformActivity(PlatformActivityReportQuery.defaultAt(now));
      expect(store.tenants.map((t) => t.toJson()).toList(), tenantsBefore);
      expect(audit.events.map((e) => e.toJson()).toList(), auditBefore);
      expect(store.tombstones, isEmpty);
    });

    test('Super Admin reads build no tenant-operational repository', () async {
      final watch = TenantRepositoryWatch();
      final container = platformContainer(
        superAdmin,
        watch: watch,
        overrides: [
          clockProvider.overrideWithValue(clock),
          platformReportsMockConfigProvider.overrideWithValue(
            const MockPlatformReportsConfig(latency: Duration.zero),
          ),
        ],
      );
      ok(await container.read(
        subscriptionReportProvider(SubscriptionReportQuery()).future,
      ));
      ok(await container.read(
        usageLimitsReportProvider(UsageLimitsReportQuery()).future,
      ));
      ok(await container.read(
        featureAvailabilityReportProvider(FeatureAvailabilityReportQuery())
            .future,
      ));
      ok(await container.read(
        platformActivityReportProvider(
          PlatformActivityReportQuery.defaultAt(now),
        ).future,
      ));
      expect(watch.built, isEmpty);
    });

    test(
        'report sources import no tenant, Audit/Security/Health/Break-glass '
        'repository, capability, sync or export code', () {
      const files = [
        'lib/features/platform/domain/platform_report_models.dart',
        'lib/features/platform/domain/platform_report_datasets.dart',
        'lib/features/platform/domain/platform_reports_repository.dart',
        'lib/features/platform/data/mock_platform_reports_repository.dart',
        'lib/features/platform/data/platform_reports_providers.dart',
      ];
      const forbidden = [
        'features/detachment',
        'features/team',
        'features/shift',
        'features/inventory',
        'features/workshop',
        'features/announcement',
        'features/home',
        'features/notification',
        'platform_audit_repository',
        'mock_platform_audit_repository',
        'platform_audit_list_controller',
        'platform_security',
        'platform_health',
        'platform_operations',
        'platform_break_glass',
        'platform_overview',
        'tenant_lifecycle_repository',
        'saas_subscription_repository',
        'mock_tenant_subscription_repository',
        'tenant_feature_repository',
        'core/access/capability',
        'core/export',
        'sync/',
        'outbox',
      ];
      for (final path in files) {
        final imports = File(path)
            .readAsLinesSync()
            .where((line) => line.startsWith('import '));
        for (final line in imports) {
          for (final token in forbidden) {
            expect(line.contains(token), isFalse, reason: '$path → $line');
          }
        }
      }
    });

    test('report models have no field for Team Code, contact or credentials',
        () {
      const files = [
        'lib/features/platform/domain/platform_report_models.dart',
        'lib/features/platform/domain/platform_report_datasets.dart',
      ];
      final field = RegExp(r'^\s*final\s+[\w<>?, ]+\s+(\w+);', multiLine: true);
      for (final path in files) {
        for (final match in field.allMatches(File(path).readAsStringSync())) {
          final name = match.group(1)!;
          expect(isForbiddenReportField(name), isFalse,
              reason: '$path declares $name');
        }
      }
    });
  });
}
