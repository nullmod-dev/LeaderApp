import 'dart:collection';
import 'dart:convert';

import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../../../core/text/search_key.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart'
    show TenantFeatureKey;
import '../domain/platform_audit_models.dart';
import '../domain/platform_report_datasets.dart';
import '../domain/platform_report_models.dart';
import '../domain/platform_reports_repository.dart';
import '../domain/saas_subscription_models.dart';
import '../domain/saas_tenant_models.dart';
import 'platform_audit_fixtures.dart';
import 'platform_subscription_fixtures.dart';
import 'platform_tenant_store.dart';

enum MockPlatformReportsMode {
  loaded,

  /// The platform has no tenants and Audit has no events.
  empty,

  /// A cached result served after a refresh failed (`Success(stale: true)`).
  stale,

  /// Offline with a previously read first page; paging is refused.
  offlineWithCache,
  offlineWithoutCache,
  failure,
  notPermitted,

  /// Page one loads; every next page fails safely.
  nextPageFailure,

  /// Page one loads; every cursor reports its snapshot as gone.
  cursorExpired,

  /// Page one includes one row with lifecycle/status/feature values this
  /// build does not support, counted in the unsupported buckets.
  unsupportedValues,
}

/// How old a stale / offline-cached mock result claims to be.
const Duration kMockReportCacheAge = Duration(hours: 3);

/// Deterministic Point 13A mock.
///
/// Reads the **same** canonical `PlatformTenantStore` as Points 5–9 and the
/// **same** `PlatformAuditFixtures` as Point 11, so report counts can never
/// disagree with tenant management or with the Audit drill-down. It writes
/// nothing, calls no other repository, builds no tenant-operational
/// repository, and reads time only from the injected clock.
///
/// Snapshot rows are frozen per first-page request, as a server would
/// materialize them, so every cursor pages one consistent snapshot.
class MockPlatformReportsRepository implements PlatformReportsRepository {
  MockPlatformReportsRepository({
    required this.store,
    required this.auditFixtures,
    required DateTime Function() clock,
    this.mode = MockPlatformReportsMode.loaded,
    this.latency = Duration.zero,
    this.auditRetention,
  }) : _clock = clock;

  final PlatformTenantStore store;
  final PlatformAuditFixtures auditFixtures;
  final DateTime Function() _clock;
  final MockPlatformReportsMode mode;
  final Duration latency;

  /// When set, Audit evidence older than `now - auditRetention` is treated as
  /// no longer retained, and activity reports state partial coverage.
  final Duration? auditRetention;

  static const int _retainedSnapshots = 8;
  final LinkedHashMap<String, _Snapshot> _snapshots = LinkedHashMap();
  int _sequence = 0;

  // -------------------------------------------------------------------------
  // Reports
  // -------------------------------------------------------------------------

  @override
  Future<Result<SubscriptionReport>> loadSubscriptions(
    SubscriptionReportQuery query,
  ) =>
      _serveRows(
        type: PlatformReportType.subscriptions,
        query: query,
        firstPage: query.firstPage,
        cursor: query.cursor,
        limit: query.limit,
        build: () {
          final rows = [
            for (final row in _subscriptionRows())
              if (_matchesSubscription(row, query)) row,
          ]..sort(compareSubscriptionRows);
          return (rows: rows, summary: _subscriptionSummary(rows));
        },
        assemble: (meta, summary, page) => SubscriptionReport(
          meta: meta,
          query: query,
          summary: summary as SubscriptionReportSummary,
          rows: page.cast(),
        ),
      );

  @override
  Future<Result<UsageLimitsReport>> loadUsageLimits(
    UsageLimitsReportQuery query,
  ) =>
      _serveRows(
        type: PlatformReportType.usageLimits,
        query: query,
        firstPage: query.firstPage,
        cursor: query.cursor,
        limit: query.limit,
        build: () {
          final rows = [
            for (final row in _usageRows())
              if (_matchesUsage(row, query)) row,
          ]..sort((a, b) => compareUsageRows(a, b, key: query.limitKey));
          return (rows: rows, summary: _usageSummary(rows));
        },
        assemble: (meta, summary, page) => UsageLimitsReport(
          meta: meta,
          query: query,
          summary: summary as UsageLimitsReportSummary,
          rows: page.cast(),
        ),
      );

  @override
  Future<Result<FeatureAvailabilityReport>> loadFeatureAvailability(
    FeatureAvailabilityReportQuery query,
  ) =>
      _serveRows(
        type: PlatformReportType.featureAvailability,
        query: query,
        firstPage: query.firstPage,
        cursor: query.cursor,
        limit: query.limit,
        build: () {
          final rows = [
            for (final row in _featureRows())
              if (_matchesFeature(row, query)) row,
          ]..sort(_compareFeatureRows);
          return (rows: rows, summary: _featureSummary(rows));
        },
        assemble: (meta, summary, page) => FeatureAvailabilityReport(
          meta: meta,
          query: query,
          summary: summary as FeatureAvailabilitySummary,
          rows: page.cast(),
        ),
      );

  @override
  Future<Result<PlatformActivityReport>> loadPlatformActivity(
    PlatformActivityReportQuery query,
  ) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final refused = _refusal<PlatformActivityReport>();
    if (refused != null) return refused;

    final generatedAt = _generatedAt();
    final retainedFrom = auditRetention == null
        ? null
        : _clock().toUtc().subtract(auditRetention!);
    final counts = <PlatformAuditAction, int>{};
    var unsupported = 0;
    if (mode != MockPlatformReportsMode.empty) {
      for (final event in auditFixtures.events) {
        if (!query.range.contains(event.occurredAt)) continue;
        if (retainedFrom != null && event.occurredAt.isBefore(retainedFrom)) {
          continue;
        }
        if (query.category != null && event.category != query.category) {
          continue;
        }
        if (event.action == PlatformAuditAction.unknown) {
          unsupported++;
        } else {
          counts[event.action] = (counts[event.action] ?? 0) + 1;
        }
      }
    }
    final report = PlatformActivityReport(
      meta: PlatformReportMeta(
        type: PlatformReportType.platformActivity,
        generatedAt: generatedAt,
        snapshotId: 'rpt_activity_${++_sequence}',
      ),
      query: query,
      byAction: PlatformReportBreakdown(
        keys: kReportableAuditActions,
        counts: counts,
        unsupported: unsupported,
      ),
      evidenceAvailableFrom:
          retainedFrom != null && retainedFrom.isAfter(query.range.from)
              ? retainedFrom
              : null,
    );
    return _deliver(report);
  }

  // -------------------------------------------------------------------------
  // Shared serving, snapshots and cursors
  // -------------------------------------------------------------------------

  Future<Result<R>> _serveRows<R>({
    required PlatformReportType type,
    required Object query,
    required Object firstPage,
    required String? cursor,
    required int limit,
    required ({List<Object> rows, Object summary}) Function() build,
    required R Function(
      PlatformReportMeta meta,
      Object summary,
      PlatformReportPage<Object> page,
    ) assemble,
  }) async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final refused = _refusal<R>();
    if (refused != null) return refused;

    _Snapshot snapshot;
    var offset = 0;
    if (cursor == null) {
      final built = build();
      snapshot = _Snapshot(
        id: 'rpt_${type.wire}_${++_sequence}',
        type: type,
        query: firstPage,
        generatedAt: _generatedAt(),
        rows: List.unmodifiable(built.rows),
        summary: built.summary,
      );
      _snapshots[snapshot.id] = snapshot;
      while (_snapshots.length > _retainedSnapshots) {
        _snapshots.remove(_snapshots.keys.first);
      }
    } else {
      switch (mode) {
        case MockPlatformReportsMode.offlineWithCache:
          return const Offline();
        case MockPlatformReportsMode.nextPageFailure:
          return _serverFailure();
        case MockPlatformReportsMode.cursorExpired:
          return _cursorExpired();
        default:
          break;
      }
      final anchor = _decodeCursor(cursor);
      if (anchor == null) return _invalidCursor();
      final found = _snapshots[anchor.snapshotId];
      if (found == null) return _cursorExpired();
      if (found.type != type ||
          found.query != firstPage ||
          anchor.offset < 0 ||
          anchor.offset > found.rows.length) {
        return _invalidCursor();
      }
      snapshot = found;
      offset = anchor.offset;
    }

    final end = (offset + limit).clamp(0, snapshot.rows.length);
    final page = PlatformReportPage<Object>(
      items: snapshot.rows.sublist(offset, end),
      nextCursor:
          end < snapshot.rows.length ? _encodeCursor(snapshot.id, end) : null,
    );
    final report = assemble(
      PlatformReportMeta(
        type: type,
        generatedAt: snapshot.generatedAt,
        snapshotId: snapshot.id,
      ),
      snapshot.summary,
      page,
    );
    return cursor == null ? _deliver(report) : Success(report);
  }

  Result<R>? _refusal<R>() {
    switch (mode) {
      case MockPlatformReportsMode.failure:
        return _serverFailure<R>();
      case MockPlatformReportsMode.notPermitted:
        return Failure<R>(
          'لا تملك صلاحية عرض تقارير المنصة.',
          code: ProblemCode.notPermitted.wire,
        );
      case MockPlatformReportsMode.offlineWithoutCache:
        return Offline<R>();
      default:
        return null;
    }
  }

  Result<R> _deliver<R>(R report) => switch (mode) {
        MockPlatformReportsMode.stale => Success(report, stale: true),
        MockPlatformReportsMode.offlineWithCache => Offline(cached: report),
        _ => Success(report),
      };

  DateTime _generatedAt() {
    final now = _clock().toUtc();
    return switch (mode) {
      MockPlatformReportsMode.stale ||
      MockPlatformReportsMode.offlineWithCache =>
        now.subtract(kMockReportCacheAge),
      _ => now,
    };
  }

  static String _encodeCursor(String snapshotId, int offset) => base64Url
      .encode(utf8.encode(jsonEncode({'v': 1, 's': snapshotId, 'o': offset})))
      .replaceAll('=', '');

  static ({String snapshotId, int offset})? _decodeCursor(String cursor) {
    try {
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(cursor)) return null;
      final padded = cursor.padRight((cursor.length + 3) ~/ 4 * 4, '=');
      final decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
      if (decoded is! Map ||
          decoded['v'] != 1 ||
          decoded['s'] is! String ||
          decoded['o'] is! int) {
        return null;
      }
      return (snapshotId: decoded['s'] as String, offset: decoded['o'] as int);
    } on FormatException {
      return null;
    }
  }

  static Failure<R> _serverFailure<R>() => Failure(
        'تعذّر تحميل التقرير.',
        code: ProblemCode.server.wire,
      );

  static Failure<R> _invalidCursor<R>() => Failure(
        'مؤشر صفحة التقرير غير صالح.',
        code: ProblemCode.validation.wire,
      );

  static Failure<R> _cursorExpired<R>() => Failure(
        'تغيّرت بيانات التقرير. أعد تحميله من البداية.',
        code: PlatformReportProblemCode.cursorExpired.wire,
      );

  // -------------------------------------------------------------------------
  // Canonical projections (control-plane fields only)
  // -------------------------------------------------------------------------

  List<SaasTenant> get _tenants => mode == MockPlatformReportsMode.empty
      ? const []
      : [
          for (final tenant in store.tenants)
            if (tenant.tenantStatus != SaasTenantStatus.deleted) tenant,
        ];

  bool get _withUnsupported =>
      mode == MockPlatformReportsMode.unsupportedValues;

  static const _futureTenant = PlatformReportTenantRef(
    id: 'saas_future_state',
    displayName: 'فريق بحالة غير مدعومة',
  );

  static PlatformReportTenantRef _ref(SaasTenant tenant) =>
      PlatformReportTenantRef(id: tenant.id, displayName: tenant.displayName);

  static PlatformReportPlanRef? _plan(SaasTenant tenant) {
    final id = tenant.subscription.plan.planId;
    if (id == null) return null;
    return PlatformReportPlanRef(
      id: id,
      name: canonicalPlanById(id)?.name ?? id,
    );
  }

  List<SubscriptionReportRow> _subscriptionRows() => [
        for (final tenant in _tenants)
          SubscriptionReportRow(
            tenant: _ref(tenant),
            lifecycle: PlatformReportValue.supported(tenant.tenantStatus),
            status: PlatformReportValue.supported(tenant.subscription.status),
            plan: _plan(tenant),
            relevantDate: tenant.subscription.relevantDate,
          ),
        if (_withUnsupported)
          SubscriptionReportRow(
            tenant: _futureTenant,
            lifecycle: const PlatformReportValue.unsupported(),
            status: const PlatformReportValue.unsupported(),
            plan: null,
          ),
      ];

  /// The same aggregates the Point 7 Limits screen shows. `admins` is the
  /// Point 7 mock placeholder (no platform admin-count aggregate exists yet —
  /// a documented backend gap).
  static Map<PlanLimitKey, int> _usageOf(SaasTenant tenant) => {
        PlanLimitKey.detachmentGroups: tenant.counts.detachmentGroups,
        PlanLimitKey.detachments: tenant.counts.detachments,
        PlanLimitKey.admins: 1,
        PlanLimitKey.members: tenant.counts.members,
        PlanLimitKey.workshops: tenant.counts.workshops,
        PlanLimitKey.storageBytes: tenant.usage.storageUsedBytes,
      };

  List<UsageLimitsReportRow> _usageRows() => [
        for (final tenant in _tenants) _usageRow(tenant),
      ];

  static UsageLimitsReportRow _usageRow(SaasTenant tenant) {
    final plan = canonicalPlanById(tenant.subscription.plan.planId);
    final usage = _usageOf(tenant);
    return UsageLimitsReportRow(
      tenant: _ref(tenant),
      lifecycle: PlatformReportValue.supported(tenant.tenantStatus),
      plan: plan == null
          ? null
          : PlatformReportPlanRef(id: plan.id, name: plan.name),
      cells: {
        for (final key in PlanLimitKey.values)
          key: UsageLimitCell(
            usage: usage[key]!,
            limit: plan == null
                ? null
                : tenant.subscription.effectiveLimit(key, plan),
            overridden: plan != null && tenant.subscription.hasOverride(key),
          ),
      },
    );
  }

  List<FeatureAvailabilityRow> _featureRows() => [
        for (final tenant in _tenants)
          FeatureAvailabilityRow(
            tenant: _ref(tenant),
            lifecycle: PlatformReportValue.supported(tenant.tenantStatus),
            states: {
              for (final key in TenantFeatureKey.values)
                if (store.featuresOf(tenant.id)?.stateOf(key) case final state?)
                  key: PlatformReportValue.supported(
                    state.enabled
                        ? TenantFeatureAvailability.enabled
                        : TenantFeatureAvailability.disabled,
                  ),
            },
          ),
        if (_withUnsupported)
          FeatureAvailabilityRow(
            tenant: _futureTenant,
            lifecycle: const PlatformReportValue.unsupported(),
            states: const {},
          ),
      ];

  static int _compareFeatureRows(
    FeatureAvailabilityRow a,
    FeatureAvailabilityRow b,
  ) {
    final byName = searchKey(a.tenant.displayName)
        .compareTo(searchKey(b.tenant.displayName));
    return byName != 0 ? byName : a.tenant.id.compareTo(b.tenant.id);
  }

  // -------------------------------------------------------------------------
  // Filters — applied before summaries and paging, as a server must
  // -------------------------------------------------------------------------

  static bool _lifecycleMatches(
    PlatformReportValue<SaasTenantStatus> value,
    Set<SaasTenantStatus> filter,
  ) =>
      filter.isEmpty || filter.contains(value.valueOrNull);

  static bool _matchesSubscription(
    SubscriptionReportRow row,
    SubscriptionReportQuery q,
  ) {
    if (!_lifecycleMatches(row.lifecycle, q.lifecycles)) return false;
    if (q.statuses.isNotEmpty && !q.statuses.contains(row.status.valueOrNull)) {
      return false;
    }
    if (q.plan != null && !q.plan!.matches(row.plan)) return false;
    final due = q.dueBefore;
    if (due != null) {
      final date = row.relevantDate;
      if (date == null || !date.isBefore(due)) return false;
    }
    return true;
  }

  static bool _matchesUsage(
          UsageLimitsReportRow row, UsageLimitsReportQuery q) =>
      _lifecycleMatches(row.lifecycle, q.lifecycles) &&
      (q.plan == null || q.plan!.matches(row.plan)) &&
      (q.bands.isEmpty || q.bands.contains(row.bandFor(q.limitKey)));

  static bool _matchesFeature(
    FeatureAvailabilityRow row,
    FeatureAvailabilityReportQuery q,
  ) {
    if (!_lifecycleMatches(row.lifecycle, q.lifecycles)) return false;
    final key = q.featureKey, state = q.state;
    if (key != null && state != null) {
      return row.states[key]!.valueOrNull == state;
    }
    return true;
  }

  // -------------------------------------------------------------------------
  // Summaries — computed over the whole filtered set, never over a page
  // -------------------------------------------------------------------------

  static PlatformReportBreakdown<K> _breakdown<K extends Object>(
    List<K> keys,
    Iterable<PlatformReportValue<K>> values,
  ) {
    final counts = <K, int>{};
    var unsupported = 0;
    for (final value in values) {
      final known = value.valueOrNull;
      if (known == null || !keys.contains(known)) {
        unsupported++;
      } else {
        counts[known] = (counts[known] ?? 0) + 1;
      }
    }
    return PlatformReportBreakdown(
      keys: keys,
      counts: counts,
      unsupported: unsupported,
    );
  }

  static SubscriptionReportSummary _subscriptionSummary(
    List<SubscriptionReportRow> rows,
  ) {
    final plans = <String?, ({PlatformReportPlanRef? plan, int count})>{};
    for (final row in rows) {
      final id = row.plan?.id;
      final current = plans[id];
      plans[id] = (plan: row.plan, count: (current?.count ?? 0) + 1);
    }
    final buckets = [
      for (final entry in plans.values)
        PlatformReportPlanBucket(plan: entry.plan, count: entry.count),
    ]..sort((a, b) {
        if (a.plan == null) return 1;
        if (b.plan == null) return -1;
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.plan!.id.compareTo(b.plan!.id);
      });
    return SubscriptionReportSummary(
      tenantCount: rows.length,
      byStatus: _breakdown(
        SubscriptionStatus.values,
        rows.map((r) => r.status),
      ),
      byLifecycle: _breakdown(
        kReportableLifecycleStatuses,
        rows.map((r) => r.lifecycle),
      ),
      byPlan: buckets,
    );
  }

  static UsageLimitsReportSummary _usageSummary(
    List<UsageLimitsReportRow> rows,
  ) =>
      UsageLimitsReportSummary(
        tenantCount: rows.length,
        byKey: {
          for (final key in PlanLimitKey.values)
            key: _breakdown(
              UsageLimitBand.values,
              rows.map(
                  (r) => PlatformReportValue.supported(r.cells[key]!.band)),
            ),
        },
      );

  static FeatureAvailabilitySummary _featureSummary(
    List<FeatureAvailabilityRow> rows,
  ) =>
      FeatureAvailabilitySummary(
        tenantCount: rows.length,
        byFeature: {
          for (final key in TenantFeatureKey.values)
            key: _breakdown(
              TenantFeatureAvailability.values,
              rows.map((r) => r.states[key]!),
            ),
        },
      );
}

class _Snapshot {
  _Snapshot({
    required this.id,
    required this.type,
    required this.query,
    required this.generatedAt,
    required this.rows,
    required this.summary,
  });

  final String id;
  final PlatformReportType type;

  /// The first-page query the snapshot answers; a cursor for any other query
  /// is refused.
  final Object query;
  final DateTime generatedAt;
  final List<Object> rows;
  final Object summary;
}
