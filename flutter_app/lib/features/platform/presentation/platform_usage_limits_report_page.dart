import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/saas_tenant_status.dart';
import '../../../core/format/app_date.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../data/platform_report_rows_controller.dart';
import '../data/platform_reports_providers.dart';
import '../domain/platform_report_datasets.dart';
import '../domain/platform_report_models.dart';
import '../domain/saas_subscription_models.dart';
import 'platform_reports_copy.dart';
import 'saas_subscription_copy.dart';
import 'saas_tenant_routes.dart';
import 'tenant_lifecycle_copy.dart';
import 'widgets/platform_meta.dart';
import 'widgets/platform_report_widgets.dart';

/// `/platform/reports/usage_limits` — Point 13A §B row 2.
class PlatformUsageLimitsReportPage extends ConsumerStatefulWidget {
  const PlatformUsageLimitsReportPage({super.key});

  @override
  ConsumerState<PlatformUsageLimitsReportPage> createState() =>
      _PlatformUsageLimitsReportPageState();
}

class _PlatformUsageLimitsReportPageState
    extends ConsumerState<PlatformUsageLimitsReportPage> {
  UsageLimitsReportQuery query = UsageLimitsReportQuery();

  late final rows = PlatformReportRowsController<UsageLimitsReportQuery,
      UsageLimitsReport, UsageLimitsReportRow>(
    loadPage: (q) =>
        ref.read(platformReportsRepositoryProvider).loadUsageLimits(q),
    pageOf: (r) => r.rows,
    snapshotIdOf: (r) => r.meta.snapshotId,
    withCursor: (q, cursor) => q.withCursor(cursor),
    keyOf: (row) => row.tenant.id,
  );

  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    rows.addListener(_update);
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    rows.removeListener(_update);
    rows.dispose();
    super.dispose();
  }

  void _setQuery(UsageLimitsReportQuery next) {
    if (next == query) return;
    setState(() => query = next);
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    ref.invalidate(usageLimitsReportProvider(query));
    await ref.read(usageLimitsReportProvider(query).future);
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _openFilters() async {
    final next = await showReportFilterSheet<UsageLimitsReportQuery>(
      context,
      title:
          '${PlatformReportsCopy.title(PlatformReportType.usageLimits)} · ${S.platformReportFiltersButton}',
      initial: query,
      builder: (context, q, onChange) =>
          _UsageFilterForm(query: q, onChange: onChange),
      cleared: () => UsageLimitsReportQuery(limitKey: query.limitKey),
    );
    if (next != null) _setQuery(next);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(usageLimitsReportProvider(query));
    final count = _filterCount(query);

    return PlatformReportScaffold(
      title: PlatformReportsCopy.title(PlatformReportType.usageLimits),
      onRefresh: _refresh,
      refreshing: _refreshing || (async.isLoading && async.hasValue),
      filterCount: count,
      onOpenFilters: _openFilters,
      filterPanel: _UsageFilterForm(query: query, onChange: _setQuery),
      filterChips: _chips(query),
      onClearFilters: count == 0
          ? null
          : () => _setQuery(UsageLimitsReportQuery(limitKey: query.limitKey)),
      bodyBuilder: (wide) => [_body(async, wide)],
    );
  }

  Widget _body(AsyncValue<Result<UsageLimitsReport>> async, bool wide) {
    if (!async.hasValue) {
      return const _SkeletonBody(key: Key('usage-loading'));
    }
    if (async.hasError) {
      return ErrorStateView(
        key: const Key('usage-failure'),
        title: S.platformReportFailureTitle,
        body: S.platformReportFailureBody,
        onRetry: _refresh,
      );
    }
    final result = async.requireValue;
    final viewState = platformReportViewState(result);
    final freshness = platformReportFreshness(result);
    final report = switch (result) {
      Success<UsageLimitsReport>(:final data) => data,
      Offline<UsageLimitsReport>(:final cached) => cached,
      Failure<UsageLimitsReport>() => null,
    };

    switch (viewState) {
      case PlatformReportViewState.offlineNoData:
        return EmptyState(
          key: const Key('usage-offline'),
          icon: Icons.cloud_off_rounded,
          title: S.platformReportOfflineNoDataTitle,
          body: S.platformReportOfflineNoDataBody,
          actionLabel: S.platformReportRetry,
          onAction: _refresh,
        );
      case PlatformReportViewState.notPermitted:
        return const EmptyState(
          key: Key('usage-not-permitted'),
          icon: Icons.lock_outline_rounded,
          title: S.platformReportNotPermittedTitle,
          body: '',
        );
      case PlatformReportViewState.failure:
        return ErrorStateView(
          key: const Key('usage-failure'),
          title: S.platformReportFailureTitle,
          body: S.platformReportFailureBody,
          onRetry: _refresh,
        );
      case PlatformReportViewState.empty:
      case PlatformReportViewState.filteredEmpty:
      case PlatformReportViewState.loaded:
        break;
    }

    final loadedReport = report!;
    if (rows.needsSync(loadedReport.meta.snapshotId)) {
      rows.syncFirstPage(query, loadedReport.meta, loadedReport.rows);
    }
    final rowsState = rows.state!;

    return Column(
      key: const Key('usage-loaded'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportProvenanceLine(
          lines: [
            'لقطة حالية — حتى ${AppDate.dayMonthTime(loadedReport.meta.generatedAt.toLocal())}',
            S.platformReportScopeNote,
            if (loadedReport.hasUnsupportedLimitKeys)
              S.platformReportUnsupportedKeysNote,
          ],
          stale: freshness == PlatformReportFreshness.stale,
          offlineCached: freshness == PlatformReportFreshness.offlineCached,
        ),
        const SizedBox(height: AppSpacing.md),
        _LimitKeyPillRow(
          selected: query.limitKey,
          onSelect: (key) => _setQuery(UsageLimitsReportQuery(
            limitKey: key,
            bands: query.bands,
            plan: query.plan,
            lifecycles: query.lifecycles,
            limit: query.limit,
          )),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (viewState == PlatformReportViewState.filteredEmpty)
          EmptyState(
            key: const Key('usage-filtered-empty'),
            icon: Icons.filter_alt_off_outlined,
            title: S.platformReportFilteredEmptyTitle,
            body: S.platformReportFilteredEmptyBody,
            actionLabel: S.platformReportFiltersClearAll,
            onAction: () =>
                _setQuery(UsageLimitsReportQuery(limitKey: query.limitKey)),
          )
        else if (viewState == PlatformReportViewState.empty)
          const EmptyState(
            key: Key('usage-empty'),
            icon: Icons.speed_outlined,
            title: S.platformReportEmptyTeamsTitle,
            body: S.platformReportEmptyTeamsBody,
          )
        else ...[
          if (wide)
            _UsageKeyBandTable(summary: loadedReport.summary)
          else
            for (final key in PlanLimitKey.values)
              ReportBreakdownSection(
                title: planLimitLabel(key),
                total: loadedReport.summary.tenantCount,
                rows: [
                  for (final band in UsageLimitBand.values)
                    ReportBreakdownRow(
                      label: PlatformReportsCopy.bandLabel(band),
                      count: loadedReport.summary.byKey[key]![band],
                      kind: PlatformReportsCopy.bandKind(band),
                    ),
                ],
              ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${S.platformReportRowsLabel} (${loadedReport.summary.tenantCount})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (wide)
            ReportDenseTable(
              columnLabels: const [
                S.platformReportColumnTeam,
                S.platformReportColumnUsage,
                S.platformReportColumnBand,
              ],
              columnFlex: const [3, 3, 2],
              rows: [
                for (final row in rowsState.items)
                  _denseRow(row, query.limitKey),
              ],
            )
          else
            for (final row in rowsState.items) ...[
              _UsageRowTile(row: row, selectedKey: query.limitKey),
              const Divider(height: 1),
            ],
          ReportPagingFooter(
            shown: rowsState.items.length,
            total: loadedReport.summary.tenantCount,
            hasMore: rowsState.canLoadMore,
            paging: rows.paging,
            pageFailed: rowsState.pageFailed,
            mustReload: rowsState.mustReload,
            offlinePaging: rows.offlinePaging,
            onLoadMore: () => unawaited(rows.loadMore()),
            onReload: _refresh,
          ),
        ],
      ],
    );
  }

  ReportDenseTableRow _denseRow(
      UsageLimitsReportRow row, PlanLimitKey? selectedKey) {
    final key = selectedKey ??
        row.cells.entries
            .reduce((a, b) =>
                a.value.band.severity >= b.value.band.severity ? a : b)
            .key;
    final cell = row.cells[key]!;
    final band = row.bandFor(selectedKey);
    final limitText =
        cell.limit == null ? '—' : formatLimitValue(key, cell.limit!);
    final usageText =
        '${planLimitLabel(key)}: ${formatLimitValue(key, cell.usage)} / $limitText';
    final bandText = PlatformReportsCopy.bandLabel(band) +
        (cell.overridden ? ' — ${S.platformUsageOverridden}' : '');
    final lifecycle = row.lifecycle.valueOrNull;
    final ink3 = context.c.ink3;
    return ReportDenseTableRow(
      rowKey: Key('usage-row-${row.tenant.id}'),
      name: row.tenant.displayName,
      lifecycleChip: lifecycle == null || lifecycle == SaasTenantStatus.active
          ? null
          : StatusChip(
              kind: tenantLifecycleStatusKind(lifecycle),
              label: tenantLifecycleStatusLabel(lifecycle),
            ),
      cells: [
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            usageText,
            style: TextStyle(color: ink3, fontSize: 12),
            textAlign: TextAlign.start,
          ),
        ),
        Text(bandText, style: TextStyle(color: ink3, fontSize: 12)),
      ],
      semanticLabel: '${row.tenant.displayName}، $usageText، $bandText',
      onTap: () => context.push(SaasTenantRoutes.detail(row.tenant.id)),
    );
  }

  static int _filterCount(UsageLimitsReportQuery q) => [
        q.bands.isNotEmpty,
        q.plan != null,
        q.lifecycles.isNotEmpty,
      ].where((v) => v).length;

  List<Widget> _chips(UsageLimitsReportQuery q) => [
        for (final band in q.bands)
          InputChip(
            label: Text(PlatformReportsCopy.bandLabel(band)),
            onDeleted: () => _setQuery(UsageLimitsReportQuery(
              limitKey: q.limitKey,
              bands: {...q.bands}..remove(band),
              plan: q.plan,
              lifecycles: q.lifecycles,
              limit: q.limit,
            )),
          ),
        for (final lifecycle in q.lifecycles)
          InputChip(
            label: Text(tenantLifecycleStatusLabel(lifecycle)),
            onDeleted: () => _setQuery(UsageLimitsReportQuery(
              limitKey: q.limitKey,
              bands: q.bands,
              plan: q.plan,
              lifecycles: {...q.lifecycles}..remove(lifecycle),
              limit: q.limit,
            )),
          ),
        if (q.plan != null)
          InputChip(
            label: Text(
              q.plan is PlatformReportNoPlanFilter
                  ? S.platformReportNoPlan
                  : (q.plan as PlatformReportPlanIdFilter).planId,
            ),
            onDeleted: () => _setQuery(UsageLimitsReportQuery(
              limitKey: q.limitKey,
              bands: q.bands,
              lifecycles: q.lifecycles,
              limit: q.limit,
            )),
          ),
      ];
}

class _SkeletonBody extends StatelessWidget {
  const _SkeletonBody({super.key});
  @override
  Widget build(BuildContext context) => const Column(children: [
        Skeleton(height: 64),
        SizedBox(height: AppSpacing.md),
        Skeleton(height: 64),
        SizedBox(height: AppSpacing.md),
        SkeletonRow(),
        SizedBox(height: AppSpacing.md),
        SkeletonRow(),
      ]);
}

class _LimitKeyPillRow extends StatelessWidget {
  const _LimitKeyPillRow({required this.selected, required this.onSelect});
  final PlanLimitKey? selected;
  final ValueChanged<PlanLimitKey?> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ChoicePill(
          key: const Key('usage-limit-key-all'),
          label: S.platformReportFiltersAll,
          selected: selected == null,
          onTap: () => onSelect(null),
        ),
        for (final key in PlanLimitKey.values)
          ChoicePill(
            key: Key('usage-limit-key-${key.wire}'),
            label: planLimitLabel(key),
            selected: selected == key,
            onTap: () => onSelect(key),
          ),
      ],
    );
  }
}

/// The ≥900 dp alternative to stacking six [ReportBreakdownSection]s: the
/// same per-key band counts as a small table (§K.5 — "small keys × bands
/// table"), one row per limit key, one column per band. Every cell still
/// carries its own numeric label; colour only supplements it (§18/§36).
class _UsageKeyBandTable extends StatelessWidget {
  const _UsageKeyBandTable({required this.summary});
  final UsageLimitsReportSummary summary;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                const Expanded(flex: 3, child: SizedBox.shrink()),
                for (final band in UsageLimitBand.values)
                  Expanded(
                    flex: 2,
                    child: Text(
                      PlatformReportsCopy.bandLabel(band),
                      style: t.labelSmall?.copyWith(
                        color: c.ink3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          for (final key in PlanLimitKey.values) ...[
            _UsageKeyBandRow(limitKey: key, breakdown: summary.byKey[key]!),
            Divider(height: 1, color: c.line),
          ],
        ],
      ),
    );
  }
}

class _UsageKeyBandRow extends StatelessWidget {
  const _UsageKeyBandRow({required this.limitKey, required this.breakdown});
  final PlanLimitKey limitKey;
  final PlatformReportBreakdown<UsageLimitBand> breakdown;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final keyLabel = planLimitLabel(limitKey);
    final parts = [
      for (final band in UsageLimitBand.values)
        '${PlatformReportsCopy.bandLabel(band)}: ${breakdown[band]}',
    ];
    return Semantics(
      label: '$keyLabel: ${parts.join('، ')}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(flex: 3, child: Text(keyLabel, style: t.bodyMedium)),
              for (final band in UsageLimitBand.values)
                Expanded(
                  flex: 2,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '${breakdown[band]}',
                      style: TextStyle(
                        color: reportKindColor(
                          context,
                          PlatformReportsCopy.bandKind(band),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageRowTile extends StatelessWidget {
  const _UsageRowTile({required this.row, required this.selectedKey});
  final UsageLimitsReportRow row;
  final PlanLimitKey? selectedKey;

  (PlanLimitKey, UsageLimitCell) _cellFor() {
    final key = selectedKey ??
        row.cells.entries
            .reduce((a, b) =>
                a.value.band.severity >= b.value.band.severity ? a : b)
            .key;
    return (key, row.cells[key]!);
  }

  @override
  Widget build(BuildContext context) {
    final (key, cell) = _cellFor();
    final band = row.bandFor(selectedKey);
    final limitText =
        cell.limit == null ? '—' : formatLimitValue(key, cell.limit!);
    final factsParts = [
      '${planLimitLabel(key)}: ${formatLimitValue(key, cell.usage)} / $limitText',
      PlatformReportsCopy.bandLabel(band),
      if (cell.overridden) S.platformUsageOverridden,
    ];
    final lifecycle = row.lifecycle.valueOrNull;
    return ReportRowTile(
      key: Key('usage-row-${row.tenant.id}'),
      name: row.tenant.displayName,
      lifecycleChip: lifecycle == null || lifecycle == SaasTenantStatus.active
          ? null
          : StatusChip(
              kind: tenantLifecycleStatusKind(lifecycle),
              label: tenantLifecycleStatusLabel(lifecycle),
            ),
      // A painted separator rather than ` · `: these facts are dates and
      // figures, and the Arabic-Indic zero is itself a raised dot (P1-11).
      facts: PlatformMeta(
        parts: [for (final fact in factsParts) PlatformMetaText(fact)],
      ),
      semanticLabel: '${row.tenant.displayName}، ${factsParts.join('، ')}',
      onTap: () => context.push(SaasTenantRoutes.detail(row.tenant.id)),
    );
  }
}

class _UsageFilterForm extends StatelessWidget {
  const _UsageFilterForm({required this.query, required this.onChange});
  final UsageLimitsReportQuery query;
  final ValueChanged<UsageLimitsReportQuery> onChange;

  UsageLimitsReportQuery _copy({
    Set<UsageLimitBand>? bands,
    Object? plan = _unset,
    Set<SaasTenantStatus>? lifecycles,
  }) =>
      UsageLimitsReportQuery(
        limitKey: query.limitKey,
        bands: bands ?? query.bands,
        plan: identical(plan, _unset)
            ? query.plan
            : plan as PlatformReportPlanFilter?,
        lifecycles: lifecycles ?? query.lifecycles,
        limit: query.limit,
      );

  static const _unset = Object();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('الحالة مقابل الحد', style: t.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final band in UsageLimitBand.values)
              ChoicePill(
                key: Key('usage-filter-band-${band.wire}'),
                label: PlatformReportsCopy.bandLabel(band),
                selected: query.bands.contains(band),
                onTap: () {
                  final next = {...query.bands};
                  next.contains(band) ? next.remove(band) : next.add(band);
                  onChange(_copy(bands: next));
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('حالة الفريق', style: t.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final lifecycle in kReportableLifecycleStatuses)
              ChoicePill(
                key: Key('usage-filter-lifecycle-${lifecycle.wire}'),
                label: tenantLifecycleStatusLabel(lifecycle),
                selected: query.lifecycles.contains(lifecycle),
                onTap: () {
                  final next = {...query.lifecycles};
                  next.contains(lifecycle)
                      ? next.remove(lifecycle)
                      : next.add(lifecycle);
                  onChange(_copy(lifecycles: next));
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('الخطة', style: t.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        ChoicePill(
          key: const Key('usage-filter-no-plan'),
          label: S.platformReportNoPlan,
          selected: query.plan is PlatformReportNoPlanFilter,
          onTap: () => onChange(_copy(
            plan: query.plan is PlatformReportNoPlanFilter
                ? null
                : const PlatformReportPlanFilter.noPlan(),
          )),
        ),
      ],
    );
  }
}
