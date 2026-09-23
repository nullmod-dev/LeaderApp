import 'package:flutter/material.dart';

import '../../../../core/motion/animated_counter.dart' show toArabicIndic;
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/refresh_indicator.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../l10n/strings.dart';
import 'platform_page.dart';

/// Point 13B — the shared shape of a report page: header, provenance, filter
/// affordance, summary, rows, paging and states. The four report pages differ
/// in what fills each slot (§K.7 is explicit that the row shape must not be
/// forced identical), never in the slots themselves.

/// Where the side filter panel takes over from the modal filter sheet.
///
/// Point 13A §K.4: below this, filters are a bottom sheet applied on
/// "تطبيق"; at and above it, a permanent start-side panel that applies
/// immediately. 900, not [PlatformShell.expandedBreakpoint] (600) — the panel
/// needs the report's reading column *and* a 300 dp rail beside it, which 600
/// is too narrow to hold without squeezing the column the contrast test and
/// the reading-width rule both depend on.
const double kPlatformReportFilterBreakpoint = 900;

Color reportKindColor(BuildContext context, StatusKind kind) {
  final c = context.c;
  return switch (kind) {
    StatusKind.ok => c.ok,
    StatusKind.warn => c.warn,
    StatusKind.crit => c.crit,
    StatusKind.info => c.info,
    StatusKind.muted => c.ink3,
  };
}

/// The page frame every report shares. [filterPanel] is only ever laid out at
/// [kPlatformReportFilterBreakpoint] and above; below it, filtering happens
/// through [onOpenFilters] opening a modal sheet the report page builds
/// itself (`showModalBottomSheet`), because only the report knows its own
/// typed query.
class PlatformReportScaffold extends StatelessWidget {
  const PlatformReportScaffold({
    super.key,
    required this.title,
    required this.onRefresh,
    required this.refreshing,
    required this.filterCount,
    required this.onOpenFilters,
    required this.filterPanel,
    required this.filterChips,
    this.onClearFilters,
    required this.bodyBuilder,
  });

  final String title;
  final Future<void> Function() onRefresh;

  /// A refresh is in flight while content is already showing — Point 13A
  /// §K.3/§26: "refresh keeps content and shows a top linear progress
  /// indicator", never a full-page skeleton over rows already on screen.
  final bool refreshing;

  final int filterCount;
  final VoidCallback onOpenFilters;

  /// The live filter form, laid out as the start-side panel at
  /// [kPlatformReportFilterBreakpoint] and above. `null` for a report with no
  /// typed filters to offer at all (none in the closed catalogue today, but
  /// the slot stays optional rather than assumed).
  final Widget filterPanel;

  final List<Widget> filterChips;
  final VoidCallback? onClearFilters;

  /// Builds the report's own content for the current width class. `wide` is
  /// exactly [kPlatformReportFilterBreakpoint] and above — the same signal
  /// that raises the side filter panel — so a report can swap its compact row
  /// tiles for the §10 dense table without guessing at its own column width
  /// (the reading column stays capped at [kPlatformContentMaxWidth] either
  /// way; only the side panel's presence changes).
  final List<Widget> Function(bool wide) bodyBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: PlatformAppBar(
        title: title,
        actions: [
          IconButton(
            key: const Key('report-refresh'),
            tooltip: 'تحديث التقرير',
            onPressed: refreshing ? null : () => onRefresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= kPlatformReportFilterBreakpoint;
          final content = _ReportBody(
            onRefresh: onRefresh,
            refreshing: refreshing,
            wide: wide,
            filterCount: filterCount,
            onOpenFilters: onOpenFilters,
            filterChips: filterChips,
            onClearFilters: onClearFilters,
            body: bodyBuilder(wide),
          );
          if (!wide) return content;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const Key('report-filter-panel'),
                width: 300,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: filterPanel,
                ),
              ),
              VerticalDivider(width: 1, color: context.c.line),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.onRefresh,
    required this.refreshing,
    required this.wide,
    required this.filterCount,
    required this.onOpenFilters,
    required this.filterChips,
    required this.onClearFilters,
    required this.body,
  });

  final Future<void> Function() onRefresh;
  final bool refreshing;
  final bool wide;
  final int filterCount;
  final VoidCallback onOpenFilters;
  final List<Widget> filterChips;
  final VoidCallback? onClearFilters;
  final List<Widget> body;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kPlatformContentMaxWidth),
        child: Column(
          children: [
            if (refreshing)
              const LinearProgressIndicator(key: Key('report-refreshing')),
            Expanded(
              child: AppRefreshIndicator(
                onRefresh: onRefresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  children: [
                    if (!wide)
                      _FilterButtonRow(
                        count: filterCount,
                        onTap: onOpenFilters,
                      ),
                    if (filterChips.isNotEmpty || onClearFilters != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ...filterChips,
                            if (onClearFilters != null)
                              TextButton(
                                key: const Key('report-clear-filters'),
                                onPressed: onClearFilters,
                                child:
                                    const Text(S.platformReportFiltersClearAll),
                              ),
                          ],
                        ),
                      ),
                    ...body,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterButtonRow extends StatelessWidget {
  const _FilterButtonRow({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          key: const Key('report-open-filters'),
          onPressed: onTap,
          // `Size(0, 48)`, not the theme's `Size.fromHeight(48)` — that is
          // `Size(infinity, 48)`, which is why a one-word control stretched
          // across the page.
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          ),
          icon: const Icon(Icons.filter_list_rounded),
          label: Text(
            count == 0
                ? S.platformReportFiltersButton
                : '${S.platformReportFiltersButton} '
                    '(${toArabicIndic('$count')})',
          ),
        ),
      ),
    );
  }
}

/// The signature provenance line, directly under the page's question.
class ReportProvenanceLine extends StatelessWidget {
  const ReportProvenanceLine({
    super.key,
    required this.lines,
    this.stale = false,
    this.offlineCached = false,
  });

  /// Provenance sentences in reading order: what/as-of, source, exclusions.
  final List<String> lines;
  final bool stale;
  final bool offlineCached;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.c;
    return Semantics(
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line,
                style: t.bodySmall?.copyWith(color: c.ink3, height: 1.5),
              ),
            ),
          if (stale || offlineCached) ...[
            const SizedBox(height: AppSpacing.sm),
            _FreshnessNote(
              key: Key(
                  offlineCached ? 'report-offline-note' : 'report-stale-note'),
              icon: offlineCached
                  ? Icons.cloud_off_rounded
                  : Icons.history_rounded,
              text: offlineCached
                  ? S.platformReportOfflineCachedNote
                  : S.platformReportStaleNote,
            ),
          ],
        ],
      ),
    );
  }
}

class _FreshnessNote extends StatelessWidget {
  const _FreshnessNote({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: c.warn),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: c.warn, fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One labelled bucket in a [ReportBreakdownSection]: a name, a count and a
/// severity used only to colour the meter — never the only carrier of state
/// (§K.5 / §36), the label and count text say the same thing.
@immutable
class ReportBreakdownRow {
  const ReportBreakdownRow({
    required this.label,
    required this.count,
    this.kind = StatusKind.muted,
    this.trailing,
  });

  final String label;
  final int count;
  final StatusKind kind;

  /// A short trailing note, e.g. "مخصص" for an overridden limit.
  final String? trailing;
}

/// A labelled breakdown list: every known bucket, zero included, each with a
/// thin redundant proportion meter. No pie/donut, no animated count (§K.6).
class ReportBreakdownSection extends StatelessWidget {
  const ReportBreakdownSection({
    super.key,
    required this.title,
    required this.rows,
    required this.total,
  });

  final String title;
  final List<ReportBreakdownRow> rows;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          for (final row in rows) _BreakdownTile(row: row, total: total),
        ],
      ),
    );
  }
}

class _BreakdownTile extends StatelessWidget {
  const _BreakdownTile({required this.row, required this.total});
  final ReportBreakdownRow row;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    final color = reportKindColor(context, row.kind);
    final ratio = total == 0 ? 0.0 : row.count / total;
    final semantics = row.trailing == null
        ? '${row.label}: ${row.count}'
        : '${row.label}: ${row.count}، ${row.trailing}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        label: semantics,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(row.label, style: t.bodyMedium),
                  ),
                  if (row.trailing != null) ...[
                    Text(
                      row.trailing!,
                      style: TextStyle(color: c.ink3, fontSize: 12),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text('${row.count}', style: t.bodyMedium),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 4,
                  color: color,
                  backgroundColor: c.surface3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A two-line compact report row tile — the shared body around each report's
/// own facts line, tenant name and non-active lifecycle chip.
class ReportRowTile extends StatelessWidget {
  const ReportRowTile({
    super.key,
    required this.name,
    this.lifecycleChip,
    required this.facts,
    required this.onTap,
    required this.semanticLabel,
  });

  final String name;
  final Widget? lifecycleChip;
  final Widget facts;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (lifecycleChip != null) lifecycleChip!,
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                facts,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in a [ReportDenseTable]: the same facts a [ReportRowTile] shows,
/// laid out across columns instead of two stacked lines.
@immutable
class ReportDenseTableRow {
  const ReportDenseTableRow({
    this.rowKey,
    required this.name,
    this.lifecycleChip,
    required this.cells,
    required this.semanticLabel,
    required this.onTap,
  });

  /// The same [Key] the report's compact [ReportRowTile] uses for this row,
  /// so a test — or anything else keyed off it — does not care which layout
  /// is on screen.
  final Key? rowKey;

  final String name;
  final Widget? lifecycleChip;

  /// One widget per column after the name column; must match
  /// [ReportDenseTable.columnFlex] length minus one.
  final List<Widget> cells;
  final String semanticLabel;
  final VoidCallback onTap;
}

/// The ≥900 dp dense-row alternative to a stack of [ReportRowTile]s for the
/// three snapshot reports. Point 13A's §K.7 wording ("its own horizontal
/// scroll container") is refined here per the 13C closure pass: columns are
/// flex-proportioned to the reading column's own width instead, so the table
/// never depends on horizontal scrolling to be read or reached by keyboard —
/// a stricter accessibility bar than the original wording asked for, not a
/// looser one. Each row keeps exactly the one composed semantics label the
/// compact tile already used, so switching between the two at the 900 dp
/// boundary changes no assistive-technology behaviour, only density.
class ReportDenseTable extends StatelessWidget {
  const ReportDenseTable({
    super.key,
    required this.columnLabels,
    required this.columnFlex,
    required this.rows,
  }) : assert(columnLabels.length == columnFlex.length);

  /// Header labels, name column first.
  final List<String> columnLabels;

  /// Flex weights, name column first — supplements [columnLabels], it does
  /// not replace the header text.
  final List<int> columnFlex;
  final List<ReportDenseTableRow> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < columnLabels.length; i++)
                Expanded(
                  flex: columnFlex[i],
                  child: Text(
                    columnLabels[i],
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
        for (final row in rows) ...[
          _DenseTableRow(key: row.rowKey, row: row, columnFlex: columnFlex),
          Divider(height: 1, color: c.line),
        ],
      ],
    );
  }
}

class _DenseTableRow extends StatelessWidget {
  const _DenseTableRow(
      {super.key, required this.row, required this.columnFlex});
  final ReportDenseTableRow row;
  final List<int> columnFlex;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: row.semanticLabel,
      child: InkWell(
        onTap: row.onTap,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: columnFlex[0],
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.name,
                            style: t.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (row.lifecycleChip != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          row.lifecycleChip!,
                        ],
                      ],
                    ),
                  ),
                  for (var i = 0; i < row.cells.length; i++)
                    Expanded(flex: columnFlex[i + 1], child: row.cells[i]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The narrow-width filter host: a modal bottom sheet built around the
/// report's own typed form, applied only on "تطبيق التصفية" (§K.4 — dismiss
/// discards). The wide-width host is [PlatformReportScaffold.filterPanel]
/// laid out permanently instead, built directly from the same [builder] with
/// an immediate `onChange`, so the two hosts never drift about which controls
/// a report offers.
Future<Q?> showReportFilterSheet<Q>(
  BuildContext context, {
  required String title,
  required Q initial,
  required Widget Function(BuildContext, Q, ValueChanged<Q>) builder,
  required Q Function() cleared,
}) =>
    showModalBottomSheet<Q>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReportFilterSheet<Q>(
        title: title,
        initial: initial,
        builder: builder,
        cleared: cleared,
      ),
    );

class _ReportFilterSheet<Q> extends StatefulWidget {
  const _ReportFilterSheet({
    required this.title,
    required this.initial,
    required this.builder,
    required this.cleared,
  });

  final String title;
  final Q initial;
  final Widget Function(BuildContext, Q, ValueChanged<Q>) builder;
  final Q Function() cleared;

  @override
  State<_ReportFilterSheet<Q>> createState() => _ReportFilterSheetState<Q>();
}

class _ReportFilterSheetState<Q> extends State<_ReportFilterSheet<Q>> {
  late Q pending = widget.initial;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: .9,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.lg),
            widget.builder(
              context,
              pending,
              (v) => setState(() => pending = v),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              key: const Key('report-filters-apply'),
              onPressed: () => Navigator.pop(context, pending),
              child: const Text(S.platformReportFiltersApply),
            ),
            TextButton(
              key: const Key('report-filters-clear'),
              onPressed: () => Navigator.pop(context, widget.cleared()),
              child: const Text(S.platformReportFiltersClearAll),
            ),
          ],
        ),
      ),
    );
  }
}

/// The explicit "عرض المزيد" paging action (§K.7 / §24 — never infinite
/// scroll), with the "shown x of n" count and every paging state.
class ReportPagingFooter extends StatelessWidget {
  const ReportPagingFooter({
    super.key,
    required this.shown,
    required this.total,
    required this.hasMore,
    required this.paging,
    required this.pageFailed,
    required this.mustReload,
    required this.offlinePaging,
    required this.onLoadMore,
    required this.onReload,
  });

  final int shown;
  final int total;
  final bool hasMore;
  final bool paging;
  final bool pageFailed;
  final bool mustReload;
  final bool offlinePaging;
  final VoidCallback onLoadMore;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                '$shown / $total',
                style: TextStyle(color: c.ink3, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (mustReload)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.platformReportMustReloadTitle,
                  style: TextStyle(color: c.warn),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  key: const Key('report-reload'),
                  onPressed: onReload,
                  child: const Text(S.platformReportReload),
                ),
              ],
            )
          else if (offlinePaging)
            Text(
              S.platformReportOfflinePagingDisabled,
              style: TextStyle(color: c.ink3),
            )
          else if (pageFailed)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.platformReportPageFailedNote,
                  style: TextStyle(color: c.warn),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton(
                  key: const Key('report-load-more-retry'),
                  onPressed: paging ? null : onLoadMore,
                  child: const Text(S.platformReportRetry),
                ),
              ],
            )
          else if (hasMore)
            OutlinedButton(
              key: const Key('report-load-more'),
              onPressed: paging ? null : onLoadMore,
              child: Text(
                paging ? S.platformReportLoadingMore : S.platformReportShowMore,
              ),
            ),
        ],
      ),
    );
  }
}
