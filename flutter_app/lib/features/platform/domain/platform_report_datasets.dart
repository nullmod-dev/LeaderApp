/// Point 13A — the four reports of the closed Platform Reports catalogue.
///
/// Each report has its **own** typed query, summary and row model; there is
/// no universal filter object and no arbitrary map. See
/// `platform_report_models.dart` for the shared contract and `API_CONTRACT.md`
/// → "Platform Reports — Point 13A" for the wire shapes.
library;

import 'package:flutter/foundation.dart';

import '../../../core/access/saas_tenant_status.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart'
    show TenantFeatureKey;
import 'platform_audit_models.dart';
import 'platform_report_models.dart';
import 'saas_subscription_models.dart' show PlanLimitKey, SubscriptionStatus;

// ---------------------------------------------------------------------------
// Shared tenant-row dimensions
// ---------------------------------------------------------------------------

/// Lifecycle states a current-snapshot report may contain.
///
/// Deleted tenants are **never** report rows or buckets: a Point 9 tombstone
/// has no subscription, plan, usage or feature configuration left, and a
/// report must not reconstruct one. Deletions appear only as Audit-derived
/// counts in [PlatformActivityReport].
const List<SaasTenantStatus> kReportableLifecycleStatuses = [
  SaasTenantStatus.active,
  SaasTenantStatus.suspended,
  SaasTenantStatus.deletionPending,
];

Set<SaasTenantStatus> _checkedLifecycles(Set<SaasTenantStatus> value) {
  if (value.contains(SaasTenantStatus.deleted)) {
    throw ArgumentError('deleted tenants are not reportable');
  }
  return Set.unmodifiable(value);
}

/// Row-level keys a report payload must never carry. A payload containing one
/// is a server contract violation and is refused whole, never partly shown.
bool isForbiddenReportField(String name) {
  if (PlatformAuditSafetyPolicy.isForbiddenFieldName(name)) return true;
  final normalized = name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  const extra = [
    'email',
    'phone',
    'mainadmin',
    'reason',
    'ipaddress',
    'device',
    'medical',
    'member',
    'volunteer',
    'attendance',
  ];
  return extra.any(normalized.contains);
}

void _refuseForbiddenFields(Map<String, dynamic> json) {
  for (final key in json.keys) {
    if (isForbiddenReportField(key)) {
      throw FormatException('forbidden report field', key);
    }
  }
}

/// The only tenant identity a report row carries: the control-plane id and
/// display name. No Team Code, Main Admin contact, reason or tenant data.
@immutable
class PlatformReportTenantRef {
  const PlatformReportTenantRef({required this.id, required this.displayName})
      : assert(id != ''),
        assert(displayName != '');

  final String id;
  final String displayName;

  factory PlatformReportTenantRef.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('tenant reference is required');
    }
    _refuseForbiddenFields(raw);
    final id = raw['id'];
    final name = raw['displayName'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      throw const FormatException('malformed tenant reference');
    }
    return PlatformReportTenantRef(id: id, displayName: name);
  }
}

PlatformReportValue<SaasTenantStatus> _rowLifecycle(Object? raw) {
  final value = PlatformReportValue<SaasTenantStatus>.parse(
    raw,
    SaasTenantStatus.tryParse,
  );
  if (value.valueOrNull == SaasTenantStatus.deleted) {
    throw const FormatException('deleted tenants are never report rows');
  }
  return value;
}

PlatformReportBreakdown<SaasTenantStatus> _lifecycleBreakdown(Object? raw) {
  if (raw is List &&
      raw.any((item) =>
          item is Map && item['key'] == SaasTenantStatus.deleted.wire)) {
    throw const FormatException('deleted tenants are never report buckets');
  }
  return PlatformReportBreakdown.fromJson(
    raw,
    keys: kReportableLifecycleStatuses,
    parse: SaasTenantStatus.tryParse,
  );
}

/// A plan as the report names it. The server supplies the display name so the
/// client needs no plan catalogue read. **No price exists** — Point 7 plans
/// carry limits only.
@immutable
class PlatformReportPlanRef {
  const PlatformReportPlanRef({required this.id, required this.name})
      : assert(id != ''),
        assert(name != '');

  final String id;
  final String name;

  /// `null` means the tenant explicitly has no plan.
  static PlatformReportPlanRef? fromJson(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map ||
        raw['id'] is! String ||
        (raw['id'] as String).isEmpty ||
        raw['name'] is! String ||
        (raw['name'] as String).isEmpty) {
      throw const FormatException('malformed plan reference');
    }
    return PlatformReportPlanRef(
      id: raw['id'] as String,
      name: raw['name'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlatformReportPlanRef && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// Filter by plan assignment; `null` on a query means every plan.
@immutable
sealed class PlatformReportPlanFilter {
  const PlatformReportPlanFilter();

  const factory PlatformReportPlanFilter.noPlan() = PlatformReportNoPlanFilter;
  const factory PlatformReportPlanFilter.plan(String planId) =
      PlatformReportPlanIdFilter;

  bool matches(PlatformReportPlanRef? plan);
  Map<String, String> toQueryParameters();
}

final class PlatformReportNoPlanFilter extends PlatformReportPlanFilter {
  const PlatformReportNoPlanFilter();

  @override
  bool matches(PlatformReportPlanRef? plan) => plan == null;

  @override
  Map<String, String> toQueryParameters() => const {'noPlan': 'true'};

  @override
  bool operator ==(Object other) => other is PlatformReportNoPlanFilter;

  @override
  int get hashCode => (PlatformReportNoPlanFilter).hashCode;
}

final class PlatformReportPlanIdFilter extends PlatformReportPlanFilter {
  const PlatformReportPlanIdFilter(this.planId) : assert(planId != '');
  final String planId;

  @override
  bool matches(PlatformReportPlanRef? plan) => plan?.id == planId;

  @override
  Map<String, String> toQueryParameters() => {'planId': planId};

  @override
  bool operator ==(Object other) =>
      other is PlatformReportPlanIdFilter && other.planId == planId;

  @override
  int get hashCode => planId.hashCode;
}

String _wireList(Iterable<Enum> values, String Function(Enum) wire) {
  final sorted = values.toList()..sort((a, b) => a.index.compareTo(b.index));
  return sorted.map(wire).join(',');
}

Map<String, String> _pageParameters(String? cursor, int limit) => {
      if (cursor != null) 'cursor': cursor,
      'limit': '$limit',
    };

PlatformReportPage<R> _rowsFromJson<R>(
  Map<String, dynamic> json,
  R Function(Map<String, dynamic>) parse,
) {
  final rows = json['rows'];
  if (rows is! Map<String, dynamic> || rows['items'] is! List) {
    throw const FormatException('rows page is required');
  }
  final next = rows['nextCursor'];
  if (next != null && (next is! String || next.isEmpty)) {
    throw const FormatException('malformed cursor');
  }
  return PlatformReportPage(
    items: [
      for (final item in rows['items'] as List)
        if (item is Map<String, dynamic>)
          parse(item)
        else
          throw const FormatException('malformed row'),
    ],
    nextCursor: next as String?,
  );
}

T _asFormat<T>(T Function() build) {
  try {
    return build();
  } on ArgumentError catch (error) {
    throw FormatException('report invariant violated: ${error.message}');
  }
}

int _requireCount(Object? raw, String name) {
  if (raw is! int || raw < 0) throw FormatException('invalid $name', raw);
  return raw;
}

// ---------------------------------------------------------------------------
// 1. Subscriptions — current snapshot
// ---------------------------------------------------------------------------

@immutable
class SubscriptionReportQuery {
  SubscriptionReportQuery({
    Set<SubscriptionStatus> statuses = const {},
    this.plan,
    Set<SaasTenantStatus> lifecycles = const {},
    DateTime? dueBefore,
    this.cursor,
    this.limit = kPlatformReportDefaultPageSize,
  })  : statuses = Set.unmodifiable(statuses),
        lifecycles = _checkedLifecycles(lifecycles),
        dueBefore = dueBefore?.toUtc() {
    checkPlatformReportPageLimit(limit);
  }

  /// Empty means every commercial status.
  final Set<SubscriptionStatus> statuses;
  final PlatformReportPlanFilter? plan;

  /// Empty means every reportable (non-deleted) lifecycle state.
  final Set<SaasTenantStatus> lifecycles;

  /// Only rows whose server-supplied relevant date (trial end, renewal or
  /// grace end) is strictly before this UTC instant — overdue included.
  /// Rows with no relevant date (`inactive`) never match.
  final DateTime? dueBefore;
  final String? cursor;
  final int limit;

  bool get isFiltered =>
      statuses.isNotEmpty ||
      plan != null ||
      lifecycles.isNotEmpty ||
      dueBefore != null;

  SubscriptionReportQuery withCursor(String? cursor) => SubscriptionReportQuery(
        statuses: statuses,
        plan: plan,
        lifecycles: lifecycles,
        dueBefore: dueBefore,
        cursor: cursor,
        limit: limit,
      );

  SubscriptionReportQuery get firstPage => withCursor(null);

  Map<String, String> toQueryParameters() => {
        if (statuses.isNotEmpty)
          'status': _wireList(statuses, (s) => (s as SubscriptionStatus).wire),
        ...?plan?.toQueryParameters(),
        if (lifecycles.isNotEmpty)
          'lifecycle':
              _wireList(lifecycles, (s) => (s as SaasTenantStatus).wire),
        if (dueBefore != null) 'dueBefore': dueBefore!.toIso8601String(),
        ..._pageParameters(cursor, limit),
      };

  @override
  bool operator ==(Object other) =>
      other is SubscriptionReportQuery &&
      setEquals(other.statuses, statuses) &&
      other.plan == plan &&
      setEquals(other.lifecycles, lifecycles) &&
      other.dueBefore == dueBefore &&
      other.cursor == cursor &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(statuses),
        plan,
        Object.hashAllUnordered(lifecycles),
        dueBefore,
        cursor,
        limit,
      );
}

@immutable
class SubscriptionReportRow {
  SubscriptionReportRow({
    required this.tenant,
    required this.lifecycle,
    required this.status,
    required this.plan,
    DateTime? relevantDate,
  }) : relevantDate = relevantDate?.toUtc();

  final PlatformReportTenantRef tenant;
  final PlatformReportValue<SaasTenantStatus> lifecycle;
  final PlatformReportValue<SubscriptionStatus> status;

  /// `null` = explicitly no plan.
  final PlatformReportPlanRef? plan;

  /// Trial end / renewal / grace end **as the server states it**. The client
  /// never computes one (the Point 7 14-day grace is a provisional mock rule).
  final DateTime? relevantDate;

  factory SubscriptionReportRow.fromJson(Map<String, dynamic> json) {
    _refuseForbiddenFields(json);
    return SubscriptionReportRow(
      tenant: PlatformReportTenantRef.fromJson(json['tenant']),
      lifecycle: _rowLifecycle(json['lifecycle']),
      status: PlatformReportValue.parse(
        json['subscriptionStatus'],
        SubscriptionStatus.parse,
      ),
      plan: PlatformReportPlanRef.fromJson(json['plan']),
      relevantDate: parseOptionalReportInstant(json['relevantDate']),
    );
  }
}

/// Canonical row order: relevant date ascending (no date last), then tenant
/// id ascending as the stable tie-break.
int compareSubscriptionRows(SubscriptionReportRow a, SubscriptionReportRow b) {
  final left = a.relevantDate, right = b.relevantDate;
  if (left != right) {
    if (left == null) return 1;
    if (right == null) return -1;
    final byDate = left.compareTo(right);
    if (byDate != 0) return byDate;
  }
  return a.tenant.id.compareTo(b.tenant.id);
}

@immutable
class PlatformReportPlanBucket {
  const PlatformReportPlanBucket({required this.plan, required this.count})
      : assert(count >= 0);

  /// `null` = the no-plan bucket.
  final PlatformReportPlanRef? plan;
  final int count;
}

@immutable
class SubscriptionReportSummary {
  SubscriptionReportSummary({
    required this.tenantCount,
    required this.byStatus,
    required this.byLifecycle,
    required List<PlatformReportPlanBucket> byPlan,
  }) : byPlan = List.unmodifiable(byPlan) {
    if (tenantCount < 0) throw ArgumentError.value(tenantCount, 'tenantCount');
    if (byStatus.total != tenantCount) {
      throw ArgumentError('status buckets must sum to tenantCount');
    }
    if (byLifecycle.total != tenantCount) {
      throw ArgumentError('lifecycle buckets must sum to tenantCount');
    }
    if (byPlan.fold<int>(0, (sum, b) => sum + b.count) != tenantCount) {
      throw ArgumentError('plan buckets must sum to tenantCount');
    }
    if (byPlan.where((b) => b.plan == null).length > 1 ||
        byPlan.map((b) => b.plan?.id).toSet().length != byPlan.length) {
      throw ArgumentError('plan buckets must be unique');
    }
  }

  final int tenantCount;
  final PlatformReportBreakdown<SubscriptionStatus> byStatus;
  final PlatformReportBreakdown<SaasTenantStatus> byLifecycle;

  /// Count descending, then plan id ascending, the no-plan bucket last.
  final List<PlatformReportPlanBucket> byPlan;

  factory SubscriptionReportSummary.fromJson(Map<String, dynamic> json) {
    final rawPlans = json['byPlan'];
    if (rawPlans is! List) throw const FormatException('byPlan is required');
    return _asFormat(() => SubscriptionReportSummary(
          tenantCount: _requireCount(json['tenantCount'], 'tenantCount'),
          byStatus: PlatformReportBreakdown.fromJson(
            json['byStatus'],
            keys: SubscriptionStatus.values,
            parse: SubscriptionStatus.parse,
          ),
          byLifecycle: _lifecycleBreakdown(json['byLifecycle']),
          byPlan: [
            for (final item in rawPlans)
              if (item is Map)
                PlatformReportPlanBucket(
                  plan: PlatformReportPlanRef.fromJson(item['plan']),
                  count: _requireCount(item['count'], 'plan count'),
                )
              else
                throw const FormatException('malformed plan bucket'),
          ],
        ));
  }
}

@immutable
class SubscriptionReport implements PlatformReportResult {
  const SubscriptionReport({
    required this.meta,
    required this.query,
    required this.summary,
    required this.rows,
  });

  @override
  final PlatformReportMeta meta;
  final SubscriptionReportQuery query;
  final SubscriptionReportSummary summary;
  final PlatformReportPage<SubscriptionReportRow> rows;

  @override
  bool get isFiltered => query.isFiltered;

  @override
  bool get isEmpty => summary.tenantCount == 0;

  factory SubscriptionReport.fromJson(
    Map<String, dynamic> json, {
    required SubscriptionReportQuery query,
  }) =>
      SubscriptionReport(
        meta: PlatformReportMeta.fromJson(
          json,
          expected: PlatformReportType.subscriptions,
        ),
        query: query,
        summary: SubscriptionReportSummary.fromJson(
          json['summary'] is Map<String, dynamic>
              ? json['summary'] as Map<String, dynamic>
              : throw const FormatException('summary is required'),
        ),
        rows: _rowsFromJson(json, SubscriptionReportRow.fromJson),
      );
}

// ---------------------------------------------------------------------------
// 2. Usage & limits — current snapshot
// ---------------------------------------------------------------------------

/// A factual usage position against the **effective** plan limit
/// (`override ?? plan default`). No "near limit" threshold exists: none has
/// been approved, so the report sorts by utilization instead of inventing one.
enum UsageLimitBand {
  withinLimit('within_limit'),

  /// Usage equals the limit: further creates are blocked.
  atLimit('at_limit'),

  /// Usage exceeds the limit (e.g. after a lower override). Nothing was
  /// deleted; creates are blocked until usage falls below the limit.
  overLimit('over_limit'),

  /// The tenant has no plan, so no limit applies.
  noLimit('no_limit');

  const UsageLimitBand(this.wire);
  final String wire;

  static UsageLimitBand? parse(String wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return null;
  }

  static UsageLimitBand classify({required int usage, required int? limit}) {
    if (limit == null) return noLimit;
    if (usage > limit) return overLimit;
    if (usage == limit) return atLimit;
    return withinLimit;
  }

  /// Ordering weight: over > at > within > no limit.
  int get severity => switch (this) {
        overLimit => 3,
        atLimit => 2,
        withinLimit => 1,
        noLimit => 0,
      };
}

@immutable
class UsageLimitCell {
  UsageLimitCell({required this.usage, this.limit, this.overridden = false}) {
    if (usage < 0) throw ArgumentError.value(usage, 'usage');
    if (limit != null && limit! < 0) throw ArgumentError.value(limit, 'limit');
    if (overridden && limit == null) {
      throw ArgumentError('an override needs a limit');
    }
  }

  /// A platform aggregate supplied by the server. Storage is bytes.
  final int usage;

  /// Effective limit; `null` when the tenant has no plan.
  final int? limit;

  /// Whether [limit] is a tenant override rather than the plan default.
  final bool overridden;

  UsageLimitBand get band =>
      UsageLimitBand.classify(usage: usage, limit: limit);

  /// `usage / limit`; `null` without a limit. A zero limit is a real "no
  /// additional create" limit: ratio 1 at zero usage, infinite above it.
  double? get ratio {
    final l = limit;
    if (l == null) return null;
    if (l == 0) return usage == 0 ? 1 : double.infinity;
    return usage / l;
  }
}

@immutable
class UsageLimitsReportRow {
  UsageLimitsReportRow({
    required this.tenant,
    required this.lifecycle,
    required this.plan,
    required Map<PlanLimitKey, UsageLimitCell> cells,
  }) : cells = Map.unmodifiable(cells) {
    for (final key in PlanLimitKey.values) {
      final cell = this.cells[key];
      if (cell == null) throw ArgumentError('missing usage cell ${key.wire}');
      if ((plan == null) != (cell.limit == null)) {
        throw ArgumentError('limits exist exactly when a plan is assigned');
      }
    }
  }

  final PlatformReportTenantRef tenant;
  final PlatformReportValue<SaasTenantStatus> lifecycle;
  final PlatformReportPlanRef? plan;
  final Map<PlanLimitKey, UsageLimitCell> cells;

  /// The band for [key], or the most severe band across keys when `null`.
  UsageLimitBand bandFor(PlanLimitKey? key) => key != null
      ? cells[key]!.band
      : cells.values
          .map((cell) => cell.band)
          .reduce((a, b) => a.severity >= b.severity ? a : b);

  /// The ratio for [key], or the highest ratio across keys when `null`.
  double? ratioFor(PlanLimitKey? key) {
    if (key != null) return cells[key]!.ratio;
    double? best;
    for (final cell in cells.values) {
      final r = cell.ratio;
      if (r != null && (best == null || r > best)) best = r;
    }
    return best;
  }

  factory UsageLimitsReportRow.fromJson(Map<String, dynamic> json) {
    _refuseForbiddenFields(json);
    final rawCells = json['cells'];
    if (rawCells is! List) throw const FormatException('cells are required');
    final cells = <PlanLimitKey, UsageLimitCell>{};
    for (final item in rawCells) {
      if (item is! Map) throw const FormatException('malformed usage cell');
      final key = item['key'] is String
          ? PlanLimitKey.parse(item['key'] as String)
          : null;
      if (key == null) continue; // A newer limit key: not rendered.
      final limit = item['limit'];
      if (limit != null && limit is! int) {
        throw const FormatException('malformed limit');
      }
      cells[key] = _asFormat(() => UsageLimitCell(
            usage: _requireCount(item['usage'], 'usage'),
            limit: limit as int?,
            overridden: item['overridden'] == true,
          ));
    }
    return _asFormat(() => UsageLimitsReportRow(
          tenant: PlatformReportTenantRef.fromJson(json['tenant']),
          lifecycle: _rowLifecycle(json['lifecycle']),
          plan: PlatformReportPlanRef.fromJson(json['plan']),
          cells: cells,
        ));
  }
}

/// Canonical row order for [key] (or the worst key when `null`): band
/// severity descending, ratio descending (none last), tenant id ascending.
int compareUsageRows(
  UsageLimitsReportRow a,
  UsageLimitsReportRow b, {
  PlanLimitKey? key,
}) {
  final bySeverity = b.bandFor(key).severity.compareTo(a.bandFor(key).severity);
  if (bySeverity != 0) return bySeverity;
  final left = a.ratioFor(key), right = b.ratioFor(key);
  if (left != right) {
    if (left == null) return 1;
    if (right == null) return -1;
    final byRatio = right.compareTo(left);
    if (byRatio != 0) return byRatio;
  }
  return a.tenant.id.compareTo(b.tenant.id);
}

@immutable
class UsageLimitsReportQuery {
  UsageLimitsReportQuery({
    this.limitKey,
    Set<UsageLimitBand> bands = const {},
    this.plan,
    Set<SaasTenantStatus> lifecycles = const {},
    this.cursor,
    this.limit = kPlatformReportDefaultPageSize,
  })  : bands = Set.unmodifiable(bands),
        lifecycles = _checkedLifecycles(lifecycles) {
    checkPlatformReportPageLimit(limit);
  }

  /// One limit to rank by; `null` ranks by each tenant's worst limit.
  final PlanLimitKey? limitKey;

  /// Rows whose band for [limitKey] (or worst band) is in this set; empty
  /// means every band.
  final Set<UsageLimitBand> bands;
  final PlatformReportPlanFilter? plan;
  final Set<SaasTenantStatus> lifecycles;
  final String? cursor;
  final int limit;

  /// [limitKey] only reorders; it does not narrow the dataset.
  bool get isFiltered =>
      bands.isNotEmpty || plan != null || lifecycles.isNotEmpty;

  UsageLimitsReportQuery withCursor(String? cursor) => UsageLimitsReportQuery(
        limitKey: limitKey,
        bands: bands,
        plan: plan,
        lifecycles: lifecycles,
        cursor: cursor,
        limit: limit,
      );

  UsageLimitsReportQuery get firstPage => withCursor(null);

  Map<String, String> toQueryParameters() => {
        if (limitKey != null) 'limitKey': limitKey!.wire,
        if (bands.isNotEmpty)
          'band': _wireList(bands, (b) => (b as UsageLimitBand).wire),
        ...?plan?.toQueryParameters(),
        if (lifecycles.isNotEmpty)
          'lifecycle':
              _wireList(lifecycles, (s) => (s as SaasTenantStatus).wire),
        ..._pageParameters(cursor, limit),
      };

  @override
  bool operator ==(Object other) =>
      other is UsageLimitsReportQuery &&
      other.limitKey == limitKey &&
      setEquals(other.bands, bands) &&
      other.plan == plan &&
      setEquals(other.lifecycles, lifecycles) &&
      other.cursor == cursor &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(
        limitKey,
        Object.hashAllUnordered(bands),
        plan,
        Object.hashAllUnordered(lifecycles),
        cursor,
        limit,
      );
}

@immutable
class UsageLimitsReportSummary {
  UsageLimitsReportSummary({
    required this.tenantCount,
    required Map<PlanLimitKey, PlatformReportBreakdown<UsageLimitBand>> byKey,
  }) : byKey = Map.unmodifiable(byKey) {
    for (final key in PlanLimitKey.values) {
      final breakdown = this.byKey[key];
      if (breakdown == null) throw ArgumentError('missing key ${key.wire}');
      if (breakdown.total != tenantCount) {
        throw ArgumentError('${key.wire} bands must sum to tenantCount');
      }
    }
  }

  final int tenantCount;

  /// Every known limit key → tenants per band over the filtered set.
  final Map<PlanLimitKey, PlatformReportBreakdown<UsageLimitBand>> byKey;
}

@immutable
class UsageLimitsReport implements PlatformReportResult {
  const UsageLimitsReport({
    required this.meta,
    required this.query,
    required this.summary,
    required this.rows,
    this.hasUnsupportedLimitKeys = false,
  });

  @override
  final PlatformReportMeta meta;
  final UsageLimitsReportQuery query;
  final UsageLimitsReportSummary summary;
  final PlatformReportPage<UsageLimitsReportRow> rows;

  /// The server reported limit keys this build does not know; they are not
  /// rendered, and the screen says some limits are not shown.
  final bool hasUnsupportedLimitKeys;

  @override
  bool get isFiltered => query.isFiltered;

  @override
  bool get isEmpty => summary.tenantCount == 0;

  factory UsageLimitsReport.fromJson(
    Map<String, dynamic> json, {
    required UsageLimitsReportQuery query,
  }) {
    final summary = json['summary'];
    if (summary is! Map<String, dynamic> || summary['byKey'] is! List) {
      throw const FormatException('summary is required');
    }
    final tenantCount = _requireCount(summary['tenantCount'], 'tenantCount');
    final byKey = <PlanLimitKey, PlatformReportBreakdown<UsageLimitBand>>{};
    var unsupportedKeys = false;
    for (final item in summary['byKey'] as List) {
      if (item is! Map) throw const FormatException('malformed key summary');
      final key = item['key'] is String
          ? PlanLimitKey.parse(item['key'] as String)
          : null;
      if (key == null) {
        unsupportedKeys = true;
        continue;
      }
      byKey[key] = PlatformReportBreakdown.fromJson(
        item['bands'],
        keys: UsageLimitBand.values,
        parse: UsageLimitBand.parse,
      );
    }
    return UsageLimitsReport(
      meta: PlatformReportMeta.fromJson(
        json,
        expected: PlatformReportType.usageLimits,
      ),
      query: query,
      summary: _asFormat(() =>
          UsageLimitsReportSummary(tenantCount: tenantCount, byKey: byKey)),
      rows: _rowsFromJson(json, UsageLimitsReportRow.fromJson),
      hasUnsupportedLimitKeys: unsupportedKeys,
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Feature availability — current snapshot
// ---------------------------------------------------------------------------

/// A tenant's Feature Flag (module entitlement) state. It says whether the
/// team **has** the module — not whether any administrator may use it
/// (Capability) nor how much it may create (Plan Limit), and not whether the
/// module is used at all.
enum TenantFeatureAvailability {
  enabled('enabled'),
  disabled('disabled');

  const TenantFeatureAvailability(this.wire);
  final String wire;

  static TenantFeatureAvailability? parse(String wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return null;
  }
}

@immutable
class FeatureAvailabilityReportQuery {
  FeatureAvailabilityReportQuery({
    this.featureKey,
    this.state,
    Set<SaasTenantStatus> lifecycles = const {},
    this.cursor,
    this.limit = kPlatformReportDefaultPageSize,
  }) : lifecycles = _checkedLifecycles(lifecycles) {
    checkPlatformReportPageLimit(limit);
    if (state != null && featureKey == null) {
      throw ArgumentError('a feature state filter needs a feature key');
    }
  }

  final TenantFeatureKey? featureKey;
  final TenantFeatureAvailability? state;
  final Set<SaasTenantStatus> lifecycles;
  final String? cursor;
  final int limit;

  bool get isFiltered => state != null || lifecycles.isNotEmpty;

  FeatureAvailabilityReportQuery withCursor(String? cursor) =>
      FeatureAvailabilityReportQuery(
        featureKey: featureKey,
        state: state,
        lifecycles: lifecycles,
        cursor: cursor,
        limit: limit,
      );

  FeatureAvailabilityReportQuery get firstPage => withCursor(null);

  Map<String, String> toQueryParameters() => {
        if (featureKey != null) 'featureKey': featureKey!.wire,
        if (state != null) 'state': state!.wire,
        if (lifecycles.isNotEmpty)
          'lifecycle':
              _wireList(lifecycles, (s) => (s as SaasTenantStatus).wire),
        ..._pageParameters(cursor, limit),
      };

  @override
  bool operator ==(Object other) =>
      other is FeatureAvailabilityReportQuery &&
      other.featureKey == featureKey &&
      other.state == state &&
      setEquals(other.lifecycles, lifecycles) &&
      other.cursor == cursor &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(
        featureKey,
        state,
        Object.hashAllUnordered(lifecycles),
        cursor,
        limit,
      );
}

@immutable
class FeatureAvailabilityRow {
  FeatureAvailabilityRow({
    required this.tenant,
    required this.lifecycle,
    required Map<TenantFeatureKey,
            PlatformReportValue<TenantFeatureAvailability>>
        states,
  }) : states = Map.unmodifiable({
          for (final key in TenantFeatureKey.values)
            key: states[key] ??
                const PlatformReportValue<
                    TenantFeatureAvailability>.unsupported(),
        });

  final PlatformReportTenantRef tenant;
  final PlatformReportValue<SaasTenantStatus> lifecycle;

  /// Every known key. A missing or unreadable state is **unsupported** here —
  /// honest in a report — while tenant access still treats it as disabled
  /// (Point 8 fail-closed).
  final Map<TenantFeatureKey, PlatformReportValue<TenantFeatureAvailability>>
      states;

  factory FeatureAvailabilityRow.fromJson(Map<String, dynamic> json) {
    _refuseForbiddenFields(json);
    final raw = json['features'];
    if (raw is! List) throw const FormatException('features are required');
    final states =
        <TenantFeatureKey, PlatformReportValue<TenantFeatureAvailability>>{};
    for (final item in raw) {
      if (item is! Map) throw const FormatException('malformed feature state');
      final key = item['key'] is String
          ? TenantFeatureKey.parse(item['key'] as String)
          : null;
      if (key == null) continue; // A newer module key: not rendered.
      states[key] = PlatformReportValue.parse(
        item['state'],
        TenantFeatureAvailability.parse,
      );
    }
    return FeatureAvailabilityRow(
      tenant: PlatformReportTenantRef.fromJson(json['tenant']),
      lifecycle: _rowLifecycle(json['lifecycle']),
      states: states,
    );
  }
}

@immutable
class FeatureAvailabilitySummary {
  FeatureAvailabilitySummary({
    required this.tenantCount,
    required Map<TenantFeatureKey,
            PlatformReportBreakdown<TenantFeatureAvailability>>
        byFeature,
  }) : byFeature = Map.unmodifiable(byFeature) {
    for (final key in TenantFeatureKey.values) {
      final breakdown = this.byFeature[key];
      if (breakdown == null) throw ArgumentError('missing ${key.wire}');
      if (breakdown.total != tenantCount) {
        throw ArgumentError('${key.wire} states must sum to tenantCount');
      }
    }
  }

  final int tenantCount;

  /// Enabled / disabled per module, unsupported states in their own bucket.
  final Map<TenantFeatureKey,
      PlatformReportBreakdown<TenantFeatureAvailability>> byFeature;
}

@immutable
class FeatureAvailabilityReport implements PlatformReportResult {
  const FeatureAvailabilityReport({
    required this.meta,
    required this.query,
    required this.summary,
    required this.rows,
    this.hasUnsupportedFeatureKeys = false,
  });

  @override
  final PlatformReportMeta meta;
  final FeatureAvailabilityReportQuery query;
  final FeatureAvailabilitySummary summary;
  final PlatformReportPage<FeatureAvailabilityRow> rows;
  final bool hasUnsupportedFeatureKeys;

  @override
  bool get isFiltered => query.isFiltered;

  @override
  bool get isEmpty => summary.tenantCount == 0;

  factory FeatureAvailabilityReport.fromJson(
    Map<String, dynamic> json, {
    required FeatureAvailabilityReportQuery query,
  }) {
    final summary = json['summary'];
    if (summary is! Map<String, dynamic> || summary['byFeature'] is! List) {
      throw const FormatException('summary is required');
    }
    final tenantCount = _requireCount(summary['tenantCount'], 'tenantCount');
    final byFeature = <TenantFeatureKey,
        PlatformReportBreakdown<TenantFeatureAvailability>>{};
    var unsupportedKeys = false;
    for (final item in summary['byFeature'] as List) {
      if (item is! Map) {
        throw const FormatException('malformed feature summary');
      }
      final key = item['key'] is String
          ? TenantFeatureKey.parse(item['key'] as String)
          : null;
      if (key == null) {
        unsupportedKeys = true;
        continue;
      }
      byFeature[key] = PlatformReportBreakdown.fromJson(
        item['states'],
        keys: TenantFeatureAvailability.values,
        parse: TenantFeatureAvailability.parse,
      );
    }
    return FeatureAvailabilityReport(
      meta: PlatformReportMeta.fromJson(
        json,
        expected: PlatformReportType.featureAvailability,
      ),
      query: query,
      summary: _asFormat(() => FeatureAvailabilitySummary(
            tenantCount: tenantCount,
            byFeature: byFeature,
          )),
      rows: _rowsFromJson(json, FeatureAvailabilityRow.fromJson),
      hasUnsupportedFeatureKeys: unsupportedKeys,
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Platform activity — period summary derived from Audit
// ---------------------------------------------------------------------------

/// The Audit actions this build can count — every known action.
final List<PlatformAuditAction> kReportableAuditActions = List.unmodifiable(
  PlatformAuditAction.values.where((a) => a != PlatformAuditAction.unknown),
);

PlatformAuditAction? _knownAction(String wire) {
  final action = PlatformAuditAction.parse(wire);
  return action == PlatformAuditAction.unknown ? null : action;
}

@immutable
class PlatformActivityReportQuery {
  PlatformActivityReportQuery({required this.range, this.category}) {
    if (category == PlatformAuditCategory.unknown) {
      throw ArgumentError('unknown is not a filterable category');
    }
  }

  factory PlatformActivityReportQuery.defaultAt(DateTime now) =>
      PlatformActivityReportQuery(range: PlatformReportRange.defaultAt(now));

  final PlatformReportRange range;
  final PlatformAuditCategory? category;

  /// The range is the report's subject, not a filter; only a category narrows.
  bool get isFiltered => category != null;

  Map<String, String> toQueryParameters() => {
        ...range.toQueryParameters(),
        if (category != null) 'category': category!.wire,
      };

  @override
  bool operator ==(Object other) =>
      other is PlatformActivityReportQuery &&
      other.range == range &&
      other.category == category;

  @override
  int get hashCode => Object.hash(range, category);
}

/// How many control-plane actions Audit recorded in a range — counts only.
///
/// No actor, tenant, target, change body or reason is present: the Audit Log
/// remains the evidence, and every count opens it through [auditQueryFor].
@immutable
class PlatformActivityReport implements PlatformReportResult {
  PlatformActivityReport({
    required this.meta,
    required this.query,
    required this.byAction,
    DateTime? evidenceAvailableFrom,
  }) : evidenceAvailableFrom = evidenceAvailableFrom?.toUtc() {
    final category = query.category;
    if (category != null) {
      for (final action in byAction.keys) {
        if (action.category != category && byAction[action] > 0) {
          throw ArgumentError('${action.wire} is outside ${category.wire}');
        }
      }
    }
  }

  @override
  final PlatformReportMeta meta;
  final PlatformActivityReportQuery query;

  /// Every known action (zero-filled). Actions from a newer backend are
  /// counted in `unsupported` — shown as "other actions", never dropped and
  /// never merged into a known action.
  final PlatformReportBreakdown<PlatformAuditAction> byAction;

  /// The earliest instant for which the platform still retains Audit
  /// evidence, when that is later than the range start; `null` when the
  /// whole range is covered. Earlier counts are **unknown**, not zero.
  final DateTime? evidenceAvailableFrom;

  bool get isCoveragePartial =>
      evidenceAvailableFrom != null &&
      evidenceAvailableFrom!.isAfter(query.range.from);

  int get total => byAction.total;

  /// Category totals derived from [byAction]; unsupported actions stay
  /// unsupported.
  PlatformReportBreakdown<PlatformAuditCategory> get byCategory {
    final counts = <PlatformAuditCategory, int>{};
    for (final action in byAction.keys) {
      counts[action.category] =
          (counts[action.category] ?? 0) + byAction[action];
    }
    return PlatformReportBreakdown(
      keys: PlatformAuditCategory.values
          .where((c) => c != PlatformAuditCategory.unknown)
          .toList(),
      counts: counts,
      unsupported: byAction.unsupported,
    );
  }

  /// The Audit query that lists exactly the events behind [action]'s count.
  PlatformAuditQuery auditQueryFor(PlatformAuditAction action) {
    if (action == PlatformAuditAction.unknown) {
      throw ArgumentError('unsupported actions have no typed drill-down');
    }
    return PlatformAuditQuery(
      from: query.range.from,
      before: query.range.before,
      action: action,
    );
  }

  @override
  bool get isFiltered => query.isFiltered;

  @override
  bool get isEmpty => total == 0;

  factory PlatformActivityReport.fromJson(
    Map<String, dynamic> json, {
    required PlatformActivityReportQuery query,
  }) {
    final range = json['range'];
    if (range is! Map ||
        parseReportInstant(range['from']) != query.range.from ||
        parseReportInstant(range['before']) != query.range.before) {
      throw const FormatException('report range does not match the query');
    }
    _refuseForbiddenFields(json);
    return _asFormat(() => PlatformActivityReport(
          meta: PlatformReportMeta.fromJson(
            json,
            expected: PlatformReportType.platformActivity,
          ),
          query: query,
          byAction: PlatformReportBreakdown.fromJson(
            json['byAction'],
            keys: kReportableAuditActions,
            parse: _knownAction,
          ),
          evidenceAvailableFrom:
              parseOptionalReportInstant(json['evidenceAvailableFrom']),
        ));
  }
}
