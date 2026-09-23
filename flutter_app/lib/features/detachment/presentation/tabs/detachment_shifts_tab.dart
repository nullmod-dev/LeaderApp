import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/access/capability.dart';
import '../../../../core/format/app_date.dart';
import '../../../../core/format/app_number.dart';
import '../../../../core/format/app_time.dart';
import '../../../../core/motion/animated_counter.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/motion/press_scale.dart';
import '../../../../core/motion/stagger.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/async_result.dart';
import '../../../../core/widgets/app_meta.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/forward_chevron.dart';
import '../../../../core/widgets/refresh_indicator.dart';
import '../../../../core/widgets/sheet_scaffold.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../l10n/strings.dart';
import '../../../shell/main_shell.dart';
import '../../../shift/data/shift_providers.dart';
import '../../../shift/domain/shift_models.dart';
import '../../../shift/presentation/shift_edit_sheet.dart';
import '../../../shift/presentation/shift_manage_sheet.dart';
import '../../../shift/presentation/template_edit_sheet.dart';
import '../../data/detachment_providers.dart';
import '../../domain/detachment_models.dart';

/// One detachment's schedule, one day at a time.
///
/// The whole screen is one path: **pick a day → read its shift cards → open a
/// card → manage that shift**. Nothing above the day selector, nothing on a
/// card that is not part of choosing which card to open.
///
/// The weekly summary that used to sit at the top is gone. It answered a
/// question ("how is the week doing?") that the statistics tab answers
/// better, and it did so in the space where the day selector belongs — the
/// control that every other thing on this screen depends on. The week
/// *navigation* stays, folded into the selector itself, because stepping to
/// next week is part of picking a day.
///
/// Two affordances exist specifically because scheduling by hand was the part
/// of the legacy program people found hard:
///
/// * **Copy previous day** — a detachment runs ten to fifteen days and most
///   of them look like the one before. One tap instead of eight forms.
/// * **Quick fill** — closes a coverage gap with members who are actually
///   free at that hour, instead of leaving someone to cross-check by eye.
///
/// Repetition itself is not a button here: the shift editor's day picker
/// materialises a shift on each chosen day when it is saved, and the
/// templates sheet edits those days afterwards. A shift card is a summary;
/// tapping it opens the management sheet that carries every per-shift
/// action.
class DetachmentShiftsTab extends ConsumerWidget {
  const DetachmentShiftsTab({super.key, required this.detachmentId});

  final String detachmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekStart = ref.watch(selectedWeekProvider(detachmentId));
    final dayOffset = ref.watch(selectedDayOffsetProvider(detachmentId));
    final query = WeekQuery(detachmentId: detachmentId, weekStart: weekStart);

    // One resolver for both halves of the question — "may this session do
    // it" and "does this detachment still accept it". A finished detachment
    // answers no to every one of these five, so the bulk actions, the add
    // control, and every per-shift action below fall away together instead
    // of one at a time.
    final access = ref.accessIn(detachmentId);
    final canManage = access.can(Cap.shiftManage);
    final canAssign = access.can(Cap.shiftAssign);
    final canRecord = access.can(Cap.shiftAttendanceRecord);
    final canOverride = access.can(Cap.shiftAttendanceOverride);
    final canDelete = access.can(Cap.shiftDelete);

    // A finished detachment opens on the last week it actually worked rather
    // than on this one, which it never reached. Applied once, and only while
    // the selection is still the untouched default, so it can never fight a
    // week the reader has navigated to themselves.
    if (access.isHistorical) {
      ref.listen<AsyncValue<DateTime?>>(
        lastScheduledDayProvider(detachmentId),
        (_, next) {
          final day = next.valueOrNull;
          if (day == null) return;
          final thisWeek = startOfWeek(DateTime.now());
          if (ref.read(selectedWeekProvider(detachmentId)) != thisWeek) return;
          final week = startOfWeek(day);
          if (week == thisWeek) return;
          ref.read(selectedWeekProvider(detachmentId).notifier).state = week;
          ref.read(selectedDayOffsetProvider(detachmentId).notifier).state =
              day.difference(week).inDays;
        },
      );
    }

    return AppRefreshIndicator(
      onRefresh: () => ref.refresh(weekShiftsProvider(query).future),
      child: AsyncResultView<List<Shift>>(
        value: ref.watch(weekShiftsProvider(query)),
        onRetry: () => ref.invalidate(weekShiftsProvider),
        builder: (context, shifts, stale) => _Week(
          detachmentId: detachmentId,
          weekStart: weekStart,
          dayOffset: dayOffset,
          shifts: shifts,
          historical: access.isHistorical,
          canManage: canManage,
          canAssign: canAssign,
          canRecord: canRecord,
          canOverride: canOverride,
          canDelete: canDelete,
        ),
      ),
    );
  }
}

class _Week extends ConsumerWidget {
  const _Week({
    required this.detachmentId,
    required this.weekStart,
    required this.dayOffset,
    required this.shifts,
    required this.historical,
    required this.canManage,
    required this.canAssign,
    required this.canRecord,
    required this.canOverride,
    required this.canDelete,
  });

  final String detachmentId;
  final DateTime weekStart;
  final int dayOffset;
  final List<Shift> shifts;

  /// This detachment has ended, so an empty day is a fact about the past
  /// rather than a day nobody has staffed yet.
  final bool historical;

  final bool canManage;
  final bool canAssign;
  final bool canRecord;
  final bool canOverride;
  final bool canDelete;

  DateTime get _selectedDay => addDays(weekStart, dayOffset);

  List<Shift> _shiftsOn(int offset) {
    final day = addDays(weekStart, offset);
    return shifts.where((s) => s.date == day).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = _shiftsOn(dayOffset);

    return FloatingNavPadding(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
        children: [
          // First thing under the tabs, because every other thing on this
          // screen is scoped to the day it selects.
          _DaySelector(
            detachmentId: detachmentId,
            weekStart: weekStart,
            selected: dayOffset,
            countsFor: (i) {
              final list = _shiftsOn(i);
              return (list.length, list.where((s) => s.hasCoverageGap).length);
            },
            onPick: (i) => ref
                .read(selectedDayOffsetProvider(detachmentId).notifier)
                .state = i,
          ),
          const SizedBox(height: AppSpacing.md),
          if (canManage)
            _BulkActions(
              detachmentId: detachmentId,
              day: _selectedDay,
            ),
          const SizedBox(height: AppSpacing.md),
          _DayHeader(
            day: _selectedDay,
            count: today.length,
            onAdd:
                canManage ? () => _addShift(context, ref, _selectedDay) : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (today.isEmpty)
            _EmptyDay(
              historical: historical,
              onAdd: canManage
                  ? () => _addShift(context, ref, _selectedDay)
                  : null,
            )
          else
            for (int i = 0; i < today.length; i++) ...[
              Stagger(
                index: i,
                child: _ShiftCard(
                  shift: today[i],
                  canAssign: canAssign,
                  canRecord: canRecord,
                  canOverride: canOverride,
                  canManage: canManage,
                  canDelete: canDelete,
                  detachmentId: detachmentId,
                ),
              ),
              if (i != today.length - 1) const SizedBox(height: AppSpacing.md),
            ],
        ],
      ),
    );
  }

  Future<void> _addShift(
      BuildContext context, WidgetRef ref, DateTime day) async {
    // The centre field is pre-filled with the detachment's main centre,
    // which is right for most shifts and editable for the rest.
    final detachment =
        ref.read(detachmentByIdProvider(detachmentId)).valueOrNull;
    final center = detachment?.when(
          success: (Detachment d, {bool stale = false}) => d.mainCenter,
          failure: (_, __) => '',
          offline: (cached) => cached?.mainCenter ?? '',
        ) ??
        '';
    await showShiftEditor(
      context: context,
      detachmentId: detachmentId,
      date: day,
      defaultCenter: center,
    );
  }
}

// ---------------------------------------------------------------------------
// Day selector
// ---------------------------------------------------------------------------

/// The one control the rest of the screen hangs off: which day am I looking
/// at.
///
/// It carries the week navigation in its own header row rather than in a card
/// above it. Stepping to the next week is part of picking a day, and giving
/// it a separate card was what pushed the day chips — the thing people
/// actually touch — a summary's height down the screen.
///
/// No coverage percentages, no shift totals, no gap counts. Each chip still
/// carries one dot for its own day, because that is what tells you *which day
/// to pick*; the week's numbers live in the statistics tab, where they can be
/// read properly.
class _DaySelector extends ConsumerWidget {
  const _DaySelector({
    required this.detachmentId,
    required this.weekStart,
    required this.selected,
    required this.countsFor,
    required this.onPick,
  });

  final String detachmentId;
  final DateTime weekStart;
  final int selected;
  final (int total, int gaps) Function(int offset) countsFor;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final today = dateOnly(DateTime.now());
    final isThisWeek = weekStart == startOfWeek(today);

    void goToWeek(DateTime start) =>
        ref.read(selectedWeekProvider(detachmentId).notifier).state = start;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          // Both rounded chevrons mirror under RTL, so `earlier` is
          // `chevron_left` and paints to the *right* in Arabic — towards the
          // days that came before. See `DirectionalArrows`.
          _Nav(
            icon: DirectionalArrows.earlier,
            label: S.prevWeek,
            onTap: () => goToWeek(addDays(weekStart, -7)),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isThisWeek ? null : () => goToWeek(startOfWeek(today)),
              child: Column(children: [
                Text(
                  isThisWeek ? S.thisWeek : S.weekOf,
                  style: TextStyle(
                    color: isThisWeek ? c.ink3 : c.primary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppDate.weekRange(weekStart),
                  style: AppTypography.digits(c.ink, size: 13),
                ),
              ]),
            ),
          ),
          _Nav(
            icon: DirectionalArrows.later,
            label: S.nextWeek,
            onTap: () => goToWeek(addDays(weekStart, 7)),
          ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          // The strip is a fixed-height row of seven equal columns, so its
          // height has to follow the text it holds: a chip stacks a weekday,
          // a date and a coverage dot, and at a 1.6 text scale 74 dp clipped
          // the dot and overflowed by 21 px. Scaling the box keeps the seven
          // columns equal — which is the point of the strip — instead of
          // letting one day's chip grow taller than its neighbours.
          height: MediaQuery.textScalerOf(context).scale(74),
          child: Row(children: [
            for (int i = 0; i < 7; i++) ...[
              Expanded(
                child: _DayChip(
                  day: addDays(weekStart, i),
                  isToday: addDays(weekStart, i) == today,
                  selected: i == selected,
                  counts: countsFor(i),
                  onTap: () => onPick(i),
                ),
              ),
              if (i != 6) const SizedBox(width: 5),
            ],
          ]),
        ),
      ],
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav({
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
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: PressScale(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: Container(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              alignment: Alignment.center,
              decoration:
                  BoxDecoration(color: c.surface2, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: c.ink2),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.isToday,
    required this.selected,
    required this.counts,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool selected;
  final (int total, int gaps) counts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (total, gaps) = counts;
    // One node per column, spelling the day out. The cell shows a letter and
    // a number, which is the right *visual* density for seven columns and the
    // wrong thing to hear: «س ١٢» names no day. The amber dot is also the
    // only sign that a day is short-staffed, and colour alone is not a
    // status — so the gap is said here too.
    return Semantics(
      button: true,
      selected: selected,
      onTap: onTap,
      label: gaps > 0
          ? '${AppTime.weekdayDay(day)}، ${S.coverageGap}'
          : AppTime.weekdayDay(day),
      excludeSemantics: true,
      child: PressScale(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: AnimatedContainer(
          duration: effectiveDuration(context, MotionTokens.short),
          curve: effectiveCurve(context, MotionTokens.standard),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? c.primary : c.surface,
            border: Border.all(
              color: selected
                  ? c.primary
                  : isToday
                      ? c.primary.withValues(alpha: 0.45)
                      : c.line,
            ),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                // One letter, and a distinct one per day: a two-character
                // prefix of an Arabic weekday is «ال» every time.
                AppDate.weekdayInitialOf(day),
                style: TextStyle(
                  color: selected ? c.primaryInk : c.ink2,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                toArabicIndic('${day.day}'),
                style: AppTypography.digits(
                  selected ? c.primaryInk : c.ink,
                  size: 15,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 6,
                child: total == 0
                    ? null
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: gaps > 0
                                  ? (selected ? c.warnTint : c.warn)
                                  : (selected ? c.primaryInk : c.ok),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bulk actions
// ---------------------------------------------------------------------------

class _BulkActions extends ConsumerStatefulWidget {
  const _BulkActions({
    required this.detachmentId,
    required this.day,
  });

  final String detachmentId;

  /// The selected day — what "copy the previous day" copies *onto*. The week
  /// is no longer part of this row's job now that the copy is day-scoped.
  final DateTime day;

  @override
  ConsumerState<_BulkActions> createState() => _BulkActionsState();
}

class _BulkActionsState extends ConsumerState<_BulkActions> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    // "Copy the previous day" replaced "copy last week". A detachment lasts
    // ten to fifteen days, so there is rarely a previous *week* to copy — but
    // there is almost always a yesterday, and it usually looks like today.
    // The templates list stays reachable because it is schedule-scoped, not
    // shift-scoped.
    final copy = _Action(
      icon: Icons.content_copy_rounded,
      label: S.copyPreviousDay,
      onTap: _busy ? null : _copyPreviousDay,
    );
    final templates = _Action(
      icon: Icons.event_repeat_rounded,
      label: S.templatesButton,
      onTap: _busy ? null : _openTemplates,
    );
    return LayoutBuilder(builder: (context, constraints) {
      final largeNarrow = MediaQuery.textScalerOf(context).scale(1) >= 1.4 &&
          constraints.maxWidth < 420;
      if (largeNarrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            copy,
            const SizedBox(height: AppSpacing.sm),
            templates,
          ],
        );
      }
      return Row(children: [
        Expanded(child: copy),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: templates),
      ]);
    });
  }

  void _refresh() {
    ref.invalidate(weekShiftsProvider);
    ref.invalidate(todaysShiftsProvider);
    ref.invalidate(shiftTemplatesProvider);
  }

  /// Copies the day immediately before the selected one onto it.
  ///
  /// "Immediately before" is a calendar day, not a day of this week: on the
  /// first day of a week the source is the last day of the previous one,
  /// which is what the user means and what the repository's date-based copy
  /// already does. Shifts arrive unstaffed and a day+time that already has a
  /// shift is skipped, so pressing this twice adds nothing the second time.
  Future<void> _copyPreviousDay() async {
    setState(() => _busy = true);
    final result = await ref.read(shiftRepositoryProvider).copyDay(
          detachmentId: widget.detachmentId,
          fromDay: addDays(widget.day, -1),
          toDay: widget.day,
        );
    _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      success: (added, {stale = false}) =>
          _say(added == 0 ? S.copyPreviousDayEmpty : S.copyPreviousDayDone),
      failure: (message, _) => _say(message),
      offline: (_) => _say(S.offlineTitle),
    );
  }

  Future<void> _openTemplates() async {
    await showAppSheet<void>(
      context: context,
      title: S.templatesTitle,
      child: _TemplatesBody(detachmentId: widget.detachmentId),
    );
    _refresh();
  }

  void _say(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enabled = onTap != null;
    return PressScale(
      onTap: onTap,
      enabled: enabled,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: label == null ? AppSpacing.md : AppSpacing.sm,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: c.primary),
              if (label != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(label!,
                      style: TextStyle(
                          color: c.ink2,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplatesBody extends ConsumerWidget {
  const _TemplatesBody({required this.detachmentId});

  final String detachmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      child: AsyncResultView<List<ShiftTemplate>>(
        value: ref.watch(shiftTemplatesProvider(detachmentId)),
        onRetry: () => ref.invalidate(shiftTemplatesProvider),
        loading: const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
        builder: (context, templates, stale) => templates.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text(S.applyTemplatesEmpty, textAlign: TextAlign.center),
              )
            : ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(S.templatesSub,
                      style:
                          TextStyle(color: c.ink3, fontSize: 12, height: 1.5)),
                  const SizedBox(height: AppSpacing.md),
                  for (final t in templates) ...[
                    _TemplateRow(template: t),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
      ),
    );
  }
}

/// How many days this repeat covers and the span it runs across. The count
/// and dates are separate facts so no middle dot can be mistaken for a zero.
Widget _dateSpan(ShiftTemplate template) {
  final first = template.firstDate;
  if (first == null) return const SizedBox.shrink();
  final last = template.lastDate;
  if (template.dayCount == 1 || last == null || last == first) {
    return AppMeta(parts: [AppMetaText.day(first)]);
  }
  return AppMeta(parts: [
    AppMetaText.count(template.dayCount, label: S.templateDays),
    AppMetaText('${AppTime.day(first)} – ${AppTime.day(last)}'),
  ]);
}

class _TemplateRow extends ConsumerWidget {
  const _TemplateRow({required this.template});

  final ShiftTemplate template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                template.centerName,
                style: TextStyle(
                    color: c.ink, fontSize: 14, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Text(
                AppTime.minuteRange(template.startMinutes, template.endMinutes),
                style: AppTypography.digits(c.ink3, size: 12),
              ),
              const SizedBox(height: 4),
              _dateSpan(template),
            ],
          ),
        ),
        // Editing the days is the primary action here — it is why a saved
        // template is worth keeping around. Stopping it is the destructive
        // one, so it reads as the quieter of the two.
        IconButton(
          tooltip: S.templateEdit,
          icon: const Icon(Icons.edit_calendar_outlined),
          color: c.primary,
          onPressed: () =>
              showTemplateEditor(context: context, template: template),
        ),
        TextButton(
          onPressed: () async {
            await ref.read(shiftRepositoryProvider).stopTemplate(template.id);
            ref.invalidate(shiftTemplatesProvider);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(S.templateStopped)));
            }
          },
          style: TextButton.styleFrom(foregroundColor: c.crit),
          child: const Text(S.templateStop),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Day body
// ---------------------------------------------------------------------------

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.count,
    required this.onAdd,
  });

  final DateTime day;
  final int count;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Row(children: [
      Expanded(
        child: Text(
          AppTime.weekdayDay(day),
          style: AppTypography.eyebrow(c),
        ),
      ),
      if (onAdd != null)
        PressScale(
          onTap: onAdd,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
            decoration: BoxDecoration(
              color: c.primaryTint,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_rounded, size: 18, color: c.primary),
              const SizedBox(width: 6),
              Text(S.addShift,
                  style: TextStyle(
                      color: c.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
    ]);
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.historical, required this.onAdd});

  /// Changes what the emptiness *means*: on a live schedule it is work not
  /// done yet, on a finished one it is a week the detachment did not run.
  final bool historical;

  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: EmptyState(
        icon: Icons.event_available_outlined,
        title: historical ? S.historicalNoShiftsInWeek : S.noShiftsToday,
        body: historical ? S.historicalNoShiftsInWeekSub : S.noShiftsTodaySub,
        actionLabel: onAdd == null ? null : S.addShift,
        onAction: onAdd,
      ),
    );
  }
}

/// A shift, as a summary you tap.
///
/// Four things and no more: where and when, whether it is covered, and who
/// is answerable for it. The roster used to be here too — three rows plus
/// "+N more" — and it made every card tall enough that a day with four
/// shifts needed scrolling before you could compare them. Names are not what
/// you choose a card *by*; the supervisor's name is, because that is the
/// person you would go and ask.
///
/// So the full attendee list moved to where it is actually worked with.
/// Tapping anywhere opens [showShiftManageSheet], which carries every
/// per-shift action — both assignment routes, quick-fill, the whole roster,
/// attendance, check-in / out, edit, delete — unchanged.
class _ShiftCard extends ConsumerWidget {
  const _ShiftCard({
    required this.shift,
    required this.detachmentId,
    required this.canAssign,
    required this.canRecord,
    required this.canOverride,
    required this.canManage,
    required this.canDelete,
  });

  final Shift shift;
  final String detachmentId;
  final bool canAssign;
  final bool canRecord;
  final bool canOverride;
  final bool canManage;
  final bool canDelete;

  bool get _canOpen =>
      canAssign || canRecord || canOverride || canManage || canDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final t = Theme.of(context).textTheme;
    final running = shift.isRunningNow;
    final manager = shift.manager;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.4;
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Flexible(
            child: Tooltip(
              message: shift.centerName,
              excludeFromSemantics: true,
              child: Text(
                shift.centerName,
                style: t.titleMedium,
                maxLines: largeText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (shift.templateId != null) ...[
            const SizedBox(width: 6),
            Tooltip(
              message: S.templatesTitle,
              child: Icon(
                Icons.event_repeat_rounded,
                size: 14,
                color: c.ink3,
              ),
            ),
          ],
        ]),
        const SizedBox(height: 2),
        Text(
          AppTime.minuteRange(shift.startMinutes, shift.endMinutes),
          style: AppTypography.digits(c.ink2, size: 14),
        ),
      ],
    );
    final coverage = StatusChip(
      kind: running
          ? StatusKind.info
          : shift.hasCoverageGap
              ? StatusKind.warn
              : StatusKind.ok,
      label: running
          ? S.now
          : shift.hasCoverageGap
              ? '${S.coverageGap} ${AppNumber.count(shift.gap)}'
              : S.shiftCoverageOk,
    );

    return PressScale(
      onTap: _canOpen
          ? () => showShiftManageSheet(
                context: context,
                ref: ref,
                shift: shift,
                detachmentId: detachmentId,
                canAssign: canAssign,
                canRecord: canRecord,
                canOverride: canOverride,
                canManage: canManage,
                canDelete: canDelete,
              )
          : null,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: running ? c.primary : c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (largeText) ...[
              identity,
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: coverage,
              ),
            ] else
              Row(children: [
                Expanded(child: identity),
                coverage,
              ]),
            const SizedBox(height: AppSpacing.md),
            _CoverageBar(shift: shift),
            const SizedBox(height: AppSpacing.sm),
            // The one name on the card. A shift with no supervisor says so
            // plainly instead of leaving a blank line — an unassigned shift
            // is exactly the one someone needs to open.
            Row(children: [
              Icon(
                manager == null
                    ? Icons.person_off_outlined
                    : Icons.badge_outlined,
                size: 15,
                color: manager == null ? c.warn : c.ink3,
              ),
              const SizedBox(width: 6),
              Text(
                '${S.shiftManager}:',
                style: TextStyle(color: c.ink3, fontSize: 12),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  manager?.name ?? S.shiftManagerUnset,
                  style: TextStyle(
                    color: manager == null ? c.warn : c.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: largeText ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Assigned against needed, as a bar rather than a fraction alone. A number
/// says how short the shift is; the bar says it at a glance across a list.
class _CoverageBar extends StatelessWidget {
  const _CoverageBar({required this.shift});

  final Shift shift;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fill = shift.needed == 0 ? 1.0 : shift.assigned / shift.needed;
    final color = fill >= 1
        ? c.ok
        : fill >= 0.7
            ? c.warn
            : c.crit;
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: SizedBox(
          height: 6,
          child: Stack(children: [
            Container(color: c.surface3),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: fill.clamp(0, 1)),
              duration:
                  effectiveValueDuration(context, MotionTokens.progressFill),
              curve: effectiveCurve(context, MotionTokens.enter),
              builder: (context, v, _) => FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: v,
                child: Container(color: color),
              ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 6),
      Row(children: [
        Text(S.shiftAssignedOfNeeded,
            style: TextStyle(color: c.ink3, fontSize: 12)),
        const SizedBox(width: 6),
        Text(
          AppNumber.ratio(shift.assigned, shift.needed),
          style: AppTypography.digits(c.ink, size: 14),
        ),
      ]),
    ]);
  }
}
