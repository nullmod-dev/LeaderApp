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
import '../../tenant_feature/domain/tenant_feature_models.dart';
import '../data/platform_report_rows_controller.dart';
import '../data/platform_reports_providers.dart';
import '../domain/platform_report_datasets.dart';
import '../domain/platform_report_models.dart';
import 'platform_reports_copy.dart';
import 'saas_tenant_routes.dart';
import 'tenant_lifecycle_copy.dart';
import 'widgets/platform_report_widgets.dart';

/// `/platform/reports/feature_availability` — Point 13A §B row 3.
class PlatformFeatureAvailabilityReportPage extends ConsumerStatefulWidget {
  const PlatformFeatureAvailabilityReportPage({super.key});

  @override
  ConsumerState<PlatformFeatureAvailabilityReportPage> createState() =>
      _PlatformFeatureAvailabilityReportPageState();
}

class _PlatformFeatureAvailabilityReportPageState
    extends ConsumerState<PlatformFeatureAvailabilityReportPage> {
  FeatureAvailabilityReportQuery query = FeatureAvailabilityReportQuery();

  late final rows = PlatformReportRowsController<FeatureAvailabilityReportQuery,
      FeatureAvailabilityReport, FeatureAvailabilityRow>(
    loadPage: (q) =>
        ref.read(platformReportsRepositoryProvider).loadFeatureAvailability(q),
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

  void _setQuery(FeatureAvailabilityReportQuery next) {
    if (next == query) return;
    setState(() => query = next);
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    ref.invalidate(featureAvailabilityReportProvider(query));
    await ref.read(featureAvailabilityReportProvider(query).future);
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _openFilters() async {
    final next = await showReportFilterSheet<FeatureAvailabilityReportQuery>(
      context,
      title:
          '${PlatformReportsCopy.title(PlatformReportType.featureAvailability)} · ${S.platformReportFiltersButton}',
      initial: query,
      builder: (context, q, onChange) =>
          _FeatureFilterForm(query: q, onChange: onChange),
      cleared: FeatureAvailabilityReportQuery.new,
    );
    if (next != null) _setQuery(next);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(featureAvailabilityReportProvider(query));
    final count = _filterCount(query);

    return PlatformReportScaffold(
      title: PlatformReportsCopy.title(PlatformReportType.featureAvailability),
      onRefresh: _refresh,
      refreshing: _refreshing || (async.isLoading && async.hasValue),
      filterCount: count,
      onOpenFilters: _openFilters,
      filterPanel: _FeatureFilterForm(query: query, onChange: _setQuery),
      filterChips: _chips(query),
      onClearFilters:
          count == 0 ? null : () => _setQuery(FeatureAvailabilityReportQuery()),
      bodyBuilder: (wide) => [_body(async, wide)],
    );
  }

  Widget _body(AsyncValue<Result<FeatureAvailabilityReport>> async, bool wide) {
    if (!async.hasValue) {
      return const _SkeletonBody(key: Key('features-loading'));
    }
    if (async.hasError) {
      return ErrorStateView(
        key: const Key('features-failure'),
        title: S.platformReportFailureTitle,
        body: S.platformReportFailureBody,
        onRetry: _refresh,
      );
    }
    final result = async.requireValue;
    final viewState = platformReportViewState(result);
    final freshness = platformReportFreshness(result);
    final report = switch (result) {
      Success<FeatureAvailabilityReport>(:final data) => data,
      Offline<FeatureAvailabilityReport>(:final cached) => cached,
      Failure<FeatureAvailabilityReport>() => null,
    };

    switch (viewState) {
      case PlatformReportViewState.offlineNoData:
        return EmptyState(
          key: const Key('features-offline'),
          icon: Icons.cloud_off_rounded,
          title: S.platformReportOfflineNoDataTitle,
          body: S.platformReportOfflineNoDataBody,
          actionLabel: S.platformReportRetry,
          onAction: _refresh,
        );
      case PlatformReportViewState.notPermitted:
        return const EmptyState(
          key: Key('features-not-permitted'),
          icon: Icons.lock_outline_rounded,
          title: S.platformReportNotPermittedTitle,
          body: '',
        );
      case PlatformReportViewState.failure:
        return ErrorStateView(
          key: const Key('features-failure'),
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
      key: const Key('features-loaded'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportProvenanceLine(
          lines: [
            'لقطة حالية — حتى ${AppDate.dayMonthTime(loadedReport.meta.generatedAt.toLocal())}',
            S.platformReportScopeNote,
            if (loadedReport.hasUnsupportedFeatureKeys)
              S.platformReportUnsupportedFeatureKeysNote,
          ],
          stale: freshness == PlatformReportFreshness.stale,
          offlineCached: freshness == PlatformReportFreshness.offlineCached,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (viewState == PlatformReportViewState.filteredEmpty)
          EmptyState(
            key: const Key('features-filtered-empty'),
            icon: Icons.filter_alt_off_outlined,
            title: S.platformReportFilteredEmptyTitle,
            body: S.platformReportFilteredEmptyBody,
            actionLabel: S.platformReportFiltersClearAll,
            onAction: () => _setQuery(FeatureAvailabilityReportQuery()),
          )
        else if (viewState == PlatformReportViewState.empty)
          const EmptyState(
            key: Key('features-empty'),
            icon: Icons.toggle_on_outlined,
            title: S.platformReportEmptyTeamsTitle,
            body: S.platformReportEmptyTeamsBody,
          )
        else ...[
          for (final key in TenantFeatureKey.values)
            ReportBreakdownSection(
              title: PlatformReportsCopy.featureKeyLabel(key),
              total: loadedReport.summary.tenantCount,
              rows: [
                for (final state in TenantFeatureAvailability.values)
                  ReportBreakdownRow(
                    label: PlatformReportsCopy.featureAvailabilityLabel(state),
                    count: loadedReport.summary.byFeature[key]![state],
                    kind: PlatformReportsCopy.featureAvailabilityKind(state),
                  ),
                if (loadedReport.summary.byFeature[key]!.unsupported > 0)
                  ReportBreakdownRow(
                    label: S.platformReportUnsupportedValuesNote,
                    count: loadedReport.summary.byFeature[key]!.unsupported,
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
              columnLabels: [
                S.platformReportColumnTeam,
                for (final key in TenantFeatureKey.values)
                  PlatformReportsCopy.featureKeyLabel(key),
              ],
              columnFlex: [3, for (final _ in TenantFeatureKey.values) 2],
              rows: [
                for (final row in rowsState.items) _denseRow(row),
              ],
            )
          else
            for (final row in rowsState.items) ...[
              _FeatureRowTile(row: row),
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

  ReportDenseTableRow _denseRow(FeatureAvailabilityRow row) {
    final lifecycle = row.lifecycle.valueOrNull;
    final ink3 = context.c.ink3;
    final cellTexts = [
      for (final key in TenantFeatureKey.values)
        row.states[key]!.isSupported
            ? PlatformReportsCopy.featureAvailabilityLabel(
                row.states[key]!.valueOrNull!)
            : S.platformFeatureUnknownState,
    ];
    return ReportDenseTableRow(
      rowKey: Key('feature-row-${row.tenant.id}'),
      name: row.tenant.displayName,
      lifecycleChip: lifecycle == null || lifecycle == SaasTenantStatus.active
          ? null
          : StatusChip(
              kind: tenantLifecycleStatusKind(lifecycle),
              label: tenantLifecycleStatusLabel(lifecycle),
            ),
      cells: [
        for (final text in cellTexts)
          Text(text, style: TextStyle(color: ink3, fontSize: 12)),
      ],
      semanticLabel: '${row.tenant.displayName}، '
          '${[
        for (var i = 0; i < TenantFeatureKey.values.length; i++)
          '${PlatformReportsCopy.featureKeyLabel(TenantFeatureKey.values[i])}: ${cellTexts[i]}',
      ].join('، ')}',
      onTap: () => context.push(SaasTenantRoutes.detail(row.tenant.id)),
    );
  }

  static int _filterCount(FeatureAvailabilityReportQuery q) => [
        q.state != null,
        q.lifecycles.isNotEmpty,
      ].where((v) => v).length;

  List<Widget> _chips(FeatureAvailabilityReportQuery q) => [
        if (q.featureKey != null && q.state != null)
          InputChip(
            label: Text(
              '${PlatformReportsCopy.featureKeyLabel(q.featureKey!)}: '
              '${PlatformReportsCopy.featureAvailabilityLabel(q.state!)}',
            ),
            onDeleted: () => _setQuery(FeatureAvailabilityReportQuery(
              lifecycles: q.lifecycles,
              limit: q.limit,
            )),
          ),
        for (final lifecycle in q.lifecycles)
          InputChip(
            label: Text(tenantLifecycleStatusLabel(lifecycle)),
            onDeleted: () => _setQuery(FeatureAvailabilityReportQuery(
              featureKey: q.featureKey,
              state: q.state,
              lifecycles: {...q.lifecycles}..remove(lifecycle),
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

class _FeatureRowTile extends StatelessWidget {
  const _FeatureRowTile({required this.row});
  final FeatureAvailabilityRow row;

  @override
  Widget build(BuildContext context) {
    final lifecycle = row.lifecycle.valueOrNull;
    final chipTexts = [
      for (final key in TenantFeatureKey.values)
        '${PlatformReportsCopy.featureKeyLabel(key)}: '
            '${row.states[key]!.isSupported ? PlatformReportsCopy.featureAvailabilityLabel(row.states[key]!.valueOrNull!) : S.platformFeatureUnknownState}',
    ];
    return ReportRowTile(
      key: Key('feature-row-${row.tenant.id}'),
      name: row.tenant.displayName,
      lifecycleChip: lifecycle == null || lifecycle == SaasTenantStatus.active
          ? null
          : StatusChip(
              kind: tenantLifecycleStatusKind(lifecycle),
              label: tenantLifecycleStatusLabel(lifecycle),
            ),
      facts: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final text in chipTexts)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: context.c.surface2,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Text(text,
                  style: TextStyle(color: context.c.ink2, fontSize: 11)),
            ),
        ],
      ),
      semanticLabel: '${row.tenant.displayName}، ${chipTexts.join('، ')}',
      onTap: () => context.push(SaasTenantRoutes.detail(row.tenant.id)),
    );
  }
}

class _FeatureFilterForm extends StatelessWidget {
  const _FeatureFilterForm({required this.query, required this.onChange});
  final FeatureAvailabilityReportQuery query;
  final ValueChanged<FeatureAvailabilityReportQuery> onChange;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('الميزة', style: t.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ChoicePill(
              key: const Key('feature-filter-key-all'),
              label: S.platformReportFiltersAll,
              selected: query.featureKey == null,
              onTap: () => onChange(FeatureAvailabilityReportQuery(
                lifecycles: query.lifecycles,
                limit: query.limit,
              )),
            ),
            for (final key in TenantFeatureKey.values)
              ChoicePill(
                key: Key('feature-filter-key-${key.wire}'),
                label: PlatformReportsCopy.featureKeyLabel(key),
                selected: query.featureKey == key,
                onTap: () => onChange(FeatureAvailabilityReportQuery(
                  featureKey: key,
                  lifecycles: query.lifecycles,
                  limit: query.limit,
                )),
              ),
          ],
        ),
        if (query.featureKey != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('الحالة', style: t.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final state in TenantFeatureAvailability.values)
                ChoicePill(
                  key: Key('feature-filter-state-${state.wire}'),
                  label: PlatformReportsCopy.featureAvailabilityLabel(state),
                  selected: query.state == state,
                  onTap: () => onChange(FeatureAvailabilityReportQuery(
                    featureKey: query.featureKey,
                    state: query.state == state ? null : state,
                    lifecycles: query.lifecycles,
                    limit: query.limit,
                  )),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text('حالة الفريق', style: t.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final lifecycle in kReportableLifecycleStatuses)
              ChoicePill(
                key: Key('feature-filter-lifecycle-${lifecycle.wire}'),
                label: tenantLifecycleStatusLabel(lifecycle),
                selected: query.lifecycles.contains(lifecycle),
                onTap: () {
                  final next = {...query.lifecycles};
                  next.contains(lifecycle)
                      ? next.remove(lifecycle)
                      : next.add(lifecycle);
                  onChange(FeatureAvailabilityReportQuery(
                    featureKey: query.featureKey,
                    state: query.state,
                    lifecycles: next,
                    limit: query.limit,
                  ));
                },
              ),
          ],
        ),
      ],
    );
  }
}
