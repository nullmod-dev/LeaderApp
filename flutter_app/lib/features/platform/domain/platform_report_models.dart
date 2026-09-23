/// Point 13A — the shared foundation of **Platform Reports**.
///
/// A Platform Report is a structured, read-only view over one explicitly
/// bounded **control-plane** dataset, answering one fixed question for the
/// Super Admin. It is not the Overview (current awareness), not the Audit Log
/// (immutable actor-attributed evidence) and not Security (current alerts).
/// Reports summarize; they never become a second copy of those systems.
///
/// This file holds what every report shares: the closed catalogue, the date
/// range contract, typed fail-safe values and breakdowns, pages, freshness and
/// the pure paging state. The four report datasets live in
/// `platform_report_datasets.dart`. No tenant-operational type is imported
/// here, and nothing here can carry a Team Code, credential, session material,
/// Main Admin contact, medical record or member data — there is no field to put
/// one in.
library;

import 'package:flutter/foundation.dart';

import '../../../core/result/result.dart';

// ---------------------------------------------------------------------------
// Catalogue
// ---------------------------------------------------------------------------

/// The closed initial report catalogue. Adding a report is a contract change.
enum PlatformReportType {
  /// Current commercial portfolio: subscription status × plan × lifecycle.
  subscriptions('subscriptions'),

  /// Current usage against effective plan limits, per tenant.
  usageLimits('usage_limits'),

  /// Current Feature Flag (module entitlement) distribution.
  featureAvailability('feature_availability'),

  /// Counts of control-plane actions in a date range, derived from Audit.
  platformActivity('platform_activity'),

  /// A report type introduced by a newer backend. Never rendered as a report.
  unknown('unknown');

  const PlatformReportType(this.wire);
  final String wire;

  static PlatformReportType parse(Object? wire) => values.firstWhere(
        (value) => value != unknown && value.wire == wire,
        orElse: () => unknown,
      );
}

/// What kind of truth a report states. Reports never mix the two.
enum PlatformReportDataKind {
  /// Computed from current state at `generatedAt`. Carries no history and must
  /// never be presented as a trend.
  currentSnapshot('current_snapshot'),

  /// Counts of historical events inside an explicit `[from, before)` range.
  periodSummary('period_summary');

  const PlatformReportDataKind(this.wire);
  final String wire;
}

/// The established Platform datasets a report may read. Health, Security,
/// break-glass grant state and every tenant-operational dataset are
/// deliberately absent: none has report-grade history or a report contract.
enum PlatformReportSource {
  tenantLifecycle,
  subscription,
  planLimits,
  usageAggregates,
  featureFlags,
  auditEvidence,
}

/// How much identity a report payload may contain.
enum PlatformReportPrivacy {
  /// Counts only. No tenant, actor or target identity.
  aggregateOnly('aggregate_only'),

  /// Aggregates plus control-plane tenant rows limited to tenant id and
  /// display name. Never Team Code, Main Admin contact, reasons or
  /// tenant-operational records.
  controlPlaneTenantRows('control_plane_tenant_rows');

  const PlatformReportPrivacy(this.wire);
  final String wire;
}

/// The typed filter dimensions a report may accept. Each report declares its
/// own subset; there is no universal filter object.
enum PlatformReportFilterField {
  subscriptionStatus,
  plan,
  lifecycleStatus,
  dueBefore,
  limitKey,
  usageBand,
  featureKey,
  featureState,
  dateRange,
  auditCategory,
}

/// Where a report row may lead. Reports never open a tenant-operational shell.
enum PlatformReportDrillDown {
  none,

  /// `/platform/tenants/:tenantId` — current tenants only.
  tenantDetail,

  /// `/platform/audit` pre-filtered by range and action — the evidence.
  auditEvents,
}

@immutable
class PlatformReportDefinition {
  const PlatformReportDefinition({
    required this.type,
    required this.dataKind,
    required this.sources,
    required this.filters,
    required this.privacy,
    required this.paginatedRows,
    required this.drillDown,
  });

  final PlatformReportType type;
  final PlatformReportDataKind dataKind;
  final Set<PlatformReportSource> sources;
  final Set<PlatformReportFilterField> filters;
  final PlatformReportPrivacy privacy;

  /// Whether the report has a tenant-row table that must be paged.
  final bool paginatedRows;
  final PlatformReportDrillDown drillDown;

  /// Point 13 approves **no export** for any report. There is no backend
  /// export contract, and a client-built file from a paged cross-tenant view
  /// would be both partial and a copy leaving the control plane.
  bool get exportable => false;
}

/// The one statement of which reports exist and what each may read.
abstract final class PlatformReportCatalogue {
  static const List<PlatformReportDefinition> all = [
    PlatformReportDefinition(
      type: PlatformReportType.subscriptions,
      dataKind: PlatformReportDataKind.currentSnapshot,
      sources: {
        PlatformReportSource.subscription,
        PlatformReportSource.tenantLifecycle,
      },
      filters: {
        PlatformReportFilterField.subscriptionStatus,
        PlatformReportFilterField.plan,
        PlatformReportFilterField.lifecycleStatus,
        PlatformReportFilterField.dueBefore,
      },
      privacy: PlatformReportPrivacy.controlPlaneTenantRows,
      paginatedRows: true,
      drillDown: PlatformReportDrillDown.tenantDetail,
    ),
    PlatformReportDefinition(
      type: PlatformReportType.usageLimits,
      dataKind: PlatformReportDataKind.currentSnapshot,
      sources: {
        PlatformReportSource.usageAggregates,
        PlatformReportSource.planLimits,
        PlatformReportSource.tenantLifecycle,
      },
      filters: {
        PlatformReportFilterField.limitKey,
        PlatformReportFilterField.usageBand,
        PlatformReportFilterField.plan,
        PlatformReportFilterField.lifecycleStatus,
      },
      privacy: PlatformReportPrivacy.controlPlaneTenantRows,
      paginatedRows: true,
      drillDown: PlatformReportDrillDown.tenantDetail,
    ),
    PlatformReportDefinition(
      type: PlatformReportType.featureAvailability,
      dataKind: PlatformReportDataKind.currentSnapshot,
      sources: {
        PlatformReportSource.featureFlags,
        PlatformReportSource.tenantLifecycle,
      },
      filters: {
        PlatformReportFilterField.featureKey,
        PlatformReportFilterField.featureState,
        PlatformReportFilterField.lifecycleStatus,
      },
      privacy: PlatformReportPrivacy.controlPlaneTenantRows,
      paginatedRows: true,
      drillDown: PlatformReportDrillDown.tenantDetail,
    ),
    PlatformReportDefinition(
      type: PlatformReportType.platformActivity,
      dataKind: PlatformReportDataKind.periodSummary,
      sources: {PlatformReportSource.auditEvidence},
      filters: {
        PlatformReportFilterField.dateRange,
        PlatformReportFilterField.auditCategory,
      },
      privacy: PlatformReportPrivacy.aggregateOnly,
      paginatedRows: false,
      drillDown: PlatformReportDrillDown.auditEvents,
    ),
  ];

  /// `null` for [PlatformReportType.unknown]: an unknown report has no
  /// definition and is never offered.
  static PlatformReportDefinition? of(PlatformReportType type) {
    for (final definition in all) {
      if (definition.type == type) return definition;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Date range
// ---------------------------------------------------------------------------

/// Default period-summary range: the last 30 device-local calendar days,
/// including today.
const int kPlatformReportDefaultRangeDays = 30;

/// Longest selectable period-summary range in device-local calendar days.
///
/// Justified while Audit retention is undecided: a year bounds what a report
/// may claim to cover and bounds the server aggregation.
const int kPlatformReportMaxRangeDays = 366;

/// A half-open `[from, before)` range of exact UTC instants.
///
/// Identical to the Audit filter convention: the operator picks device-local
/// calendar days; the client sends the start of the first local day and the
/// start of the day **after** the last local day, both converted to UTC. The
/// server counts events whose timestamp satisfies `from <= t < before` and
/// never re-buckets or truncates timestamps into calendar days.
@immutable
class PlatformReportRange {
  PlatformReportRange({required DateTime from, required DateTime before})
      : from = from.toUtc(),
        before = before.toUtc() {
    if (!this.from.isBefore(this.before)) {
      throw ArgumentError('from must be earlier than before');
    }
    if (this.before.difference(this.from) > maxSpan) {
      throw ArgumentError('range exceeds $kPlatformReportMaxRangeDays days');
    }
  }

  /// [kPlatformReportMaxRangeDays] local days plus one day of slack, so a
  /// maximal local selection that crosses a UTC-offset change is still valid.
  /// The server applies the same instant-span bound.
  static const Duration maxSpan =
      Duration(days: kPlatformReportMaxRangeDays + 1);

  /// From device-local calendar days [first] … [last], both inclusive.
  factory PlatformReportRange.localDays({
    required DateTime first,
    required DateTime last,
  }) {
    final days = _calendarDaysBetween(first, last) + 1;
    if (days < 1) throw ArgumentError('last day precedes first day');
    if (days > kPlatformReportMaxRangeDays) {
      throw ArgumentError('range exceeds $kPlatformReportMaxRangeDays days');
    }
    return PlatformReportRange(
      from: DateTime(first.year, first.month, first.day),
      before: DateTime(last.year, last.month, last.day + 1),
    );
  }

  /// The default range at the injected clock instant [now].
  factory PlatformReportRange.defaultAt(DateTime now) {
    final today = now.toLocal();
    return PlatformReportRange.localDays(
      first: DateTime(
        today.year,
        today.month,
        today.day - (kPlatformReportDefaultRangeDays - 1),
      ),
      last: today,
    );
  }

  /// Inclusive, UTC.
  final DateTime from;

  /// Exclusive, UTC.
  final DateTime before;

  bool contains(DateTime instant) {
    final t = instant.toUtc();
    return !t.isBefore(from) && t.isBefore(before);
  }

  /// The first device-local calendar day the range covers, for display.
  DateTime get firstLocalDay {
    final local = from.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// The last device-local calendar day the range covers, for display.
  DateTime get lastLocalDay {
    final local = before.subtract(const Duration(microseconds: 1)).toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  Map<String, String> toQueryParameters() => {
        'from': from.toIso8601String(),
        'before': before.toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is PlatformReportRange &&
      other.from == from &&
      other.before == before;

  @override
  int get hashCode => Object.hash(from, before);
}

int _calendarDaysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day)
        .difference(DateTime.utc(a.year, a.month, a.day))
        .inDays;

// ---------------------------------------------------------------------------
// Typed fail-safe values and breakdowns
// ---------------------------------------------------------------------------

/// A dimension value that is either one this build understands or an
/// unsupported value from a newer backend.
///
/// Unsupported values are **never** mapped onto a harmless known value, and
/// the raw wire string is not retained for display.
@immutable
sealed class PlatformReportValue<T extends Object> {
  const PlatformReportValue();

  const factory PlatformReportValue.supported(T value) =
      SupportedPlatformReportValue<T>;
  const factory PlatformReportValue.unsupported() =
      UnsupportedPlatformReportValue<T>;

  /// Parses [raw] with [parse]; anything [parse] rejects is unsupported.
  factory PlatformReportValue.parse(Object? raw, T? Function(String) parse) {
    final value = raw is String ? parse(raw) : null;
    return value == null
        ? PlatformReportValue<T>.unsupported()
        : PlatformReportValue<T>.supported(value);
  }

  /// The known value, or `null` when unsupported.
  T? get valueOrNull;
  bool get isSupported => valueOrNull != null;
}

final class SupportedPlatformReportValue<T extends Object>
    extends PlatformReportValue<T> {
  const SupportedPlatformReportValue(this.value);
  final T value;

  @override
  T get valueOrNull => value;

  @override
  bool operator ==(Object other) =>
      other is SupportedPlatformReportValue<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class UnsupportedPlatformReportValue<T extends Object>
    extends PlatformReportValue<T> {
  const UnsupportedPlatformReportValue();

  @override
  T? get valueOrNull => null;

  @override
  bool operator ==(Object other) => other is UnsupportedPlatformReportValue<T>;

  @override
  int get hashCode => Object.hash(UnsupportedPlatformReportValue, T);
}

/// Counts grouped by one closed dimension, plus one explicit unsupported
/// bucket. Every known key is present (zero-filled), so absence is never
/// confused with zero.
///
/// Invariant: `total == sum(counts) + unsupported`, every count `>= 0`.
@immutable
class PlatformReportBreakdown<K extends Object> {
  PlatformReportBreakdown({
    required List<K> keys,
    Map<K, int> counts = const {},
    this.unsupported = 0,
  })  : keys = List.unmodifiable(keys),
        counts = Map.unmodifiable({
          for (final key in keys) key: counts[key] ?? 0,
        }) {
    if (unsupported < 0) throw ArgumentError.value(unsupported, 'unsupported');
    for (final entry in counts.entries) {
      if (!keys.contains(entry.key)) {
        throw ArgumentError('key ${entry.key} is not in this dimension');
      }
      if (entry.value < 0) throw ArgumentError.value(entry.value, '$entry');
    }
  }

  /// Parses `[{"key": "...", "count": n}, ...]`. Keys this build does not know
  /// — and keys outside [keys] — are summed into [unsupported], never dropped.
  factory PlatformReportBreakdown.fromJson(
    Object? raw, {
    required List<K> keys,
    required K? Function(String) parse,
  }) {
    if (raw is! List) throw const FormatException('breakdown must be a list');
    final counts = <K, int>{};
    var unsupported = 0;
    for (final item in raw) {
      if (item is! Map || item['count'] is! int) {
        throw const FormatException('malformed breakdown bucket');
      }
      final count = item['count'] as int;
      if (count < 0) throw const FormatException('negative bucket count');
      final key = item['key'] is String ? parse(item['key'] as String) : null;
      if (key == null || !keys.contains(key)) {
        unsupported += count;
      } else {
        if (counts.containsKey(key)) {
          throw const FormatException('duplicate breakdown bucket');
        }
        counts[key] = count;
      }
    }
    return PlatformReportBreakdown(
      keys: keys,
      counts: counts,
      unsupported: unsupported,
    );
  }

  final List<K> keys;
  final Map<K, int> counts;
  final int unsupported;

  int operator [](K key) => counts[key] ?? 0;

  int get total => counts.values.fold(unsupported, (sum, n) => sum + n);
  bool get isEmpty => total == 0;
}

// ---------------------------------------------------------------------------
// Report envelope, pages, freshness
// ---------------------------------------------------------------------------

/// The provenance every report states.
@immutable
class PlatformReportMeta {
  PlatformReportMeta({
    required this.type,
    required DateTime generatedAt,
    required this.snapshotId,
  })  : generatedAt = generatedAt.toUtc(),
        assert(type != PlatformReportType.unknown),
        assert(snapshotId != '');

  final PlatformReportType type;

  /// When the server computed this result (UTC). A snapshot report states
  /// "as of" this instant; it is never refreshed by the client clock.
  final DateTime generatedAt;

  /// Opaque identity of the computed result. Every cursor belongs to exactly
  /// one snapshot; rows from two snapshots are never shown together.
  final String snapshotId;

  /// Parses and checks that the server answered the report that was asked.
  factory PlatformReportMeta.fromJson(
    Map<String, dynamic> json, {
    required PlatformReportType expected,
  }) {
    final type = PlatformReportType.parse(json['type']);
    if (type != expected) {
      throw FormatException('unexpected report type', json['type']);
    }
    final snapshotId = json['snapshotId'];
    if (snapshotId is! String || snapshotId.isEmpty) {
      throw const FormatException('snapshotId is required');
    }
    return PlatformReportMeta(
      type: type,
      generatedAt: parseReportInstant(json['generatedAt']),
      snapshotId: snapshotId,
    );
  }
}

/// What every report result exposes to shared selectors.
abstract interface class PlatformReportResult {
  PlatformReportMeta get meta;

  /// Whether the report's query narrows the dataset (drives filtered-empty).
  bool get isFiltered;

  /// Whether the report's dataset/result contains nothing to show.
  bool get isEmpty;
}

/// One page of report rows. The cursor is **opaque**: the client never builds,
/// parses or edits one.
@immutable
class PlatformReportPage<R> {
  PlatformReportPage({required List<R> items, this.nextCursor})
      : items = List.unmodifiable(items),
        assert(nextCursor == null || nextCursor != '');

  final List<R> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  PlatformReportPage<T> cast<T>() =>
      PlatformReportPage(items: items.cast<T>(), nextCursor: nextCursor);
}

/// Page size contract shared with Point 11 Audit: 1–100, default 50.
const int kPlatformReportDefaultPageSize = 50;
const int kPlatformReportMaxPageSize = 100;

void checkPlatformReportPageLimit(int limit) {
  if (limit < 1 || limit > kPlatformReportMaxPageSize) {
    throw ArgumentError.value(limit, 'limit', 'must be between 1 and 100');
  }
}

/// How current a displayed report is. Never derived from the device clock.
enum PlatformReportFreshness {
  /// Just read from the server.
  fresh,

  /// Served from cache after a refresh failed; say so.
  stale,

  /// Offline, showing a previously read result; say so, never claim current.
  offlineCached,
}

/// The designed screen state for one report read.
enum PlatformReportViewState {
  loaded,

  /// The dataset has nothing at all (no tenants / no activity in the range).
  empty,

  /// The filters exclude everything; offer to clear them.
  filteredEmpty,

  /// Offline and nothing cached: say the report cannot be shown offline.
  offlineNoData,
  notPermitted,
  failure,
}

/// Feature-owned report problem codes (core codes cover the rest:
/// `validation`, `not_permitted`, `server`).
enum PlatformReportProblemCode {
  /// The cursor's snapshot no longer exists; reload page one.
  cursorExpired('report_cursor_expired'),

  /// A period range beyond the server's bound.
  rangeTooLarge('report_range_too_large'),

  /// The backend does not serve this report type (yet).
  reportUnavailable('report_unavailable');

  const PlatformReportProblemCode(this.wire);
  final String wire;
}

/// Pure freshness selector. `null` when there is no result to label.
PlatformReportFreshness? platformReportFreshness<R>(Result<R> result) =>
    switch (result) {
      Success<R>(:final stale) =>
        stale ? PlatformReportFreshness.stale : PlatformReportFreshness.fresh,
      Offline<R>(:final cached) =>
        cached == null ? null : PlatformReportFreshness.offlineCached,
      Failure<R>() => null,
    };

/// Pure view-state selector shared by every report screen.
PlatformReportViewState platformReportViewState<R extends PlatformReportResult>(
  Result<R> result,
) {
  R? report;
  switch (result) {
    case Success<R>(:final data):
      report = data;
    case Offline<R>(:final cached):
      if (cached == null) return PlatformReportViewState.offlineNoData;
      report = cached;
    case Failure<R>(:final code):
      return code == 'not_permitted'
          ? PlatformReportViewState.notPermitted
          : PlatformReportViewState.failure;
  }
  if (!report.isEmpty) return PlatformReportViewState.loaded;
  return report.isFiltered
      ? PlatformReportViewState.filteredEmpty
      : PlatformReportViewState.empty;
}

// ---------------------------------------------------------------------------
// Paging state
// ---------------------------------------------------------------------------

/// The pure accumulated-rows state for one report query.
///
/// Rules 13B's controller must keep: page one replaces everything; later
/// pages append in server order with key de-duplication; a page from another
/// snapshot, a repeated cursor or `report_cursor_expired` stops paging and
/// asks for a deliberate first-page reload; a failed next page keeps every
/// loaded row.
@immutable
class PlatformReportRowsState<R> {
  PlatformReportRowsState._({
    required this.snapshotId,
    required List<R> items,
    required this.nextCursor,
    required Set<String> usedCursors,
    this.pageFailed = false,
    this.mustReload = false,
  })  : items = List.unmodifiable(items),
        _usedCursors = Set.unmodifiable(usedCursors);

  factory PlatformReportRowsState.firstPage({
    required String snapshotId,
    required PlatformReportPage<R> page,
  }) =>
      PlatformReportRowsState._(
        snapshotId: snapshotId,
        items: page.items,
        nextCursor: page.nextCursor,
        usedCursors: const {},
      );

  final String snapshotId;
  final List<R> items;
  final String? nextCursor;
  final Set<String> _usedCursors;

  /// The last next-page request failed; loaded rows remain, retry is allowed.
  final bool pageFailed;

  /// Paging cannot continue safely; only a first-page reload may follow.
  final bool mustReload;

  bool get canLoadMore => nextCursor != null && !mustReload;

  /// Appends [page], fetched with [cursor], if it belongs to this snapshot.
  PlatformReportRowsState<R> appendPage({
    required String cursor,
    required String snapshotId,
    required PlatformReportPage<R> page,
    required String Function(R row) keyOf,
  }) {
    if (snapshotId != this.snapshotId || cursor != nextCursor) {
      return _stop();
    }
    final used = {..._usedCursors, cursor};
    final next = page.nextCursor;
    final seen = <String>{};
    final merged = [
      for (final row in [...items, ...page.items])
        if (seen.add(keyOf(row))) row,
    ];
    final repeated = next != null && (used.contains(next) || next == cursor);
    return PlatformReportRowsState._(
      snapshotId: this.snapshotId,
      items: merged,
      nextCursor: repeated ? null : next,
      usedCursors: used,
      mustReload: repeated,
    );
  }

  /// The next page failed with [code]. Loaded rows are always kept.
  PlatformReportRowsState<R> pageFailure({String? code}) =>
      code == PlatformReportProblemCode.cursorExpired.wire ||
              code == 'validation'
          ? _stop()
          : PlatformReportRowsState._(
              snapshotId: snapshotId,
              items: items,
              nextCursor: nextCursor,
              usedCursors: _usedCursors,
              pageFailed: true,
            );

  PlatformReportRowsState<R> _stop() => PlatformReportRowsState._(
        snapshotId: snapshotId,
        items: items,
        nextCursor: null,
        usedCursors: _usedCursors,
        mustReload: true,
      );
}

// ---------------------------------------------------------------------------

/// Parses an RFC 3339 instant **with** an explicit offset and normalizes it to
/// UTC. An offset-less or malformed timestamp makes the report unreadable.
DateTime parseReportInstant(Object? raw) {
  if (raw is! String) throw const FormatException('timestamp must be a string');
  if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(raw)) {
    throw FormatException('timestamp needs an explicit offset', raw);
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) throw FormatException('invalid timestamp', raw);
  return parsed.toUtc();
}

DateTime? parseOptionalReportInstant(Object? raw) =>
    raw == null ? null : parseReportInstant(raw);
