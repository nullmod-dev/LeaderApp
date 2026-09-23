import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/access/saas_tenant_status.dart';
import '../../../core/format/app_date.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/clock.dart';
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

/// `/platform/reports/subscriptions` — Point 13A §B row 1.
class PlatformSubscriptionsReportPage extends ConsumerStatefulWidget {
  const PlatformSubscriptionsReportPage({super.key});

  @override
  ConsumerState<PlatformSubscriptionsReportPage> createState() =>
      _PlatformSubscriptionsReportPageState();
}

class _PlatformSubscriptionsReportPageState
    extends ConsumerState<PlatformSubscriptionsReportPage> {
  SubscriptionReportQuery query = SubscriptionReportQuery();

  late final rows = PlatformReportRowsController<SubscriptionReportQuery,
      SubscriptionReport, SubscriptionReportRow>(
    loadPage: (q) =>
        ref.read(platformReportsRepositoryProvider).loadSubscriptions(q),
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

  void _setQuery(SubscriptionReportQuery next) {
    if (next == query) return;
    setState(() => query = next);
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    ref.invalidate(subscriptionReportProvider(query));
    await ref.read(subscriptionReportProvider(query).future);
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _openFilters() async {
    final next = await showReportFilterSheet<SubscriptionReportQuery>(
      context,
      title:
          '${PlatformReportsCopy.title(PlatformReportType.subscriptions)} · ${S.platformReportFiltersButton}',
      initial: query,
      builder: (context, q, onChange) =>
          _SubscriptionFilterForm(query: q, onChange: onChange),
      cleared: SubscriptionReportQuery.new,
    );
    if (next != null) _setQuery(next);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(subscriptionReportProvider(query));
    final count = _filterCount(query);

    return PlatformReportScaffold(
      title: PlatformReportsCopy.title(PlatformReportType.subscriptions),
      onRefresh: _refresh,
      refreshing: _refreshing || (async.isLoading && async.hasValue),
      filterCount: count,
      onOpenFilters: _openFilters,
      filterPanel: _SubscriptionFilterForm(query: query, onChange: _setQuery),
      filterChips: _chips(query),
      onClearFilters:
          count == 0 ? null : () => _setQuery(SubscriptionReportQuery()),
      bodyBuilder: (wide) => [_body(async, wide)],
    );
  }

  Widget _body(AsyncValue<Result<SubscriptionReport>> async, bool wide) {
    if (!async.hasValue) {
      return const _SkeletonBody(key: Key('subscriptions-loading'));
    }
    if (async.hasError) {
      return ErrorStateView(
        key: const Key('subscriptions-failure'),
        title: S.platformReportFailureTitle,
        body: S.platformReportFailureBody,
        onRetry: _refresh,
      );
    }
    final result = async.requireValue;
    final viewState = platformReportViewState(result);
    final freshness = platformReportFreshness(result);
    final report = switch (result) {
      Success<SubscriptionReport>(:final data) => data,
      Offline<SubscriptionReport>(:final cached) => cached,
      Failure<SubscriptionReport>() => null,
    };

    switch (viewState) {
      case PlatformReportViewState.offlineNoData:
        return EmptyState(
          key: const Key('subscriptions-offline'),
          icon: Icons.cloud_off_rounded,
          title: S.platformReportOfflineNoDataTitle,
          body: S.platformReportOfflineNoDataBody,
          actionLabel: S.platformReportRetry,
          onAction: _refresh,
        );
      case PlatformReportViewState.notPermitted:
        return const EmptyState(
          key: Key('subscriptions-not-permitted'),
          icon: Icons.lock_outline_rounded,
          title: S.platformReportNotPermittedTitle,
          body: '',
        );
      case PlatformReportViewState.failure:
        return ErrorStateView(
          key: const Key('subscriptions-failure'),
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
      key: const Key('subscriptions-loaded'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportProvenanceLine(
          lines: [
            'لقطة حالية — حتى ${AppDate.dayMonthTime(loadedReport.meta.generatedAt.toLocal())}',
            S.platformReportScopeNote,
          ],
          stale: freshness == PlatformReportFreshness.stale,
          offlineCached: freshness == PlatformReportFreshness.offlineCached,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (viewState == PlatformReportViewState.filteredEmpty)
          EmptyState(
            key: const Key('subscriptions-filtered-empty'),
            icon: Icons.filter_alt_off_outlined,
            title: S.platformReportFilteredEmptyTitle,
            body: S.platformReportFilteredEmptyBody,
            actionLabel: S.platformReportFiltersClearAll,
            onAction: () => _setQuery(SubscriptionReportQuery()),
          )
        else if (viewState == PlatformReportViewState.empty)
          const EmptyState(
            key: Key('subscriptions-empty'),
            icon: Icons.workspace_premium_outlined,
            title: S.platformReportEmptyTeamsTitle,
            body: S.platformReportEmptyTeamsBody,
          )
        else ...[
          ReportBreakdownSection(
            title: 'حسب حالة الاشتراك',
            total: loadedReport.summary.tenantCount,
            rows: [
              for (final status in SubscriptionStatus.values)
                ReportBreakdownRow(
                  label: subscriptionStatusLabel(status),
                  count: loadedReport.summary.byStatus[status],
                  kind: subscriptionStatusKind(status),
                ),
              if (loadedReport.summary.byStatus.unsupported > 0)
                ReportBreakdownRow(
                  label: S.platformReportUnsupportedValuesNote,
                  count: loadedReport.summary.byStatus.unsupported,
                ),
            ],
          ),
          ReportBreakdownSection(
            title: 'حسب حالة الفريق',
            total: loadedReport.summary.tenantCount,
            rows: [
              for (final lifecycle in kReportableLifecycleStatuses)
                ReportBreakdownRow(
                  label: tenantLifecycleStatusLabel(lifecycle),
                  count: loadedReport.summary.byLifecycle[lifecycle],
                  kind: tenantLifecycleStatusKind(lifecycle),
                ),
              if (loadedReport.summary.byLifecycle.unsupported > 0)
                ReportBreakdownRow(
                  label: S.platformReportUnsupportedValuesNote,
                  count: loadedReport.summary.byLifecycle.unsupported,
                ),
            ],
          ),
          ReportBreakdownSection(
            title: 'حسب الخطة',
            total: loadedReport.summary.tenantCount,
            rows: [
              for (final bucket in loadedReport.summary.byPlan)
                ReportBreakdownRow(
                  label: bucket.plan?.name ?? S.platformReportNoPlan,
                  count: bucket.count,
                  kind:
                      bucket.plan == null ? StatusKind.muted : StatusKind.info,
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
                S.platformReportColumnSubscriptionStatus,
                S.platformReportColumnPlan,
                S.platformReportColumnDate,
              ],
              columnFlex: const [3, 2, 2, 3],
              rows: [
                for (final row in rowsState.items) _denseRow(row),
              ],
            )
          else
            for (final row in rowsState.items) ...[
              _SubscriptionRowTile(row: row),
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

  ReportDenseTableRow _denseRow(SubscriptionReportRow row) {
    final status = row.status.valueOrNull;
    final dateLabel = PlatformReportsCopy.subscriptionRelevantDateLabel(status);
    final statusText = row.status.isSupported
        ? subscriptionStatusLabel(status!)
        : S.platformReportUnsupportedValuesNote;
    final planText = row.plan?.name ?? S.platformReportNoPlan;
    final dateText = (dateLabel != null && row.relevantDate != null)
        ? '$dateLabel ${AppDate.dayMonthYear(row.relevantDate!.toLocal())}'
        : '—';
    final lifecycle = row.lifecycle.valueOrNull;
    final ink3 = context.c.ink3;
    return ReportDenseTableRow(
      rowKey: Key('subscription-row-${row.tenant.id}'),
      name: row.tenant.displayName,
      lifecycleChip: lifecycle == null || lifecycle == SaasTenantStatus.active
          ? null
          : StatusChip(
              kind: tenantLifecycleStatusKind(lifecycle),
              label: tenantLifecycleStatusLabel(lifecycle),
            ),
      cells: [
        Text(statusText, style: TextStyle(color: ink3, fontSize: 12)),
        Text(planText, style: TextStyle(color: ink3, fontSize: 12)),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            dateText,
            style: TextStyle(color: ink3, fontSize: 12),
            textAlign: TextAlign.start,
          ),
        ),
      ],
      semanticLabel: '${row.tenant.displayName}، $statusText، $planText'
          '${dateText == '—' ? '' : '، $dateText'}',
      onTap: () => context.push(SaasTenantRoutes.detail(row.tenant.id)),
    );
  }

  static int _filterCount(SubscriptionReportQuery q) => [
        q.statuses.isNotEmpty,
        q.plan != null,
        q.lifecycles.isNotEmpty,
        q.dueBefore != null,
      ].where((v) => v).length;

  List<Widget> _chips(SubscriptionReportQuery q) => [
        for (final status in q.statuses)
          InputChip(
            label: Text(subscriptionStatusLabel(status)),
            onDeleted: () => _setQuery(SubscriptionReportQuery(
              statuses: {...q.statuses}..remove(status),
              plan: q.plan,
              lifecycles: q.lifecycles,
              dueBefore: q.dueBefore,
              limit: q.limit,
            )),
          ),
        for (final lifecycle in q.lifecycles)
          InputChip(
            label: Text(tenantLifecycleStatusLabel(lifecycle)),
            onDeleted: () => _setQuery(SubscriptionReportQuery(
              statuses: q.statuses,
              plan: q.plan,
              lifecycles: {...q.lifecycles}..remove(lifecycle),
              dueBefore: q.dueBefore,
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
            onDeleted: () => _setQuery(SubscriptionReportQuery(
              statuses: q.statuses,
              lifecycles: q.lifecycles,
              dueBefore: q.dueBefore,
              limit: q.limit,
            )),
          ),
        if (q.dueBefore != null)
          InputChip(
            label: Text(
              'قبل ${AppDate.dayMonthYear(q.dueBefore!.toLocal())}',
            ),
            onDeleted: () => _setQuery(SubscriptionReportQuery(
              statuses: q.statuses,
              plan: q.plan,
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

class _SubscriptionRowTile extends StatelessWidget {
  const _SubscriptionRowTile({required this.row});
  final SubscriptionReportRow row;

  @override
  Widget build(BuildContext context) {
    final status = row.status.valueOrNull;
    final dateLabel = PlatformReportsCopy.subscriptionRelevantDateLabel(status);
    final factsParts = [
      row.status.isSupported
          ? subscriptionStatusLabel(status!)
          : S.platformReportUnsupportedValuesNote,
      row.plan?.name ?? S.platformReportNoPlan,
      if (dateLabel != null && row.relevantDate != null)
        '$dateLabel ${AppDate.dayMonthYear(row.relevantDate!.toLocal())}',
    ];
    final lifecycle = row.lifecycle.valueOrNull;
    return ReportRowTile(
      key: Key('subscription-row-${row.tenant.id}'),
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

class _SubscriptionFilterForm extends StatelessWidget {
  const _SubscriptionFilterForm({required this.query, required this.onChange});
  final SubscriptionReportQuery query;
  final ValueChanged<SubscriptionReportQuery> onChange;

  SubscriptionReportQuery _copy({
    Set<SubscriptionStatus>? statuses,
    Object? plan = _unset,
    Set<SaasTenantStatus>? lifecycles,
    Object? dueBefore = _unset,
  }) =>
      SubscriptionReportQuery(
        statuses: statuses ?? query.statuses,
        plan: identical(plan, _unset)
            ? query.plan
            : plan as PlatformReportPlanFilter?,
        lifecycles: lifecycles ?? query.lifecycles,
        dueBefore: identical(dueBefore, _unset)
            ? query.dueBefore
            : dueBefore as DateTime?,
        limit: query.limit,
      );

  static const _unset = Object();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('حالة الاشتراك', style: t.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final status in SubscriptionStatus.values)
              ChoicePill(
                key: Key('subscription-filter-status-${status.wire}'),
                label: subscriptionStatusLabel(status),
                selected: query.statuses.contains(status),
                onTap: () {
                  final next = {...query.statuses};
                  next.contains(status)
                      ? next.remove(status)
                      : next.add(status);
                  onChange(_copy(statuses: next));
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
                key: Key('subscription-filter-lifecycle-${lifecycle.wire}'),
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
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ChoicePill(
              key: const Key('subscription-filter-no-plan'),
              label: S.platformReportNoPlan,
              selected: query.plan is PlatformReportNoPlanFilter,
              onTap: () => onChange(_copy(
                plan: query.plan is PlatformReportNoPlanFilter
                    ? null
                    : const PlatformReportPlanFilter.noPlan(),
              )),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const Key('subscription-filter-plan-id'),
          textDirection: TextDirection.ltr,
          controller: TextEditingController(
            text: query.plan is PlatformReportPlanIdFilter
                ? (query.plan as PlatformReportPlanIdFilter).planId
                : '',
          ),
          decoration: const InputDecoration(labelText: 'معرّف الخطة (اختياري)'),
          onSubmitted: (value) {
            final trimmed = value.trim();
            onChange(_copy(
              plan: trimmed.isEmpty
                  ? null
                  : PlatformReportPlanFilter.plan(trimmed),
            ));
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('الاستحقاق قبل تاريخ', style: t.titleSmall),
        Consumer(builder: (context, ref, _) {
          final now = ref.read(clockProvider)();
          return Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                key: const Key('subscription-filter-due-before'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: query.dueBefore?.toLocal() ?? now,
                    currentDate: now,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 10),
                  );
                  if (picked != null) onChange(_copy(dueBefore: picked));
                },
                child: Text(
                  query.dueBefore == null
                      ? 'اختر تاريخاً (اختياري)'
                      : AppDate.dayMonthYear(query.dueBefore!.toLocal()),
                ),
              ),
              if (query.dueBefore != null)
                TextButton(
                  onPressed: () => onChange(_copy(dueBefore: null)),
                  child: const Text('مسح'),
                ),
            ],
          );
        }),
      ],
    );
  }
}
