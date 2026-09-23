import 'package:flutter/material.dart';

import '../../../../core/format/app_number.dart';
import '../../../../core/format/app_time.dart';
import '../../../../core/motion/animated_counter.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/motion/press_scale.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_meta.dart';
import '../../../../core/widgets/forward_chevron.dart';
import '../../../../core/widgets/lock_window.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../core/widgets/tile_grid.dart';
import '../../../../l10n/strings.dart';
import '../../../shift/domain/attendance_policy.dart';
import '../../../shift/domain/shift_models.dart';
import '../../../shift/domain/shift_selectors.dart';
import '../../../team/domain/team_models.dart';
import '../../domain/today_selectors.dart';

/// The cards the Today dashboard is built from.
///
/// Presentation only: every figure arrives already decided by
/// `today_selectors.dart`, so nothing here recomputes what is current, what is
/// next, or what counts as present.

/// Which detachment the screen is about, and what day it is.
///
/// **The switcher is a control now.** The 2026-09-19 audit called the old one
/// "a 16 px double chevron": the whole header was tappable, and the only sign
/// of it was a glyph the size of a full stop at the far end. A session running
/// four detachments has to *find* the thing that changes which one it is
/// looking at, and everything under this header is about that choice. So the
/// affordance says its own name, carries a border, and states what it is
/// switching among — and when there is nothing to switch to it is not drawn at
/// all (`DETACHMENT-SCOPING.md` §4.5: no affordance for a choice that does not
/// exist).
///
/// The second line used to read «السبت ٠ ١٢ أيلول ٠ اللاذقية» in the render:
/// ` · ` beside Arabic-Indic numerals is the same mark as «٠». It is an
/// [AppMeta] line now, and the weekday and the day are *one* fact with no rule
/// between them.
class DashboardContextHeader extends StatelessWidget {
  const DashboardContextHeader({
    super.key,
    required this.detachmentName,
    required this.region,
    required this.now,
    this.detachmentCount = 1,
    this.onSwitch,
  });

  final String detachmentName;
  final String region;
  final DateTime now;

  /// How many detachments the session could switch to, including this one.
  final int detachmentCount;

  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    final lines = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          detachmentName,
          style: t.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        AppMeta(parts: [
          AppMetaText(AppTime.weekdayDay(now)),
          if (region.isNotEmpty) AppMetaText(region),
          // The organisation fact, where the organisation question is
          // actually asked. It used to be a card of its own further down the
          // screen — one line, one chevron, one more surface at the weight of
          // the day's operations — and the thing it was really telling a main
          // admin is that the screen they are reading is one of several.
          if (detachmentCount > 1)
            AppMetaText(
              S.dashboardAmongDetachments
                  .replaceFirst('%d', AppNumber.count(detachmentCount)),
            ),
        ]),
      ],
    );

    if (onSwitch == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(children: [Expanded(child: lines)]),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      // A wrap, not a row: at 1.6× the control and a two-line detachment name
      // cannot share a 320 dp line, and the control dropping under the name is
      // better than the name being squeezed to an ellipsis.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          lines,
          _SwitchControl(count: detachmentCount, onTap: onSwitch!),
        ],
      ),
    );
  }
}

class _SwitchControl extends StatelessWidget {
  const _SwitchControl({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${S.dashboardSwitchDetachment}، '
          '${S.dashboardAmongDetachments.replaceFirst('%d', AppNumber.count(count))}',
      onTap: onTap,
      child: PressScale(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line2),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.unfold_more_rounded, size: 16, color: c.ink2),
            const SizedBox(width: 6),
            Text(
              S.dashboardSwitchAction,
              style: AppTypography.chip(c).copyWith(color: c.ink2),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Today, in one card.
///
/// **Why one.** The 2026-09-19 audit's Home render showed two boxes side by
/// side saying «لا شفتات اليوم في هذه المفرزة» and «لا شفت قادم مجدول» — the
/// same absence, told twice, in two surfaces of equal weight, above 55 % empty
/// screen. Two cards is the right shape when there are two things; on a quiet
/// day there is one thing, and it is "nothing is running and nothing is
/// scheduled".
///
/// So this is one card with up to three regions, each of which is drawn only
/// when it has something to say:
///
///  1. **the quiet strip** — the confirmation that nothing needs a decision,
///     at the top, because on a quiet day that *is* the answer to the
///     screen's question. Never drawn when there is an attention list above,
///     which would be the same contradiction as two empty cards;
///  2. **now** — the running shift as the screen's one hero, or one sentence
///     saying nothing is running (and, when the whole day is empty, one
///     sentence covering both absences);
///  3. **next** — a compact row, never a card. It is context for the hero, not
///     a peer of it, and the audit's "too many equal surfaces" is what
///     happens when context gets its own box.
class TodayCard extends StatelessWidget {
  const TodayCard({
    super.key,
    required this.current,
    required this.attendance,
    required this.next,
    required this.now,
    required this.shiftsToday,
    required this.quiet,
    this.onOpenCurrent,
    this.onOpenNext,
    this.onViewSchedule,
  });

  /// The shift running at [now], or null.
  final Shift? current;

  /// Attendance on [current]. Ignored when [current] is null.
  final TodayAttendance attendance;

  /// The next shift ahead, or null.
  final Shift? next;

  final DateTime now;

  /// How many shifts are scheduled on today's calendar day.
  final int shiftsToday;

  /// Nothing was raised for a decision. Drawn as the calm state rather than
  /// as an absence.
  final bool quiet;

  final VoidCallback? onOpenCurrent;
  final VoidCallback? onOpenNext;
  final VoidCallback? onViewSchedule;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final shift = current;
    // The one case where the day is genuinely empty in both directions. It
    // gets one sentence, not two.
    final dayIsEmpty = shift == null && shiftsToday == 0 && next == null;

    return Container(
      key: const Key('dashboard-today'),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (quiet) ...[
            const _QuietStrip(),
            Divider(height: 1, thickness: 1, color: c.line),
          ],
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: shift == null
                ? _NoShiftNow(
                    dayIsEmpty: dayIsEmpty,
                    hasShiftsToday: shiftsToday > 0,
                    onViewSchedule: onViewSchedule,
                  )
                : _RunningShift(
                    shift: shift,
                    attendance: attendance,
                    now: now,
                    onOpen: onOpenCurrent,
                  ),
          ),
          // Suppressed only when the day is empty in both directions — there
          // the sentence above has already said it.
          if (!dayIsEmpty) ...[
            Divider(height: 1, thickness: 1, color: c.line),
            NextShiftRow(shift: next, now: now, onOpen: onOpenNext),
          ],
        ],
      ),
    );
  }
}

/// The calm state, as a first-class region rather than an empty box.
///
/// It says what was checked, so "nothing to do" reads as a result rather than
/// as a screen that failed to load.
class _QuietStrip extends StatelessWidget {
  const _QuietStrip();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      container: true,
      label: '${S.dashboardQuietTitle}. ${S.dashboardQuietBody}',
      child: ExcludeSemantics(
        child: Container(
          key: const Key('dashboard-quiet'),
          color: c.okTint,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.check_circle_outline_rounded, size: 18, color: c.ok),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.dashboardQuietTitle,
                    style: TextStyle(
                      color: c.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    S.dashboardQuietBody,
                    style: TextStyle(color: c.ink2, fontSize: 12, height: 1.4),
                  ),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Nothing is running. One sentence for one condition, and the schedule.
class _NoShiftNow extends StatelessWidget {
  const _NoShiftNow({
    required this.dayIsEmpty,
    required this.hasShiftsToday,
    this.onViewSchedule,
  });

  final bool dayIsEmpty;
  final bool hasShiftsToday;
  final VoidCallback? onViewSchedule;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final sentence = dayIsEmpty
        ? S.dashboardNoShiftsAtAll
        : hasShiftsToday
            ? S.dashboardNoShiftNow
            : S.dashboardNoShiftsToday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            hasShiftsToday
                ? Icons.schedule_rounded
                : Icons.event_available_outlined,
            size: 20,
            color: c.ink3,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              sentence,
              style: TextStyle(color: c.ink2, fontSize: 14, height: 1.5),
            ),
          ),
        ]),
        if (onViewSchedule != null) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('dashboard-view-schedule'),
              onPressed: onViewSchedule,
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: const Text(S.dashboardViewSchedule),
            ),
          ),
        ],
      ],
    );
  }
}

/// The shift running right now: where, when, who is answerable, and how
/// attendance stands. The screen's one hero; its primary action opens the
/// existing shift-management flow.
class _RunningShift extends StatelessWidget {
  const _RunningShift({
    required this.shift,
    required this.attendance,
    required this.now,
    this.onOpen,
  });

  final Shift shift;
  final TodayAttendance attendance;
  final DateTime now;

  /// Null when the session holds none of the shift capabilities — the card
  /// still reports, it just does not offer an action that would fail.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    final window = AttendanceWindow.of(shift, now: now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final heading = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.activeShift, style: AppTypography.eyebrow(c)),
              const SizedBox(height: 4),
              Text(
                shift.centerName,
                style: t.titleLarge,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                AppTime.minuteRange(shift.startMinutes, shift.endMinutes),
                style: AppTypography.digits(c.ink2, size: 15),
              ),
            ],
          );
          if (!window.isOpen) return heading;
          final lock = LockWindow(
            state: LockWindowState.open,
            remaining: window.remaining(now),
          );
          // The lock chip grows with the text scale, so its room is
          // measured in countdown ems: under 16 it would squeeze the
          // centre name to nothing, so it moves below the time instead.
          final em = MediaQuery.textScalerOf(context).scale(15);
          if (constraints.maxWidth < em * 16) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading,
                const SizedBox(height: AppSpacing.sm),
                lock,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: heading), lock],
          );
        }),
        const SizedBox(height: AppSpacing.md),
        _ManagerLine(manager: shift.manager),
        const SizedBox(height: AppSpacing.md),
        _AttendanceSummary(
          key: const Key('dashboard-attendance-summary'),
          attendance: attendance,
        ),
        if (onOpen != null) ...[
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('dashboard-open-current-shift'),
              onPressed: onOpen,
              icon: const Icon(Icons.event_available_rounded, size: 18),
              label: const Text(S.dashboardOpenShift),
            ),
          ),
        ],
      ],
    );
  }
}

/// The next shift ahead — a row inside the day's card, not a card of its own.
///
/// Compact on purpose: it is context for what is running, and the audit's
/// "too many equal surfaces" finding is what happens when context is drawn at
/// the weight of the thing it is context *for*.
class NextShiftRow extends StatelessWidget {
  const NextShiftRow({
    super.key,
    required this.shift,
    required this.now,
    this.onOpen,
  });

  final Shift? shift;
  final DateTime now;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final next = shift;

    if (next == null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(children: [
          Icon(Icons.hourglass_empty_rounded, size: 18, color: c.ink3),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              S.dashboardNoNextShift,
              style: TextStyle(color: c.ink3, fontSize: 13),
            ),
          ),
        ]),
      );
    }

    final isTomorrow = next.date.isAfter(dateOnly(now));
    final time = AppTime.minuteRange(next.startMinutes, next.endMinutes);
    final manager = next.manager?.name;
    final staffing = AppNumber.ratio(next.assigned, next.needed);

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(children: [
        Icon(Icons.upcoming_rounded, size: 18, color: c.ink2),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${S.dashboardNextShift} — ${next.centerName}',
                style: TextStyle(
                  color: c.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              AppMeta(parts: [
                if (isTomorrow) const AppMetaText(S.dashboardTomorrow),
                AppMetaText(time),
                AppMetaText(
                  manager ?? S.shiftManagerUnset,
                  color: manager == null ? c.warn : null,
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        StatusChip(
          kind: next.hasCoverageGap ? StatusKind.warn : StatusKind.ok,
          label: staffing,
        ),
        if (onOpen != null) ...[
          const SizedBox(width: AppSpacing.xs),
          const ForwardChevron(size: 20),
        ],
      ]),
    );

    if (onOpen == null) return content;
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: '${S.dashboardNextShift}، ${next.centerName}، $time، '
          '${manager ?? S.shiftManagerUnset}، $staffing',
      onTap: onOpen,
      child: PressScale(onTap: onOpen, child: content),
    );
  }
}

/// How consequential a raised condition is, in a word and in a colour — in
/// that order.
///
/// The dashboard used to carry severity in a tint and a glyph alone, which is
/// no carrier at all: invisible to a colour-blind reader, gone in a grey
/// print-out, never announced. The word is the carrier now and the colour
/// agrees with it.
enum AlertSeverity {
  urgent(S.severityUrgent),
  important(S.severityImportant),
  info(S.severityInfo);

  const AlertSeverity(this.label);

  final String label;

  /// True for the two levels that genuinely ask for a decision. Queued work
  /// that will clear itself on the next run is not one of them, and a heading
  /// that calls it «يحتاج قرارك» is a small lie told every day.
  bool get needsDecision => this != AlertSeverity.info;
}

/// Which severity each raised condition carries.
///
/// Read off the existing kind, not invented per screen, so the row, the
/// heading count and the semantics label can never disagree.
AlertSeverity severityOf(DashboardAlertKind kind) => switch (kind) {
      DashboardAlertKind.failedSync => AlertSeverity.urgent,
      DashboardAlertKind.lowStock => AlertSeverity.urgent,
      DashboardAlertKind.needsReview => AlertSeverity.important,
      DashboardAlertKind.understaffedShift => AlertSeverity.important,
      DashboardAlertKind.missingAttendance => AlertSeverity.important,
      DashboardAlertKind.expiringStock => AlertSeverity.important,
      DashboardAlertKind.pendingSync => AlertSeverity.info,
    };

/// One raised condition, as a **navigation row**.
///
/// Phase 2 settled this on the platform surface and the rule carries: buttons
/// are for state changes, rows are for navigation. Every destination an alert
/// has — the shift sheet, the storage tab, the sync centre, the review inbox —
/// is a place, not a change, and drawing it as a filled button put a brand
/// green call-to-action on a warning row. (Worse: Flutter's `FilledButton
/// .tonal` reads the same `FilledButtonTheme` as `FilledButton`, so the
/// "tonal" variant this row asked for was painted in the brand colour
/// anyway.)
class DashboardAlertRow extends StatelessWidget {
  const DashboardAlertRow({
    super.key,
    required this.alert,
    required this.title,
    required this.body,
    required this.isLast,
    this.onOpen,
  });

  final DashboardAlert alert;

  /// Resolved by the page: the copy lives in `S`, the value stays pure.
  final String title;
  final String body;

  final bool isLast;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final severity = severityOf(alert.kind);
    final (color, tint) = switch (severity) {
      AlertSeverity.urgent => (c.crit, c.critTint),
      AlertSeverity.important => (c.warn, c.warnTint),
      AlertSeverity.info => (c.info, c.infoTint),
    };
    final icon = switch (alert.kind) {
      DashboardAlertKind.needsReview => Icons.compare_arrows_rounded,
      DashboardAlertKind.failedSync => Icons.sync_problem_rounded,
      DashboardAlertKind.understaffedShift => Icons.group_off_outlined,
      DashboardAlertKind.missingAttendance => Icons.how_to_reg_outlined,
      DashboardAlertKind.lowStock => Icons.inventory_2_outlined,
      DashboardAlertKind.expiringStock => Icons.timer_outlined,
      DashboardAlertKind.pendingSync => Icons.cloud_upload_outlined,
    };

    final row = Container(
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Severity first, as the row's kicker. It was tried on the
              // second line beside the body, joined by an `AppMeta` hairline,
              // and the 320 dp / 1.6× render rejected it: the word took a
              // line of its own and left the rule leading a wrapped sentence,
              // where it reads as a bullet rather than as a join. Above the
              // title it also scans — a column of «عاجل / مهم / للعلم» is
              // readable down the edge without reading a single row.
              Text(
                severity.label,
                style: AppTypography.eyebrow(c).copyWith(color: color),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: TextStyle(color: c.ink3, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
        if (onOpen != null) ...[
          const SizedBox(width: AppSpacing.sm),
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.sm),
            child: ForwardChevron(size: 20),
          ),
        ],
      ]),
    );

    if (onOpen == null) return row;
    // One announcement for the whole row, severity first — that is what
    // decides whether the rest is read now.
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: S.dashboardAlertSemantics
          .replaceFirst('%severity%', severity.label)
          .replaceFirst('%title%', title)
          .replaceFirst('%body%', body),
      onTap: onOpen,
      child: PressScale(onTap: onOpen, child: row),
    );
  }
}

/// The detachment's standing facts, on one line.
///
/// Not five KPI tiles. These are the numbers a lead already knows and glances
/// at to confirm — the roster, today's schedule, the store's verdict — and
/// giving each one a card would say they are the point of the screen. Each is
/// read from state the dashboard already loaded; nothing here is fetched, and
/// nothing is computed that the tab behind it would not agree with.
class DashboardGlance extends StatelessWidget {
  const DashboardGlance({
    super.key,
    required this.rosterCount,
    required this.shiftsToday,
    required this.storageLabel,
    required this.storageKind,
  });

  final int rosterCount;
  final int shiftsToday;

  /// Null where the session may not see the store at all.
  final String? storageLabel;
  final StatusKind storageKind;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final roster = switch (rosterCount) {
      0 => S.dashboardRosterNone,
      1 => S.dashboardRosterOne,
      final n => S.dashboardRosterMany.replaceFirst('%d', AppNumber.count(n)),
    };
    final shifts = switch (shiftsToday) {
      0 => S.dashboardShiftsTodayNone,
      1 => S.dashboardShiftsTodayOne,
      final n =>
        S.dashboardShiftsTodayMany.replaceFirst('%d', AppNumber.count(n)),
    };
    final storage = storageLabel;

    return Container(
      key: const Key('dashboard-glance'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: AppMeta(parts: [
        AppMetaText(roster),
        AppMetaText(shifts),
        if (storage != null)
          AppMetaText(
            storage,
            color: switch (storageKind) {
              StatusKind.ok => c.ok,
              StatusKind.warn => c.warn,
              StatusKind.crit => c.crit,
              StatusKind.info => c.info,
              StatusKind.muted => c.ink3,
            },
          ),
      ]),
    );
  }
}

/// A shortcut into the detachment in focus.
///
/// Rendered only when its destination is one this session can actually open,
/// so the grid never offers a dead tile. What it is *not* is a second copy of
/// the bottom navigation: a shortcut earns its place by saving a real step,
/// and the two that only re-opened a permanent tab are gone.
class DashboardShortcut extends StatelessWidget {
  const DashboardShortcut({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PressScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: c.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            // Scale down, never wrap. Every shortcut label is a single Arabic
            // word, and a single word broken across two lines — «الإحصائيا /
            // ت» at 320 dp and 1.6× — is not a label any more. Shrinking it
            // to fit keeps the whole word, and the floor is still the 13 dp
            // base size because the shrink only ever undoes part of the
            // scale-up.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  color: c.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Lays the shortcuts out in equal columns instead of letting them wrap.
///
/// A `Wrap` of intrinsic-width pills produced the audit's "four ragged
/// quick-action chips": every row a different length, the last row one tile
/// wide, and the whole block reflowing whenever a capability changed which
/// tiles exist. [TileGrid] is the same information with a stable shape, and
/// the column count comes from the room a tile needs for a two-word Arabic
/// label at the reader's text scale.
class DashboardShortcutGrid extends StatelessWidget {
  const DashboardShortcutGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) =>
      TileGrid(
        tiles: tiles,
        minTileWidth: 140,
        // Never one column. A full-width shortcut reads as a primary action,
        // and the shortcuts are peers — the screen's one call to action is
        // inside the day's card.
        columnChoices: const [2, 3],
      );
}

class _ManagerLine extends StatelessWidget {
  const _ManagerLine({required this.manager});

  final TeamMember? manager;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final name = manager?.name;
    // A wrap, not a row: at large text the label alone can fill the line,
    // and the name — the part being reported — takes the next one rather
    // than being squeezed to nothing.
    return Wrap(
      spacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            name == null ? Icons.person_off_outlined : Icons.badge_outlined,
            size: 15,
            color: name == null ? c.warn : c.ink3,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${S.shiftManager}:',
              style: TextStyle(color: c.ink3, fontSize: 12),
            ),
          ),
        ]),
        Text(
          name ?? S.shiftManagerUnset,
          style: TextStyle(
            color: name == null ? c.warn : c.ink,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Present over assigned, with what is still open beside it. Counts come from
/// [TodayAttendance] so this widget adds nothing up itself.
class _AttendanceSummary extends StatelessWidget {
  const _AttendanceSummary({super.key, required this.attendance});

  final TodayAttendance attendance;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label at the start, count at the end while both fit on one line;
        // on a narrow card at large text the count drops under the label
        // (and "/ assigned" under the present figure) instead of the row
        // running out of room.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: AppSpacing.xs,
          children: [
            Text(S.attendanceProgress,
                style: TextStyle(color: c.ink2, fontSize: 13)),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AnimatedCounter(
                  value: attendance.present,
                  style: AppTypography.digits(c.ink, size: 15),
                ),
                Text(
                  ' / ${toArabicIndic('${attendance.assigned}')}',
                  style: AppTypography.digits(c.ink3, size: 15),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        _AttendanceBar(progress: attendance.progress),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
          _Pill(
            label: '${S.dashboardPresent} '
                '${toArabicIndic('${attendance.present}')}',
            kind: StatusKind.ok,
          ),
          if (attendance.awaiting > 0)
            _Pill(
              label: '${S.dashboardAwaiting} '
                  '${toArabicIndic('${attendance.awaiting}')}',
              kind: StatusKind.muted,
            ),
          if (attendance.absent > 0)
            _Pill(
              label: '${S.absent} '
                  '${toArabicIndic('${attendance.absent}')}',
              kind: StatusKind.crit,
            ),
          if (attendance.gap > 0)
            _Pill(
              label: '${S.shiftNeeded} '
                  '${toArabicIndic('${attendance.gap}')}',
              kind: StatusKind.warn,
            ),
        ]),
      ],
    );
  }
}

class _AttendanceBar extends StatelessWidget {
  const _AttendanceBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0, 1)),
      duration: effectiveValueDuration(context, MotionTokens.progressFill),
      curve: effectiveCurve(context, MotionTokens.enter),
      builder: (context, v, _) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Stack(children: [
          Container(height: 8, color: c.surface3),
          FractionallySizedBox(
            widthFactor: v,
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: c.ok,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.kind});

  final String label;
  final StatusKind kind;

  @override
  Widget build(BuildContext context) => StatusChip(kind: kind, label: label);
}
