import 'package:flutter/material.dart';

import '../../../core/format/app_date.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../l10n/strings.dart';
import '../domain/shift_models.dart';

/// Pick the exact days a shift runs on.
///
/// A rolling window of [windowDays] starting at [firstDay], which is long
/// enough to cover a whole detachment — they run ten to fifteen days — so the
/// user points at the days they want rather than describing a weekly rule
/// that will outlive the detachment.
///
/// Days in [locked] are shown selected and cannot be toggled off. Two things
/// end up there and for the same reason: the anchor day a shift is being
/// created on, and any day whose shift already has people assigned. Removing
/// either would throw away work the picker cannot see.
///
/// More than one day selected means the shift repeats — there is no separate
/// switch and no "apply" step. Used by the shift editor and by the template
/// editor, which is why the heading and help line are parameters: the two
/// surfaces are editing the same day set from different directions.
class RepeatDaysPicker extends StatelessWidget {
  const RepeatDaysPicker({
    super.key,
    required this.firstDay,
    required this.windowDays,
    required this.selected,
    required this.locked,
    required this.loading,
    required this.onToggle,
    this.title = S.repeatOnDays,
    this.help = S.repeatOnDaysHelp,
  });

  /// First day of the window. Everything before it is out of reach, which
  /// is correct for both callers: a new shift cannot repeat into the past,
  /// and a template's window starts at its own first day.
  final DateTime firstDay;

  final int windowDays;
  final Set<DateTime> selected;

  /// Days that are selected and cannot be turned off.
  final Set<DateTime> locked;

  final bool loading;
  final ValueChanged<DateTime> onToggle;

  /// Heading and help line, so the same grid reads correctly whether the
  /// user is repeating one shift or editing a saved template.
  final String title;
  final String help;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final repeats = selected.length > 1;
    final days = [
      for (int i = 0; i < windowDays; i++) addDays(firstDay, i),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: repeats ? c.primaryTint : c.surface,
        border: Border.all(color: repeats ? c.primary : c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.event_repeat_rounded,
                size: 18, color: repeats ? c.primary : c.ink3),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: repeats ? c.primary : c.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (repeats)
              Text(
                '${toArabicIndic('${selected.length}')} ${S.daysUnit}',
                style: AppTypography.digits(c.primary, size: 13),
              ),
          ]),
          const SizedBox(height: 2),
          Text(help,
              style: TextStyle(color: c.ink3, fontSize: 11, height: 1.4)),
          const SizedBox(height: AppSpacing.md),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final day in days)
                  _DayPill(
                    day: day,
                    selected: selected.contains(dateOnly(day)),
                    locked: locked.contains(dateOnly(day)),
                    onTap: () => onToggle(dateOnly(day)),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.day,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PressScale(
      onTap: onTap,
      enabled: !locked,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: AnimatedContainer(
        duration: effectiveDuration(context, MotionTokens.short),
        curve: effectiveCurve(context, MotionTokens.standard),
        width: 46,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? c.primary : c.surface,
          border: Border.all(color: selected ? c.primary : c.line2),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              // The distinct calendar initial — `weekdayOf(...).substring(0,
              // 2)` is «ال» for all seven days.
              AppDate.weekdayInitialOf(day),
              style: TextStyle(
                color: selected ? c.primaryInk : c.ink3,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              toArabicIndic('${day.day}'),
              style: AppTypography.digits(
                selected ? c.primaryInk : c.ink,
                size: 14,
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: 12,
              child: locked
                  ? Icon(Icons.lock_rounded,
                      size: 11, color: selected ? c.primaryInk : c.ink3)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
