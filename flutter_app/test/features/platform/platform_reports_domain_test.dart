import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/platform/domain/platform_audit_models.dart';
import 'package:mtm/features/platform/domain/platform_report_datasets.dart';
import 'package:mtm/features/platform/domain/platform_report_models.dart';
import 'package:mtm/features/platform/domain/saas_subscription_models.dart';
import 'package:mtm/features/tenant_feature/domain/tenant_feature_models.dart';

/// Point 13A — the report domain: catalogue, dates, typed filters, ordering,
/// fail-safe parsing, deleted-tenant minimization and metric invariants.
void main() {
  const tenant = {'id': 'saas_a', 'displayName': 'فريق أ'};
  const generatedAt = '2026-09-11T09:00:00Z';

  Map<String, dynamic> subscriptionJson({
    List<Map<String, dynamic>>? rows,
    Map<String, dynamic>? summary,
    String type = 'subscriptions',
  }) =>
      {
        'type': type,
        'generatedAt': generatedAt,
        'snapshotId': 'snap_1',
        'summary': summary ??
            {
              'tenantCount': 1,
              'byStatus': [
                {'key': 'trial', 'count': 1},
              ],
              'byLifecycle': [
                {'key': 'active', 'count': 1},
              ],
              'byPlan': [
                {'plan': null, 'count': 1},
              ],
            },
        'rows': {
          'items': rows ??
              [
                {
                  'tenant': tenant,
                  'lifecycle': 'active',
                  'subscriptionStatus': 'trial',
                  'plan': null,
                  'relevantDate': '2026-09-20T00:00:00Z',
                },
              ],
          'nextCursor': null,
        },
      };

  group('catalogue', () {
    test('is closed: four unique report types, unknown has no definition', () {
      final types = PlatformReportCatalogue.all.map((d) => d.type).toList();
      expect(types, [
        PlatformReportType.subscriptions,
        PlatformReportType.usageLimits,
        PlatformReportType.featureAvailability,
        PlatformReportType.platformActivity,
      ]);
      expect(
        PlatformReportType.values.map((t) => t.wire).toSet().length,
        PlatformReportType.values.length,
      );
      expect(PlatformReportCatalogue.of(PlatformReportType.unknown), isNull);
      expect(PlatformReportType.parse('revenue'), PlatformReportType.unknown);
      expect(PlatformReportType.parse('unknown'), PlatformReportType.unknown);
      expect(PlatformReportType.parse(null), PlatformReportType.unknown);
    });

    test('no report is exportable and only activity reads Audit', () {
      for (final definition in PlatformReportCatalogue.all) {
        expect(definition.exportable, isFalse);
        final isActivity =
            definition.type == PlatformReportType.platformActivity;
        expect(
          definition.sources.contains(PlatformReportSource.auditEvidence),
          isActivity,
        );
        expect(
          definition.dataKind,
          isActivity
              ? PlatformReportDataKind.periodSummary
              : PlatformReportDataKind.currentSnapshot,
        );
        expect(
          definition.privacy,
          isActivity
              ? PlatformReportPrivacy.aggregateOnly
              : PlatformReportPrivacy.controlPlaneTenantRows,
        );
        expect(definition.paginatedRows, !isActivity);
      }
    });

    test('health, security and break-glass are not report sources', () {
      final names = PlatformReportSource.values.map((s) => s.name).join(',');
      expect(names.contains('health'), isFalse);
      expect(names.contains('security'), isFalse);
      expect(names.contains('breakGlass'), isFalse);
    });

    test('feature flag, capability and plan limit stay separate dimensions',
        () {
      final features =
          PlatformReportCatalogue.of(PlatformReportType.featureAvailability)!;
      final usage = PlatformReportCatalogue.of(PlatformReportType.usageLimits)!;
      expect(features.sources, {
        PlatformReportSource.featureFlags,
        PlatformReportSource.tenantLifecycle,
      });
      expect(usage.sources.contains(PlatformReportSource.featureFlags), false);
      expect(features.sources.contains(PlatformReportSource.planLimits), false);
      // There is no capability dimension anywhere in the catalogue.
      expect(
        PlatformReportFilterField.values.any(
          (f) => f.name.toLowerCase().contains('cap'),
        ),
        isFalse,
      );
    });
  });

  group('date range', () {
    test('local calendar days become [start of first, start of next) in UTC',
        () {
      final range = PlatformReportRange.localDays(
        first: DateTime(2026, 9, 1, 15),
        last: DateTime(2026, 9, 10, 8),
      );
      expect(range.from, DateTime(2026, 9, 1).toUtc());
      expect(range.before, DateTime(2026, 9, 11).toUtc());
      expect(range.from.isUtc && range.before.isUtc, isTrue);
      expect(range.firstLocalDay, DateTime(2026, 9, 1));
      expect(range.lastLocalDay, DateTime(2026, 9, 10));
    });

    test('from is inclusive, before is exclusive, timestamps are not truncated',
        () {
      final range = PlatformReportRange(
        from: DateTime.utc(2026, 9, 1),
        before: DateTime.utc(2026, 9, 2),
      );
      expect(range.contains(DateTime.utc(2026, 9, 1)), isTrue);
      expect(
        range.contains(DateTime.utc(2026, 9, 2).subtract(
          const Duration(microseconds: 1),
        )),
        isTrue,
      );
      expect(range.contains(DateTime.utc(2026, 9, 2)), isFalse);
      expect(range.contains(DateTime.utc(2026, 8, 31, 23, 59, 59)), isFalse);
    });

    test('default is the last 30 local days including today', () {
      final now = DateTime.utc(2026, 9, 11, 9);
      final range = PlatformReportRange.defaultAt(now);
      final today = now.toLocal();
      expect(range.lastLocalDay, DateTime(today.year, today.month, today.day));
      expect(
        range.firstLocalDay,
        DateTime(today.year, today.month, today.day - 29),
      );
      expect(range.contains(now), isTrue);
    });

    test('366 local days is the maximum; empty or reversed ranges throw', () {
      expect(
        () => PlatformReportRange.localDays(
          first: DateTime(2025, 9, 11),
          last: DateTime(2026, 9, 11),
        ),
        returnsNormally,
      );
      expect(
        () => PlatformReportRange.localDays(
          first: DateTime(2025, 9, 10),
          last: DateTime(2026, 9, 11),
        ),
        throwsArgumentError,
      );
      expect(
        () => PlatformReportRange.localDays(
          first: DateTime(2026, 9, 11),
          last: DateTime(2026, 9, 10),
        ),
        throwsArgumentError,
      );
      final t = DateTime.utc(2026, 9, 1);
      expect(
          () => PlatformReportRange(from: t, before: t), throwsArgumentError);
      expect(
        () => PlatformReportRange(
          from: t,
          before: t.add(const Duration(days: 368)),
        ),
        throwsArgumentError,
      );
    });

    test('report instants need an explicit offset', () {
      expect(parseReportInstant('2026-09-11T09:00:00+03:00'),
          DateTime.utc(2026, 9, 11, 6));
      expect(() => parseReportInstant('2026-09-11T09:00:00'),
          throwsFormatException);
      expect(() => parseReportInstant(12), throwsFormatException);
    });
  });

  group('typed values and breakdowns', () {
    test('unknown wire values stay unsupported, never a known value', () {
      final value = PlatformReportValue<SubscriptionStatus>.parse(
        'paused',
        SubscriptionStatus.parse,
      );
      expect(value.isSupported, isFalse);
      expect(value.valueOrNull, isNull);
      expect(
        PlatformReportValue<SubscriptionStatus>.parse(
          'grace',
          SubscriptionStatus.parse,
        ),
        const PlatformReportValue.supported(SubscriptionStatus.grace),
      );
    });

    test('breakdown zero-fills known keys and keeps unknown keys counted', () {
      final breakdown = PlatformReportBreakdown<SubscriptionStatus>.fromJson(
        const [
          {'key': 'trial', 'count': 2},
          {'key': 'paused', 'count': 3},
        ],
        keys: SubscriptionStatus.values,
        parse: SubscriptionStatus.parse,
      );
      expect(breakdown[SubscriptionStatus.trial], 2);
      expect(breakdown[SubscriptionStatus.active], 0);
      expect(breakdown.counts.keys, SubscriptionStatus.values);
      expect(breakdown.unsupported, 3);
      expect(breakdown.total, 5);
    });

    test('negative, duplicate or malformed buckets are refused', () {
      List<Map<String, Object>> bucket(Object count) => [
            {'key': 'trial', 'count': count},
          ];
      PlatformReportBreakdown<SubscriptionStatus> parse(Object raw) =>
          PlatformReportBreakdown.fromJson(
            raw,
            keys: SubscriptionStatus.values,
            parse: SubscriptionStatus.parse,
          );
      expect(() => parse(bucket(-1)), throwsFormatException);
      expect(() => parse(bucket('1')), throwsFormatException);
      expect(() => parse([...bucket(1), ...bucket(1)]), throwsFormatException);
      expect(() => parse({'trial': 1}), throwsFormatException);
    });
  });

  group('typed queries', () {
    test('value equality ignores set order; firstPage drops the cursor', () {
      final a = SubscriptionReportQuery(
        statuses: const {SubscriptionStatus.trial, SubscriptionStatus.grace},
        plan: const PlatformReportPlanFilter.plan('mtm_core'),
        cursor: 'c1',
      );
      final b = SubscriptionReportQuery(
        statuses: const {SubscriptionStatus.grace, SubscriptionStatus.trial},
        plan: const PlatformReportPlanFilter.plan('mtm_core'),
        cursor: 'c1',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.firstPage.cursor, isNull);
      expect(a.firstPage, b.firstPage);
      expect(a.isFiltered, isTrue);
      expect(SubscriptionReportQuery().isFiltered, isFalse);
    });

    test('deleted is never a reportable lifecycle filter', () {
      expect(
        () => SubscriptionReportQuery(
            lifecycles: const {SaasTenantStatus.deleted}),
        throwsArgumentError,
      );
      expect(
        () => UsageLimitsReportQuery(
            lifecycles: const {SaasTenantStatus.deleted}),
        throwsArgumentError,
      );
      expect(
        () => FeatureAvailabilityReportQuery(
          lifecycles: const {SaasTenantStatus.deleted},
        ),
        throwsArgumentError,
      );
      expect(kReportableLifecycleStatuses.contains(SaasTenantStatus.deleted),
          isFalse);
    });

    test('page limits, feature state and category are validated', () {
      expect(() => SubscriptionReportQuery(limit: 0), throwsArgumentError);
      expect(() => UsageLimitsReportQuery(limit: 101), throwsArgumentError);
      expect(
        () => FeatureAvailabilityReportQuery(
          state: TenantFeatureAvailability.enabled,
        ),
        throwsArgumentError,
      );
      final range = PlatformReportRange.defaultAt(DateTime.utc(2026, 9, 11));
      expect(
        () => PlatformActivityReportQuery(
          range: range,
          category: PlatformAuditCategory.unknown,
        ),
        throwsArgumentError,
      );
    });

    test('limitKey reorders the usage report but is not a filter', () {
      expect(
        UsageLimitsReportQuery(limitKey: PlanLimitKey.members).isFiltered,
        isFalse,
      );
      expect(
        UsageLimitsReportQuery(bands: const {UsageLimitBand.overLimit})
            .isFiltered,
        isTrue,
      );
    });

    test('query parameters are closed, typed and deterministic', () {
      final params = SubscriptionReportQuery(
        statuses: const {SubscriptionStatus.grace, SubscriptionStatus.trial},
        plan: const PlatformReportPlanFilter.noPlan(),
        lifecycles: const {SaasTenantStatus.suspended, SaasTenantStatus.active},
        dueBefore: DateTime.utc(2026, 10, 1),
      ).toQueryParameters();
      expect(params, {
        'status': 'trial,grace',
        'noPlan': 'true',
        'lifecycle': 'active,suspended',
        'dueBefore': '2026-10-01T00:00:00.000Z',
        'limit': '50',
      });
    });
  });

  group('stable ordering', () {
    SubscriptionReportRow row(String id, DateTime? date) =>
        SubscriptionReportRow(
          tenant: PlatformReportTenantRef(id: id, displayName: id),
          lifecycle: const PlatformReportValue.supported(
            SaasTenantStatus.active,
          ),
          status: const PlatformReportValue.supported(SubscriptionStatus.trial),
          plan: null,
          relevantDate: date,
        );

    test('subscriptions: date ascending, no date last, tenant id tie-break',
        () {
      final day = DateTime.utc(2026, 9, 20);
      final rows = [
        row('c', null),
        row('b', day),
        row('a', day),
        row('d', day.subtract(const Duration(days: 1))),
      ]..sort(compareSubscriptionRows);
      expect(rows.map((r) => r.tenant.id), ['d', 'a', 'b', 'c']);
    });

    UsageLimitsReportRow usage(String id, int members, int? limit) =>
        UsageLimitsReportRow(
          tenant: PlatformReportTenantRef(id: id, displayName: id),
          lifecycle: const PlatformReportValue.supported(
            SaasTenantStatus.active,
          ),
          plan: limit == null
              ? null
              : const PlatformReportPlanRef(id: 'p', name: 'P'),
          cells: {
            for (final key in PlanLimitKey.values)
              key: UsageLimitCell(
                usage: key == PlanLimitKey.members ? members : 0,
                limit: limit,
              ),
          },
        );

    test('usage: band severity, then ratio, then tenant id', () {
      final rows = [
        usage('none', 50, null),
        usage('within', 40, 100),
        usage('over', 120, 100),
        usage('at-b', 100, 100),
        usage('at-a', 100, 100),
        usage('within-high', 90, 100),
      ]..sort((a, b) => compareUsageRows(a, b, key: PlanLimitKey.members));
      expect(rows.map((r) => r.tenant.id),
          ['over', 'at-a', 'at-b', 'within-high', 'within', 'none']);
    });

    test('bands are factual; a zero limit is a real limit', () {
      expect(UsageLimitBand.classify(usage: 3, limit: null),
          UsageLimitBand.noLimit);
      expect(
          UsageLimitBand.classify(usage: 0, limit: 0), UsageLimitBand.atLimit);
      expect(UsageLimitBand.classify(usage: 1, limit: 0),
          UsageLimitBand.overLimit);
      expect(UsageLimitBand.classify(usage: 79, limit: 100),
          UsageLimitBand.withinLimit);
      expect(UsageLimitCell(usage: 1, limit: 0).ratio, double.infinity);
      expect(UsageLimitCell(usage: 0, limit: 0).ratio, 1);
      expect(UsageLimitCell(usage: 5).ratio, isNull);
      expect(() => UsageLimitCell(usage: 1, overridden: true),
          throwsArgumentError);
    });
  });

  group('parsing, fail-safe and minimization', () {
    test('a well-formed subscription report parses with its provenance', () {
      final report = SubscriptionReport.fromJson(
        subscriptionJson(),
        query: SubscriptionReportQuery(),
      );
      expect(report.meta.type, PlatformReportType.subscriptions);
      expect(report.meta.generatedAt, DateTime.utc(2026, 9, 11, 9));
      expect(report.meta.snapshotId, 'snap_1');
      expect(report.summary.byStatus[SubscriptionStatus.trial], 1);
      expect(report.rows.items.single.relevantDate, DateTime.utc(2026, 9, 20));
      expect(report.rows.hasMore, isFalse);
    });

    test('unknown row values render as unsupported, not as known values', () {
      final report = SubscriptionReport.fromJson(
        subscriptionJson(
          rows: [
            {
              'tenant': tenant,
              'lifecycle': 'archived',
              'subscriptionStatus': 'paused',
              'plan': null,
            },
          ],
          summary: {
            'tenantCount': 1,
            'byStatus': [
              {'key': 'paused', 'count': 1},
            ],
            'byLifecycle': [
              {'key': 'archived', 'count': 1},
            ],
            'byPlan': [
              {'plan': null, 'count': 1},
            ],
          },
        ),
        query: SubscriptionReportQuery(),
      );
      final row = report.rows.items.single;
      expect(row.lifecycle.isSupported, isFalse);
      expect(row.status.isSupported, isFalse);
      expect(report.summary.byStatus.unsupported, 1);
      expect(report.summary.byStatus[SubscriptionStatus.active], 0);
      expect(report.summary.byLifecycle.unsupported, 1);
    });

    test('deleted tenants are never rows or buckets', () {
      expect(
        () => SubscriptionReport.fromJson(
          subscriptionJson(rows: [
            {
              'tenant': tenant,
              'lifecycle': 'deleted',
              'subscriptionStatus': 'inactive',
              'plan': null,
            },
          ]),
          query: SubscriptionReportQuery(),
        ),
        throwsFormatException,
      );
      expect(
        () => SubscriptionReport.fromJson(
          subscriptionJson(summary: {
            'tenantCount': 1,
            'byStatus': [
              {'key': 'inactive', 'count': 1},
            ],
            'byLifecycle': [
              {'key': 'deleted', 'count': 1},
            ],
            'byPlan': [
              {'plan': null, 'count': 1},
            ],
          }),
          query: SubscriptionReportQuery(),
        ),
        throwsFormatException,
      );
    });

    test('a payload carrying Team Code, contact or reason data is refused', () {
      for (final leak in <Map<String, dynamic>>[
        {'teamCode': 'MTM-4K7P-QX92'},
        {'mainAdminEmail': 'a@b.org'},
        {'suspensionReason': 'x'},
        {'memberNames': <String>[]},
        {'sessionId': 's'},
      ]) {
        expect(
          () => SubscriptionReport.fromJson(
            subscriptionJson(rows: [
              {
                'tenant': tenant,
                'lifecycle': 'active',
                'subscriptionStatus': 'trial',
                'plan': null,
                ...leak,
              },
            ]),
            query: SubscriptionReportQuery(),
          ),
          throwsFormatException,
          reason: '$leak',
        );
      }
      expect(
        () => PlatformReportTenantRef.fromJson(
            const {...tenant, 'email': 'a@b.org'}),
        throwsFormatException,
      );
    });

    test('summary invariants and report type are enforced', () {
      expect(
        () => SubscriptionReport.fromJson(
          subscriptionJson(summary: {
            'tenantCount': 2,
            'byStatus': [
              {'key': 'trial', 'count': 1},
            ],
            'byLifecycle': [
              {'key': 'active', 'count': 2},
            ],
            'byPlan': [
              {'plan': null, 'count': 2},
            ],
          }),
          query: SubscriptionReportQuery(),
        ),
        throwsFormatException,
      );
      expect(
        () => SubscriptionReport.fromJson(
          subscriptionJson(type: 'usage_limits'),
          query: SubscriptionReportQuery(),
        ),
        throwsFormatException,
      );
      expect(
        () => SubscriptionReport.fromJson(
          subscriptionJson(type: 'revenue'),
          query: SubscriptionReportQuery(),
        ),
        throwsFormatException,
      );
    });

    Map<String, dynamic> usageJson(List<Map<String, dynamic>> cells,
            {Object? plan = const {'id': 'p', 'name': 'P'}}) =>
        {
          'type': 'usage_limits',
          'generatedAt': generatedAt,
          'snapshotId': 'snap_u',
          'summary': {
            'tenantCount': 1,
            'byKey': [
              for (final key in PlanLimitKey.values)
                {
                  'key': key.wire,
                  'bands': [
                    {'key': 'within_limit', 'count': 1},
                  ],
                },
              {
                'key': 'future_limit',
                'bands': [
                  {'key': 'within_limit', 'count': 1},
                ],
              },
            ],
          },
          'rows': {
            'items': [
              {
                'tenant': tenant,
                'lifecycle': 'active',
                'plan': plan,
                'cells': cells,
              },
            ],
          },
        };

    test('usage: unknown limit keys are flagged, limits require a plan', () {
      final cells = [
        for (final key in PlanLimitKey.values)
          {'key': key.wire, 'usage': 1, 'limit': 10, 'overridden': false},
        {'key': 'future_limit', 'usage': 1, 'limit': 1},
      ];
      final report = UsageLimitsReport.fromJson(
        usageJson(cells),
        query: UsageLimitsReportQuery(),
      );
      expect(report.hasUnsupportedLimitKeys, isTrue);
      expect(report.rows.items.single.cells.length, PlanLimitKey.values.length);
      expect(
        () => UsageLimitsReport.fromJson(
          usageJson(cells, plan: null),
          query: UsageLimitsReportQuery(),
        ),
        throwsFormatException,
      );
      expect(
        () => UsageLimitsReport.fromJson(
          usageJson(cells.skip(1).toList()),
          query: UsageLimitsReportQuery(),
        ),
        throwsFormatException,
      );
    });

    test('features: missing or unknown state is unsupported, never disabled',
        () {
      final row = FeatureAvailabilityRow.fromJson(const {
        'tenant': tenant,
        'lifecycle': 'active',
        'features': [
          {'key': 'inventory', 'state': 'enabled'},
          {'key': 'workshops', 'state': 'beta'},
          {'key': 'future_module', 'state': 'enabled'},
        ],
      });
      expect(
        row.states[TenantFeatureKey.inventory],
        const PlatformReportValue.supported(TenantFeatureAvailability.enabled),
      );
      expect(row.states[TenantFeatureKey.workshops]!.isSupported, isFalse);
      expect(row.states[TenantFeatureKey.announcements]!.isSupported, isFalse);
      expect(row.states.length, TenantFeatureKey.values.length);
    });

    Map<String, dynamic> activityJson(
      PlatformReportRange range, {
      List<Map<String, Object>> byAction = const [],
      String? evidenceFrom,
    }) =>
        {
          'type': 'platform_activity',
          'generatedAt': generatedAt,
          'snapshotId': 'snap_a',
          'range': {
            'from': range.from.toIso8601String(),
            'before': range.before.toIso8601String(),
          },
          'evidenceAvailableFrom': evidenceFrom,
          'byAction': byAction,
        };

    test('activity: unknown actions are counted apart; categories derive', () {
      final query = PlatformActivityReportQuery(
        range: PlatformReportRange(
          from: DateTime.utc(2026, 8, 1),
          before: DateTime.utc(2026, 9, 1),
        ),
      );
      final report = PlatformActivityReport.fromJson(
        activityJson(query.range, byAction: [
          {'key': 'tenant_registered', 'count': 2},
          {'key': 'break_glass_activated', 'count': 1},
          {'key': 'future_action', 'count': 4},
        ]),
        query: query,
      );
      expect(report.total, 7);
      expect(report.byAction.unsupported, 4);
      expect(report.byCategory[PlatformAuditCategory.tenantManagement], 2);
      expect(report.byCategory[PlatformAuditCategory.emergencyAccess], 1);
      expect(report.byCategory.unsupported, 4);
      expect(report.isCoveragePartial, isFalse);

      final drill = report.auditQueryFor(PlatformAuditAction.tenantRegistered);
      expect(drill.from, query.range.from);
      expect(drill.before, query.range.before);
      expect(drill.action, PlatformAuditAction.tenantRegistered);
      expect(() => report.auditQueryFor(PlatformAuditAction.unknown),
          throwsArgumentError);
    });

    test('activity: partial coverage, range echo and category are enforced',
        () {
      final query = PlatformActivityReportQuery(
        range: PlatformReportRange(
          from: DateTime.utc(2026, 8, 1),
          before: DateTime.utc(2026, 9, 1),
        ),
        category: PlatformAuditCategory.lifecycle,
      );
      final partial = PlatformActivityReport.fromJson(
        activityJson(query.range, evidenceFrom: '2026-08-15T00:00:00Z'),
        query: query,
      );
      expect(partial.isCoveragePartial, isTrue);
      expect(partial.isEmpty, isTrue);
      expect(partial.isFiltered, isTrue);

      final otherRange = PlatformReportRange(
        from: DateTime.utc(2026, 7, 1),
        before: DateTime.utc(2026, 9, 1),
      );
      expect(
        () => PlatformActivityReport.fromJson(
          activityJson(otherRange),
          query: query,
        ),
        throwsFormatException,
      );
      expect(
        () => PlatformActivityReport.fromJson(
          activityJson(query.range, byAction: [
            {'key': 'plan_changed', 'count': 1},
          ]),
          query: query,
        ),
        throwsFormatException,
      );
    });
  });

  group('selectors', () {
    PlatformActivityReport activity({int count = 0, bool filtered = false}) =>
        PlatformActivityReport(
          meta: PlatformReportMeta(
            type: PlatformReportType.platformActivity,
            generatedAt: DateTime.utc(2026, 9, 11),
            snapshotId: 's',
          ),
          query: PlatformActivityReportQuery(
            range: PlatformReportRange.defaultAt(DateTime.utc(2026, 9, 11)),
            category: filtered ? PlatformAuditCategory.lifecycle : null,
          ),
          byAction: PlatformReportBreakdown(
            keys: kReportableAuditActions,
            counts: {PlatformAuditAction.tenantSuspended: count},
          ),
        );

    test('freshness is derived from the result, never the device clock', () {
      expect(platformReportFreshness(Success(activity())),
          PlatformReportFreshness.fresh);
      expect(platformReportFreshness(Success(activity(), stale: true)),
          PlatformReportFreshness.stale);
      expect(platformReportFreshness(Offline(cached: activity())),
          PlatformReportFreshness.offlineCached);
      expect(platformReportFreshness(const Offline<PlatformActivityReport>()),
          isNull);
      expect(
          platformReportFreshness(
              const Failure<PlatformActivityReport>('x', code: 'server')),
          isNull);
    });

    test('view state distinguishes every designed state', () {
      expect(platformReportViewState(Success(activity(count: 1))),
          PlatformReportViewState.loaded);
      expect(platformReportViewState(Success(activity())),
          PlatformReportViewState.empty);
      expect(platformReportViewState(Success(activity(filtered: true))),
          PlatformReportViewState.filteredEmpty);
      expect(platformReportViewState(Offline(cached: activity(count: 1))),
          PlatformReportViewState.loaded);
      expect(platformReportViewState(const Offline<PlatformActivityReport>()),
          PlatformReportViewState.offlineNoData);
      expect(
          platformReportViewState(const Failure<PlatformActivityReport>('x',
              code: 'not_permitted')),
          PlatformReportViewState.notPermitted);
      expect(
          platformReportViewState(
              const Failure<PlatformActivityReport>('x', code: 'server')),
          PlatformReportViewState.failure);
    });
  });

  group('rows paging state', () {
    PlatformReportPage<String> page(List<String> items, [String? next]) =>
        PlatformReportPage(items: items, nextCursor: next);
    String key(String row) => row;

    test('appends in order, de-duplicates, stops at the last page', () {
      var state = PlatformReportRowsState.firstPage(
        snapshotId: 's1',
        page: page(['a', 'b'], 'c1'),
      );
      state = state.appendPage(
        cursor: 'c1',
        snapshotId: 's1',
        page: page(['b', 'c'], 'c2'),
        keyOf: key,
      );
      expect(state.items, ['a', 'b', 'c']);
      expect(state.canLoadMore, isTrue);
      state = state.appendPage(
        cursor: 'c2',
        snapshotId: 's1',
        page: page(['d']),
        keyOf: key,
      );
      expect(state.items, ['a', 'b', 'c', 'd']);
      expect(state.canLoadMore, isFalse);
      expect(state.mustReload, isFalse);
    });

    test('never mixes snapshots; a repeated cursor stops paging', () {
      final first = PlatformReportRowsState.firstPage(
        snapshotId: 's1',
        page: page(['a'], 'c1'),
      );
      final mixed = first.appendPage(
        cursor: 'c1',
        snapshotId: 's2',
        page: page(['z']),
        keyOf: key,
      );
      expect(mixed.items, ['a']);
      expect(mixed.mustReload, isTrue);
      expect(mixed.canLoadMore, isFalse);

      final looped = first.appendPage(
        cursor: 'c1',
        snapshotId: 's1',
        page: page(['b'], 'c1'),
        keyOf: key,
      );
      expect(looped.items, ['a', 'b']);
      expect(looped.mustReload, isTrue);
    });

    test('a failed next page keeps rows; an expired cursor requires reload',
        () {
      final first = PlatformReportRowsState.firstPage(
        snapshotId: 's1',
        page: page(['a'], 'c1'),
      );
      final failed = first.pageFailure(code: 'server');
      expect(failed.items, ['a']);
      expect(failed.pageFailed, isTrue);
      expect(failed.canLoadMore, isTrue);

      final expired = first.pageFailure(
        code: PlatformReportProblemCode.cursorExpired.wire,
      );
      expect(expired.items, ['a']);
      expect(expired.mustReload, isTrue);
      expect(expired.canLoadMore, isFalse);
    });
  });
}
