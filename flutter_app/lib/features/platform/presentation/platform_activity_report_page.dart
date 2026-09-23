import '../../../core/widgets/forward_chevron.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/format/app_date.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/clock.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../l10n/strings.dart';
import '../../../core/motion/animated_counter.dart';
import '../../settings/presentation/widgets/settings_widgets.dart';
import '../data/platform_reports_providers.dart';
import '../domain/platform_audit_models.dart';
import '../domain/platform_report_datasets.dart';
import '../domain/platform_report_models.dart';
import 'platform_audit_copy.dart';
import 'platform_operations_routes.dart';
import 'platform_reports_copy.dart';
import 'widgets/platform_report_widgets.dart';

/// `/platform/reports/platform_activity` — Point 13A §B row 4. The one period
/// report; it has no rows and no pagination (`paginatedRows: false`).
class PlatformActivityReportPage extends ConsumerStatefulWidget {
  const PlatformActivityReportPage({super.key});

  @override
  ConsumerState<PlatformActivityReportPage> createState() =>
      _PlatformActivityReportPageState();
}

class _PlatformActivityReportPageState
    extends ConsumerState<PlatformActivityReportPage> {
  PlatformActivityReportQuery? _query;
  bool _refreshing = false;

  PlatformActivityReportQuery _queryOf(DateTime now) =>
      _query ??= PlatformActivityReportQuery.defaultAt(now);

  void _setQuery(PlatformActivityReportQuery next) {
    if (next == _query) return;
    setState(() => _query = next);
  }

  Future<void> _refresh(PlatformActivityReportQuery query) async {
    setState(() => _refreshing = true);
    ref.invalidate(platformActivityReportProvider(query));
    await ref.read(platformActivityReportProvider(query).future);
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _openFilters(PlatformActivityReportQuery query) async {
    final now = ref.read(clockProvider)();
    final next = await showReportFilterSheet<PlatformActivityReportQuery>(
      context,
      title:
          '${PlatformReportsCopy.title(PlatformReportType.platformActivity)} · ${S.platformReportFiltersButton}',
      initial: query,
      builder: (context, q, onChange) =>
          _ActivityFilterForm(query: q, now: now, onChange: onChange),
      cleared: () => PlatformActivityReportQuery.defaultAt(now),
    );
    if (next != null) _setQuery(next);
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.read(clockProvider)();
    final query = _queryOf(now);
    final async = ref.watch(platformActivityReportProvider(query));
    final count = query.category == null ? 0 : 1;

    return PlatformReportScaffold(
      title: PlatformReportsCopy.title(PlatformReportType.platformActivity),
      onRefresh: () => _refresh(query),
      refreshing: _refreshing || (async.isLoading && async.hasValue),
      filterCount: count,
      onOpenFilters: () => unawaited(_openFilters(query)),
      filterPanel: _ActivityFilterForm(
        query: query,
        now: now,
        onChange: _setQuery,
      ),
      filterChips: [
        if (query.category != null)
          InputChip(
            label: Text(AuditCopy.category(query.category!)),
            onDeleted: () => _setQuery(PlatformActivityReportQuery(
              range: query.range,
            )),
          ),
      ],
      onClearFilters: count == 0
          ? null
          : () => _setQuery(PlatformActivityReportQuery(range: query.range)),
      bodyBuilder: (wide) => [_body(async, query, wide)],
    );
  }

  Widget _body(
    AsyncValue<Result<PlatformActivityReport>> async,
    PlatformActivityReportQuery query,
    bool wide,
  ) {
    if (!async.hasValue) {
      return const _SkeletonBody(key: Key('activity-loading'));
    }
    if (async.hasError) {
      return ErrorStateView(
        key: const Key('activity-failure'),
        title: S.platformReportFailureTitle,
        body: S.platformReportFailureBody,
        onRetry: () => _refresh(query),
      );
    }
    final result = async.requireValue;
    final viewState = platformReportViewState(result);
    final freshness = platformReportFreshness(result);
    final report = switch (result) {
      Success<PlatformActivityReport>(:final data) => data,
      Offline<PlatformActivityReport>(:final cached) => cached,
      Failure<PlatformActivityReport>() => null,
    };

    switch (viewState) {
      case PlatformReportViewState.offlineNoData:
        return EmptyState(
          key: const Key('activity-offline'),
          icon: Icons.cloud_off_rounded,
          title: S.platformReportOfflineNoDataTitle,
          body: S.platformReportOfflineNoDataBody,
          actionLabel: S.platformReportRetry,
          onAction: () => _refresh(query),
        );
      case PlatformReportViewState.notPermitted:
        return const EmptyState(
          key: Key('activity-not-permitted'),
          icon: Icons.lock_outline_rounded,
          title: S.platformReportNotPermittedTitle,
          body: '',
        );
      case PlatformReportViewState.failure:
        return ErrorStateView(
          key: const Key('activity-failure'),
          title: S.platformReportFailureTitle,
          body: S.platformReportFailureBody,
          onRetry: () => _refresh(query),
        );
      case PlatformReportViewState.empty:
      case PlatformReportViewState.filteredEmpty:
      case PlatformReportViewState.loaded:
        break;
    }

    final loadedReport = report!;
    final range = loadedReport.query.range;
    return Column(
      key: const Key('activity-loaded'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportProvenanceLine(
          lines: [
            '${AppDate.dayMonthYear(range.firstLocalDay)} – '
                '${AppDate.dayMonthYear(range.lastLocalDay)} — '
                '${S.platformReportLocalTimeNote} · ${S.platformReportSourceAudit}',
          ],
          stale: freshness == PlatformReportFreshness.stale,
          offlineCached: freshness == PlatformReportFreshness.offlineCached,
        ),
        const SizedBox(height: AppSpacing.lg),
        if (loadedReport.isCoveragePartial)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Text(
              'السجل متاح منذ '
              '${AppDate.dayMonthYear(loadedReport.evidenceAvailableFrom!.toLocal())}'
              ' فقط؛ الأعداد قبل ذلك غير متاحة.',
              style: TextStyle(color: context.c.warn),
            ),
          ),
        if (viewState == PlatformReportViewState.filteredEmpty)
          EmptyState(
            key: const Key('activity-filtered-empty'),
            icon: Icons.filter_alt_off_outlined,
            title: S.platformReportFilteredEmptyTitle,
            body: S.platformReportFilteredEmptyBody,
            actionLabel: S.platformReportFiltersClearAll,
            onAction: () =>
                _setQuery(PlatformActivityReportQuery(range: query.range)),
          )
        else if (viewState == PlatformReportViewState.empty)
          EmptyState(
            key: const Key('activity-empty'),
            icon: Icons.timeline_outlined,
            title: S.platformReportEmptyActivityTitle,
            body: S.platformReportEmptyActivityBody,
            actionLabel: S.platformReportWidenRange,
            onAction: () => unawaited(_openFilters(query)),
          )
        else ...[
          if (wide)
            _CategoryGroupGrid(report: loadedReport)
          else
            for (final category in PlatformAuditCategory.values)
              if (category != PlatformAuditCategory.unknown)
                _CategoryGroup(report: loadedReport, category: category),
          if (loadedReport.byAction.unsupported > 0)
            ReportBreakdownSection(
              title: S.platformReportOtherActions,
              total: loadedReport.total,
              rows: [
                ReportBreakdownRow(
                  label: S.platformReportOtherActions,
                  count: loadedReport.byAction.unsupported,
                ),
              ],
            ),
        ],
      ],
    );
  }
}

class _SkeletonBody extends StatelessWidget {
  const _SkeletonBody({super.key});
  @override
  Widget build(BuildContext context) => const Column(children: [
        Skeleton(height: 64),
        SizedBox(height: AppSpacing.md),
        Skeleton(height: 64),
        SizedBox(height: AppSpacing.md),
        Skeleton(height: 64),
      ]);
}

/// The ≥900 dp alternative to a single stacked column of category groups:
/// the same groups (same totals, same action rows, same drill-down), laid
/// out two to a row so the wide reading column is not just a narrower page
/// stretched taller. Never a fake event table — Point 13A never stored
/// individual events for a UI to list.
class _CategoryGroupGrid extends StatelessWidget {
  const _CategoryGroupGrid({required this.report});
  final PlatformActivityReport report;

  @override
  Widget build(BuildContext context) {
    final categories = [
      for (final category in PlatformAuditCategory.values)
        if (category != PlatformAuditCategory.unknown) category,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - AppSpacing.lg) / 2;
        return Wrap(
          spacing: AppSpacing.lg,
          children: [
            for (final category in categories)
              SizedBox(
                width: columnWidth,
                child: _CategoryGroup(report: report, category: category),
              ),
          ],
        );
      },
    );
  }
}

class _CategoryGroup extends StatelessWidget {
  const _CategoryGroup({required this.report, required this.category});
  final PlatformActivityReport report;
  final PlatformAuditCategory category;

  @override
  Widget build(BuildContext context) {
    final actions = [
      for (final action in kReportableAuditActions)
        if (action.category == category) action,
    ];
    final total = report.byCategory[category];
    final isEmergency = category == PlatformAuditCategory.emergencyAccess;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  AuditCopy.category(category),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text('$total'),
              ),
            ],
          ),
          if (isEmergency && total > 0) ...[
            const SizedBox(height: 2),
            Text(
              S.platformActivityGovernanceNote,
              style: TextStyle(color: context.c.ink3, fontSize: 12),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          for (final action in actions)
            _ActionRow(report: report, action: action),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.report, required this.action});
  final PlatformActivityReport report;
  final PlatformAuditAction action;

  @override
  Widget build(BuildContext context) {
    final count = report.byAction[action];
    final label = AuditCopy.action(action);
    final interactive = count > 0;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text('$count'),
          ),
          if (interactive) ...[
            const SizedBox(width: AppSpacing.xs),
            const ForwardChevron(size: 18),
          ],
        ],
      ),
    );
    if (!interactive) return row;
    return Semantics(
      button: true,
      label: '$label، $count، ${S.platformReportOpenTenant}',
      child: InkWell(
        key: Key('activity-action-${action.wire}'),
        onTap: () => context.push(
          PlatformOperationsRoutes.audit,
          extra: report.auditQueryFor(action),
        ),
        child: ExcludeSemantics(child: row),
      ),
    );
  }
}

class _ActivityFilterForm extends StatelessWidget {
  const _ActivityFilterForm({
    required this.query,
    required this.now,
    required this.onChange,
  });
  final PlatformActivityReportQuery query;
  final DateTime now;
  final ValueChanged<PlatformActivityReportQuery> onChange;

  void _preset(int days) {
    final today = now.toLocal();
    final first = DateTime(today.year, today.month, today.day - (days - 1));
    onChange(PlatformActivityReportQuery(
      range: PlatformReportRange.localDays(first: first, last: today),
      category: query.category,
    ));
  }

  Future<void> _pickRange(BuildContext context) async {
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
      currentDate: today,
      initialDateRange: DateTimeRange(
        start: query.range.firstLocalDay,
        end: query.range.lastLocalDay,
      ),
    );
    if (picked == null) return;
    final days = picked.end.difference(picked.start).inDays + 1;
    if (days > kPlatformReportMaxRangeDays) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'أطول فترة مسموحة '
            '${toArabicIndic('$kPlatformReportMaxRangeDays')} يوماً.',
          ),
        ));
      }
      return;
    }
    onChange(PlatformActivityReportQuery(
      range:
          PlatformReportRange.localDays(first: picked.start, last: picked.end),
      category: query.category,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('الفترة', style: t.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (label, days) in const [
              ('٧ أيام', 7),
              ('٣٠ يوماً', 30),
              ('٩٠ يوماً', 90),
            ])
              OutlinedButton(
                key: Key('activity-preset-$days'),
                onPressed: () => _preset(days),
                child: Text(label),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          key: const Key('activity-custom-range'),
          onPressed: () => _pickRange(context),
          icon: const Icon(Icons.date_range_outlined),
          label: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              '${AppDate.dayMonthYear(query.range.firstLocalDay)} – '
              '${AppDate.dayMonthYear(query.range.lastLocalDay)}',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('الفئة', style: t.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            ChoicePill(
              key: const Key('activity-filter-category-all'),
              label: S.platformReportFiltersAll,
              selected: query.category == null,
              onTap: () =>
                  onChange(PlatformActivityReportQuery(range: query.range)),
            ),
            for (final category in PlatformAuditCategory.values)
              if (category != PlatformAuditCategory.unknown)
                ChoicePill(
                  key: Key('activity-filter-category-${category.wire}'),
                  label: AuditCopy.category(category),
                  selected: query.category == category,
                  onTap: () => onChange(PlatformActivityReportQuery(
                    range: query.range,
                    category: category,
                  )),
                ),
          ],
        ),
      ],
    );
  }
}
