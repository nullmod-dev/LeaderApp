import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/access/capability.dart';
import '../../../../core/access/capability_guard.dart';
import '../../../../core/chart/series_card.dart';
import '../../../../core/chart/series_scale.dart';
import '../../../../core/format/app_number.dart';
import '../../../../core/format/app_time.dart';
import '../../../../core/motion/animated_counter.dart';
import '../../../../core/result/result.dart';
import '../../../../core/motion/press_scale.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/time/clock.dart';
import '../../../../core/widgets/app_meta.dart';
import '../../../../core/widgets/async_result.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/forward_chevron.dart';
import '../../../../core/widgets/reading_column.dart';
import '../../../../core/widgets/refresh_indicator.dart';
import '../../../../core/widgets/tile_grid.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../l10n/strings.dart';
import '../../../inventory/data/inventory_providers.dart';
import '../../../inventory/domain/inventory_models.dart';
import '../../../shell/main_shell.dart';
import '../../../shift/data/shift_providers.dart';
import '../../../shift/domain/shift_models.dart';
import '../../../team/data/team_providers.dart';
import '../../../team/domain/team_models.dart';
import '../../data/detachment_providers.dart';
import '../../domain/detachment_models.dart';

/// The detachment's numbers, and the door to the report builder.
///
/// It covers all four tabs rather than only its own: a lead asking "how are
/// we doing" means the roster, the week, and the stock together. The tiles at
/// the top are live reads of the same providers those tabs use, so this
/// screen can never quote a number the tab beside it contradicts.
///
/// Gated whole: without `stats.view` there is nothing on it a session may
/// see, so it renders a denied state rather than an empty chart. The shell no
/// longer offers the tab to such a session; this state is what a direct link
/// lands on, and it says *permission*, never "no statistics yet" — the
/// empty-data sentence would have told a scoped administrator to wait for
/// numbers that were never going to appear (Point 16).
class DetachmentStatsTab extends ConsumerWidget {
  const DetachmentStatsTab({super.key, required this.detachmentId});

  final String detachmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CapabilityGate(
      capability: Cap.statsView,
      detachmentId: detachmentId,
      denied: const EmptyState(
        key: Key('detachment-stats-not-permitted'),
        icon: Icons.lock_outline_rounded,
        title: S.statsNotPermittedTitle,
        body: S.statsNotPermittedBody,
      ),
      child: AppRefreshIndicator(
        onRefresh: () =>
            ref.refresh(detachmentStatsProvider(detachmentId).future),
        child: AsyncResultView<DetachmentStats>(
          value: ref.watch(detachmentStatsProvider(detachmentId)),
          onRetry: () => ref.invalidate(detachmentStatsProvider),
          builder: (context, stats, stale) => FloatingNavPadding(
            // Class B of the measure policy: an operational screen of grouped
            // cards and rows. Uncapped, the member records ran a name at one
            // edge of a 900 dp window and its counts at the other.
            child: ReadingColumn(
              maxWidth: kContentMaxWidth,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                children: [
                  const SectionHeader(title: S.statsOverview),
                  _LiveTiles(detachmentId: detachmentId),
                  const SizedBox(height: AppSpacing.md),
                  _ExportCard(
                    onTap: () =>
                        context.push('/detachment/$detachmentId/report'),
                  ),
                  _AttendanceSection(detachmentId: detachmentId),
                  // Two series, two units, two stated domains — and never one
                  // shared scale. Coverage is a proportion and is drawn
                  // against 0–100 whatever its own peak is; consumption is a
                  // tally and is drawn against a round ceiling above its peak,
                  // which the card prints.
                  SeriesCard(
                    id: 'coverage',
                    title: S.statsCoverage,
                    hint: S.statsCoverageHint,
                    plot: SeriesPlot(stats.coverageSeries,
                        unit: SeriesUnit.percent),
                    endsOn: dateOnly(ref.watch(clockProvider)()),
                  ),
                  SeriesCard(
                    id: 'stock',
                    title: S.statsStock,
                    hint: S.statsStockHint,
                    plot:
                        SeriesPlot(stats.stockSeries, unit: SeriesUnit.count),
                    endsOn: dateOnly(ref.watch(clockProvider)()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _StatsRange {
  week(7, S.rangeWeek),
  month(30, S.rangeMonth),
  quarter(90, S.rangeQuarter);

  const _StatsRange(this.days, this.label);
  final int days;
  final String label;
}

class _AttendanceSection extends ConsumerStatefulWidget {
  const _AttendanceSection({required this.detachmentId});

  final String detachmentId;

  @override
  ConsumerState<_AttendanceSection> createState() => _AttendanceSectionState();
}

class _AttendanceSectionState extends ConsumerState<_AttendanceSection> {
  _StatsRange _range = _StatsRange.month;
  String? _memberId;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Through the clock provider, like the dashboard: the range this section
    // asks for is «the last N days ending today», and a screen that reads the
    // wall clock directly cannot be rendered or tested at a fixed instant.
    final today = dateOnly(ref.watch(clockProvider)());
    final query = AttendanceStatsQuery(
      detachmentId: widget.detachmentId,
      from: addDays(today, -(_range.days - 1)),
      to: today,
      memberId: _memberId,
    );
    final roster = _dataOf(
      ref.watch(teamListProvider(widget.detachmentId)).valueOrNull,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: S.attendanceDetails),
        Row(children: [
          for (final range in _StatsRange.values) ...[
            Expanded(
              child: _ChoiceFilter(
                label: range.label,
                selected: _range == range,
                onTap: () => setState(() => _range = range),
              ),
            ),
            if (range != _StatsRange.values.last)
              const SizedBox(width: AppSpacing.xs),
          ],
        ]),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String?>(
          key: const Key('attendance-member-filter'),
          initialValue: _memberId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: S.memberFilter),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text(S.allMembers),
            ),
            for (final member in roster ?? const <TeamMember>[])
              DropdownMenuItem<String?>(
                value: member.id,
                child: Text(member.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (value) => setState(() => _memberId = value),
        ),
        const SizedBox(height: AppSpacing.md),
        AsyncResultView<AttendanceStatistics>(
          value: ref.watch(attendanceStatisticsProvider(query)),
          onRetry: () => ref.invalidate(attendanceStatisticsProvider(query)),
          loading: const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          builder: (context, statistics, stale) {
            if (statistics.members.isEmpty) {
              return Text(S.noStats,
                  style: TextStyle(color: c.ink3, fontSize: 13));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TileGrid(
                  minTileWidth: 150,
                  columnChoices: const [2, 4],
                  tiles: [
                    _AttendanceMetric(S.presentTotal, statistics.presentCount),
                    _AttendanceMetric(S.absentTotal, statistics.absentCount),
                    _AttendanceMetric(
                      S.completedTotal,
                      statistics.completedCount,
                    ),
                    _AttendanceMetric(
                      S.attendancePercent,
                      statistics.attendancePercent,
                      percent: true,
                    ),
                  ],
                ),
                for (final role in TeamRole.values) ...[
                  if (statistics.members.any((member) => member.role == role))
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md),
                      child: Text(
                        _statsRoleLabel(role),
                        style: TextStyle(
                          color: c.ink2,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  for (final member in statistics.members
                      .where((member) => member.role == role))
                    _MemberAttendanceCard(member: member),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  static T? _dataOf<T>(Result<T>? result) => result?.when(
        success: (data, {stale = false}) => data,
        failure: (_, __) => null,
        offline: (cached) => cached,
      );
}

class _ChoiceFilter extends StatelessWidget {
  const _ChoiceFilter({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PressScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.primaryTint : c.surface,
          border: Border.all(color: selected ? c.primary : c.line),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Text(
          label,
          style: TextStyle(color: selected ? c.primary : c.ink2, fontSize: 12),
        ),
      ),
    );
  }
}

/// One total from the attendance range.
///
/// It used to read «إجمالي الحضور · ١٠٠» in a fixed 148 dp box. Beside
/// Arabic-Indic numerals that dot is «٠», so the card said "total present,
/// zero, one hundred". The label and the figure are now stacked — a label is
/// not a fact on a meta line, it is the name of the fact under it — and the
/// box sizes to its content instead of clipping a long label at a width
/// chosen for a short one.
class _AttendanceMetric extends StatelessWidget {
  const _AttendanceMetric(this.label, this.value, {this.percent = false});

  final String label;
  final int value;

  /// Renders through the one percentage path rather than appending `'٪'`.
  final bool percent;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: c.ink3, fontSize: 11),
          ),
          const SizedBox(height: 2),
          TabularDigits(
            percent ? AppNumber.percent(value) : AppNumber.count(value),
            style: AppTypography.digits(c.ink, size: 16),
          ),
        ],
      ),
    );
  }
}

/// One member's totals and their individual records.
///
/// Both lines here were ` · `-joined strings, and both sat next to
/// Arabic-Indic numerals: «إجمالي الحضور ١ · إجمالي الغياب ٠ · الحضور المكتمل
/// ١» rendered as a run of five identical dots of which three were values,
/// and the record line put a dot immediately before a clock that begins «٠».
/// They are [AppMeta] lines now: the rule is drawn, not written.
class _MemberAttendanceCard extends StatelessWidget {
  const _MemberAttendanceCard({required this.member});

  final MemberAttendanceSummary member;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(member.memberName,
              style: TextStyle(
                  color: c.ink, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          AppMeta(parts: [
            AppMetaText.total(S.presentTotal, member.presentCount),
            AppMetaText.total(S.absentTotal, member.absentCount),
            AppMetaText.total(S.completedTotal, member.completedCount),
          ]),
          for (final record in member.records)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: AppMeta(parts: [
                AppMetaText.day(record.shiftDate),
                AppMetaText(_statsAttendanceLabel(record.status)),
                if (record.checkInAt != null)
                  AppMetaText.code(
                    AppTime.clockRange(record.checkInAt!, record.checkOutAt),
                  ),
              ]),
            ),
        ],
      ),
    );
  }
}

String _statsRoleLabel(TeamRole role) => switch (role) {
      TeamRole.shiftSupervisor => S.roleShiftSupervisor,
      TeamRole.administrator => S.roleAdministrator,
      TeamRole.followUp => S.roleFollowUp,
      TeamRole.member => S.roleMember,
    };

String _statsAttendanceLabel(AttendanceState state) => switch (state) {
      AttendanceState.notCheckedIn => S.notCheckedIn,
      AttendanceState.checkedIn => S.checkedIn,
      AttendanceState.checkedOut => S.checkedOut,
      AttendanceState.absent => S.absent,
    };

/// Four figures read straight from the other tabs' providers.
///
/// Each tile renders its own value the moment its provider resolves, rather
/// than the whole row waiting on the slowest of them — three of these are
/// separate mock round-trips.
///
/// **Two things the render changed.** The four tiles were a fixed `Row`, and
/// at 320 dp / 1.6× that left «أدوية منخفضة» drawn as «أدوية…» and «تغطية
/// الأسبوع» as «تغطي…»: the figures survived and their meanings did not,
/// which is the same defect as an unlabelled chart. They reflow to two
/// columns when the row cannot hold four. And the coverage tile printed
/// «١٠٠٪» for a week with no shifts in it, because `WeekSummary.coveragePercent`
/// answers 100 when nothing is needed — true as a fraction, false as a
/// statement. A week with no shifts has no coverage to report, so the tile
/// says so rather than reporting a perfect one.
class _LiveTiles extends ConsumerWidget {
  const _LiveTiles({required this.detachmentId});

  final String detachmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(teamListProvider(detachmentId)).valueOrNull;
    final week = ref
        .watch(weekShiftsProvider(WeekQuery(
          detachmentId: detachmentId,
          weekStart: startOfWeek(ref.watch(clockProvider)()),
        )))
        .valueOrNull;
    final stock = ref.watch(inventoryListProvider(detachmentId)).valueOrNull;

    final members = _dataOf(roster);
    final shifts = _dataOf(week);
    final items = _dataOf(stock);
    final summary = shifts == null ? null : WeekSummary.of(shifts);
    final lowCount =
        items?.where((i) => i.level != StockLevel.ok).length ?? 0;

    final tiles = <Widget>[
      _Tile(
        icon: Icons.groups_rounded,
        label: S.statsMembers,
        value: members == null ? null : AppNumber.count(members.length),
      ),
      _Tile(
        icon: Icons.event_note_rounded,
        label: S.statsShifts,
        value: summary == null ? null : AppNumber.count(summary.shiftCount),
      ),
      _Tile(
        icon: Icons.donut_small_rounded,
        label: S.weekCoverage,
        // Resolved, not loading: the week loaded and simply has nothing to
        // measure. An em dash is the honest reading.
        value: summary == null
            ? null
            : summary.shiftCount == 0
                ? '—'
                : AppNumber.percent(summary.coveragePercent),
        unavailable: summary != null && summary.shiftCount == 0,
      ),
      _Tile(
        icon: Icons.inventory_2_rounded,
        label: S.stockLow,
        value: items == null ? null : AppNumber.count(lowCount),
        warn: lowCount > 0,
      ),
    ];

    // Four across while a tile can still hold «أدوية منخفضة» on two lines,
    // two across below that. Never one and never three: a full-width metric
    // tile reads as a headline rather than as one of four comparable
    // figures, and three columns would split four figures 3 + 1.
    return TileGrid(
      tiles: tiles,
      minTileWidth: 82,
      columnChoices: const [2, 4],
    );
  }

  static T? _dataOf<T>(Result<T>? result) => result?.when(
        success: (data, {stale = false}) => data,
        failure: (_, __) => null,
        offline: (cached) => cached,
      );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.value,
    this.warn = false,
    this.unavailable = false,
  });

  final IconData icon;
  final String label;

  /// Null while the underlying provider is still resolving. Already in the
  /// app's numerals when it is not.
  final String? value;
  final bool warn;

  /// The figure resolved to "there is nothing to measure" rather than to a
  /// number. Drawn quietly so it does not read as a reading of zero.
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final tone = warn ? c.warn : (unavailable ? c.ink3 : c.ink);
    return Semantics(
      container: true,
      label: '$label، ${value ?? S.statsLoadingValue}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.md, horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Column(children: [
            Icon(icon, size: 17, color: warn ? c.warn : c.ink3),
            const SizedBox(height: 6),
            value == null
                ? SizedBox(
                    height: 24,
                    child: Center(
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: c.ink3),
                      ),
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: TabularDigits(
                      value!,
                      style: AppTypography.digits(tone, size: 19),
                    ),
                  ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(color: c.ink3, fontSize: 11, height: 1.3),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PressScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.infoTint,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(children: [
          Icon(Icons.description_outlined, color: c.info),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(S.exportReport,
                    style: TextStyle(
                        color: c.info,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(S.exportSub,
                    style: TextStyle(color: c.ink2, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
          ForwardChevron(color: c.info),
        ]),
      ),
    );
  }
}
