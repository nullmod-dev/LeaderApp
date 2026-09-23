import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/app_number.dart';
import '../../../../core/motion/animated_counter.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/async_result.dart';
import '../../../../core/widgets/app_meta.dart';
import '../../../../core/widgets/offline_banner.dart';
import '../../../../core/widgets/refresh_indicator.dart';
import '../../../../l10n/strings.dart';
import '../../../shell/main_shell.dart';
import '../../data/workshop_providers.dart';
import '../../data/workshop_stats_providers.dart';
import '../../data/workshop_stats_report.dart';
import '../../domain/workshop_stats.dart';
import '../widgets/workshop_stats_export.dart';

/// Workshop → Statistics.
///
/// The information architecture is carried over from the legacy medical-team
/// app, which had the shape right: **dashboard → detail → file**. Attendance
/// as a rate you can read across the room, the money as two tiles, the exact
/// counts as a table underneath, then the two ways to get the numbers out of
/// the app — names on the clipboard, or a whole report as a file.
///
/// What changed is everything underneath. The numbers come from
/// `workshopStatsProvider` (this app's `Result` + Riverpod stack, not a raw
/// SQL stream), the report is built as this app's own `ReportDocument` so the
/// existing PDF builder and CSV writer both render it, and every colour,
/// radius, duration and digit comes from the MTM tokens.
///
// ASSUMPTION: this tab is not capability-gated. `stats.view` is scoped to a
// detachment, while workshops are organisation-level and have no scoped key.
class WorkshopStatsTab extends ConsumerWidget {
  const WorkshopStatsTab({super.key, required this.workshopId});

  final String workshopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppRefreshIndicator(
      onRefresh: () async {
        // The statistics are derived, so the two reads behind them are what
        // has to be dropped; awaiting the derived provider is what makes the
        // spinner last as long as the reload does.
        ref.invalidate(workshopByIdProvider(workshopId));
        ref.invalidate(workshopParticipantsProvider(workshopId));
        await ref.read(workshopStatsProvider(workshopId).future);
      },
      child: AsyncResultView<WorkshopStats>(
        value: ref.watch(workshopStatsProvider(workshopId)),
        onRetry: () => ref.invalidate(workshopStatsProvider),
        builder: (context, stats, stale) =>
            _Dashboard(stats: stats, stale: stale),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.stats, required this.stale});

  final WorkshopStats stats;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    return FloatingNavPadding(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (stale)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.md),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: StaleBadge(),
              ),
            ),
          _Title(stats: stats),
          const SizedBox(height: AppSpacing.lg),
          _AttendanceSection(stats: stats),
          const SizedBox(height: AppSpacing.md),
          _FinanceSection(stats: stats),
          const SizedBox(height: AppSpacing.md),
          _DetailSection(stats: stats),
          const SizedBox(height: AppSpacing.md),
          WorkshopCopyNamesCard(stats: stats),
          const SizedBox(height: AppSpacing.md),
          WorkshopStatsExportCard(stats: stats),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.stats});

  final WorkshopStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(children: [
      Text(
        stats.name,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        S.workshopStatsSubtitle,
        textAlign: TextAlign.center,
        style: TextStyle(color: c.ink3, fontSize: 12),
      ),
    ]);
  }
}

/// Two donuts side by side, one per group.
///
/// Deliberately not one combined rate: a workshop where every organiser
/// turned up and half the students did not is not "75% attended", and that is
/// exactly the workshop somebody needs to notice.
class _AttendanceSection extends StatelessWidget {
  const _AttendanceSection({required this.stats});

  final WorkshopStats stats;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: S.statsAttendanceSection,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _DonutMetric(
              label: S.statsGroupParticipants,
              group: stats.participantStats,
            ),
          ),
          Expanded(
            child: _DonutMetric(
              label: S.statsGroupTeam,
              group: stats.teamStats,
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutMetric extends StatelessWidget {
  const _DonutMetric({required this.label, required this.group});

  final String label;
  final WorkshopGroupStats group;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(children: [
      _Donut(percent: group.percent),
      const SizedBox(height: AppSpacing.sm),
      Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: c.ink2,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        '${AppNumber.ratio(group.present, group.absent)} '
        '${S.statsPresentAbsent}',
        textAlign: TextAlign.center,
        style: TextStyle(color: c.ink3, fontSize: 12),
      ),
      const SizedBox(height: 2),
      AppMeta(
        parts: [
          AppMetaText.count(group.paid, label: S.paymentPaid),
          AppMetaText.count(group.unpaid, label: S.paymentUnpaid),
          AppMetaText.count(group.unspecified, label: S.paymentUnspecified),
        ],
      ),
    ]);
  }
}

/// The attendance rate as a ring.
///
/// The sweep animates from empty on the same dial as every other value in the
/// app, so the cheap quality levels draw it at its final angle on the first
/// frame instead of running a painter for 700ms.
class _Donut extends StatelessWidget {
  const _Donut({required this.percent});

  final int percent;

  static const double _size = 96;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox.square(
      dimension: _size,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: percent / 100),
        duration: effectiveValueDuration(context, MotionTokens.progressFill),
        curve: effectiveCurve(context, MotionTokens.enter),
        builder: (context, value, child) => CustomPaint(
          painter: _DonutPainter(
            fraction: value,
            track: c.surface3,
            fill: percent >= 80
                ? c.ok
                : percent >= 50
                    ? c.warn
                    : c.crit,
          ),
          child: child,
        ),
        child: Center(
          child: TabularDigits(
            AppNumber.percent(percent),
            style: AppTypography.number(c, size: 20),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.fraction,
    required this.track,
    required this.fill,
  });

  final double fraction;
  final Color track;
  final Color fill;

  static const double _stroke = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - _stroke) / 2;
    final base = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    canvas.drawCircle(center, radius, base);
    if (fraction <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      fraction.clamp(0, 1) * math.pi * 2,
      false,
      Paint()
        ..color = fill
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.fraction != fraction || old.fill != fill || old.track != track;
}

/// What has come in, and what has not been settled.
///
/// A free workshop says so rather than printing a column of zeros that looks
/// like an unpaid bill.
class _FinanceSection extends StatelessWidget {
  const _FinanceSection({required this.stats});

  final WorkshopStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return _SectionCard(
      title: S.statsFinanceSection,
      child: stats.isFree
          ? Row(children: [
              Icon(Icons.card_giftcard_rounded, size: 16, color: c.ink3),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  S.statsFreeWorkshop,
                  style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
                ),
              ),
            ])
          : Row(children: [
              Expanded(
                child: _FinanceTile(
                  icon: Icons.check_circle_outline_rounded,
                  label: S.statsPayers,
                  value: toArabicIndic('${stats.paidCount}'),
                  caption: '${S.statsTotalCollected}: '
                      '${formatWorkshopAmount(stats.totalPaidAmount)}',
                  tone: _Tone.ok,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _FinanceTile(
                  icon: Icons.pending_outlined,
                  label: S.statsNonPayers,
                  value: toArabicIndic(
                      '${stats.unpaidCount + stats.unspecifiedCount}'),
                  caption: '${S.statsRegistrationFee}: '
                      '${formatWorkshopAmount(stats.registrationFee)}',
                  tone: _Tone.warn,
                ),
              ),
            ]),
    );
  }
}

enum _Tone { ok, warn, primary }

class _FinanceTile extends StatelessWidget {
  const _FinanceTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final String caption;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (fg, bg) = switch (tone) {
      _Tone.ok => (c.ok, c.okTint),
      _Tone.warn => (c.warn, c.warnTint),
      _Tone.primary => (c.primary, c.primaryTint),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: Icon(icon, size: 15, color: fg),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: c.ink3, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.sm),
          TabularDigits(value, style: AppTypography.number(c, size: 22)),
          const SizedBox(height: 2),
          Text(
            caption,
            style: TextStyle(color: c.ink3, fontSize: 11, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// The exact counts, in the same six columns the exported summary uses — so
/// what somebody reads on screen is literally the table they will get in the
/// file.
class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.stats});

  final WorkshopStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return _SectionCard(
      title: S.statsDetailSection,
      child: Column(children: [
        const _DetailRow(
          cells: [
            S.statsColCategory,
            S.statsColPresent,
            S.statsColAbsent,
            S.paymentPaid,
            S.paymentUnpaid,
            S.paymentUnspecified,
          ],
          header: true,
        ),
        Divider(height: AppSpacing.md, color: c.line),
        _DetailRow(
            cells: _row(S.statsGroupParticipants, stats.participantStats)),
        const SizedBox(height: AppSpacing.sm),
        _DetailRow(cells: _row(S.statsGroupTeam, stats.teamStats)),
        Divider(height: AppSpacing.lg, color: c.line),
        Row(children: [
          Icon(Icons.event_seat_rounded, size: 15, color: c.ink3),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              S.capacityUsage,
              style: TextStyle(color: c.ink3, fontSize: 12),
            ),
          ),
          Text(
            AppNumber.ratio(stats.registeredCount, stats.capacity),
            style: AppTypography.digits(c.ink, size: 14),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            AppNumber.percent(stats.capacityPercent),
            style: AppTypography.digits(c.ink3, size: 13),
          ),
        ]),
      ]),
    );
  }

  static List<String> _row(String label, WorkshopGroupStats g) => [
        label,
        toArabicIndic('${g.present}'),
        toArabicIndic('${g.absent}'),
        toArabicIndic('${g.paid}'),
        toArabicIndic('${g.unpaid}'),
        toArabicIndic('${g.unspecified}'),
      ];
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.cells, this.header = false});

  final List<String> cells;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(children: [
      Expanded(
        flex: 3,
        child: Text(
          cells.first,
          style: TextStyle(
            color: header ? c.ink3 : c.ink,
            fontSize: header ? 11 : 13,
            fontWeight: header ? FontWeight.w600 : FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      for (final cell in cells.skip(1))
        Expanded(
          flex: 2,
          child: header
              ? Text(
                  cell,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.ink3, fontSize: 10),
                  maxLines: 2,
                )
              : TabularDigits(
                  cell,
                  style: AppTypography.digits(c.ink, size: 14),
                ),
        ),
    ]);
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.eyebrow(c),
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
