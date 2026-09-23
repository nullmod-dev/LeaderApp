import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/app_date.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/motion/press_scale.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../l10n/strings.dart';
import '../data/shift_providers.dart';
import '../domain/shift_models.dart';
import 'repeat_days_picker.dart';

/// Create or edit one shift.
///
/// The whole design of this sheet is one decision: **nobody should have to
/// operate a time picker to schedule an ordinary shift.** Three presets cover
/// what a detachment actually runs, so the common case is two taps — pick the
/// period, save. The custom row is there for the exception, not the rule, and
/// the number of people needed is a stepper rather than a keyboard field
/// because it is always a small number and always adjusted by one.
Future<bool> showShiftEditor({
  required BuildContext context,
  required String detachmentId,
  required DateTime date,
  required String defaultCenter,
  Shift? existing,
}) async {
  final saved = await showAppSheet<bool>(
    context: context,
    title: existing == null
        ? '${S.addShift} · ${AppDate.weekdayOf(date)}'
        : S.editShift,
    expanded: true,
    child: _ShiftEditor(
      detachmentId: detachmentId,
      date: date,
      defaultCenter: defaultCenter,
      existing: existing,
    ),
  );
  return saved ?? false;
}

class _ShiftEditor extends ConsumerStatefulWidget {
  const _ShiftEditor({
    required this.detachmentId,
    required this.date,
    required this.defaultCenter,
    this.existing,
  });

  final String detachmentId;
  final DateTime date;
  final String defaultCenter;
  final Shift? existing;

  @override
  ConsumerState<_ShiftEditor> createState() => _ShiftEditorState();
}

class _ShiftEditorState extends ConsumerState<_ShiftEditor> {
  late final TextEditingController _center;
  late ShiftPeriod _period;
  late int _start;
  late int _end;
  late int _needed;

  /// The anchor day, always locked on. Extra days here mean the shift repeats.
  late final DateTime _anchorDay;
  late Set<DateTime> _repeatDays;

  /// Repeat days that cannot be unpicked: the anchor, and (in edit mode) any
  /// day whose materialised shift already has people on it.
  late Set<DateTime> _lockedDays;
  bool _loadingRepeat = false;

  bool _busy = false;
  String? _error;
  final _formKey = GlobalKey<FormState>();

  bool get _isNew => widget.existing == null;

  /// The rolling window the picker offers: 21 days from the anchor.
  static const _repeatWindowDays = 21;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _center =
        TextEditingController(text: e?.centerName ?? widget.defaultCenter);
    // A new shift opens on the morning preset rather than on an empty form.
    // A default that is right most of the time is the difference between
    // "fill this in" and "confirm this".
    _period = e == null ? ShiftPeriod.morning : e.period;
    final times = _period.times;
    _start = e?.startMinutes ?? times!.$1;
    _end = e?.endMinutes ?? times!.$2;
    _needed = e?.needed ?? 6;

    _anchorDay = dateOnly(widget.date);
    _repeatDays = {_anchorDay};
    _lockedDays = {_anchorDay};

    // Editing a shift that already repeats: pull the template's day set so the
    // picker opens showing every day it runs, with the staffed ones locked.
    if (e?.templateId != null) {
      _loadingRepeat = true;
      Future.microtask(() => _loadRepeatDays(e!.templateId!));
    }
  }

  Future<void> _loadRepeatDays(String templateId) async {
    final result =
        await ref.read(shiftRepositoryProvider).shiftsForTemplate(templateId);
    if (!mounted) return;
    final shifts = result.when(
      success: (data, {stale = false}) => data,
      failure: (_, __) => const <Shift>[],
      offline: (_) => const <Shift>[],
    );
    setState(() {
      _loadingRepeat = false;
      for (final s in shifts) {
        final day = dateOnly(s.date);
        _repeatDays.add(day);
        if (s.attendees.isNotEmpty) _lockedDays.add(day);
      }
    });
  }

  @override
  void dispose() {
    _center.dispose();
    super.dispose();
  }

  void _pickPeriod(ShiftPeriod p) {
    setState(() {
      _period = p;
      final t = p.times;
      if (t != null) {
        _start = t.$1;
        _end = t.$2;
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    setState(() {
      final minutes = picked.hour * 60 + picked.minute;
      if (isStart) {
        _start = minutes;
      } else {
        _end = minutes;
      }
      // Editing a time by hand is what makes a shift custom. Saying so keeps
      // the preset row honest instead of leaving "morning" selected next to
      // 09:15.
      _period = ShiftPeriodTimes.match(_start, _end);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final crosses = _end <= _start;

    return Form(
      key: _formKey,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const Key('shift-form-scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isNew) ...[
                    Row(children: [
                      Icon(Icons.lightbulb_outline_rounded,
                          size: 15, color: c.ink3),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(S.guideAddShift,
                            style: TextStyle(
                                color: c.ink3, fontSize: 12, height: 1.5)),
                      ),
                    ]),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  const _Label(S.shiftPeriod),
                  const SizedBox(height: AppSpacing.sm),
                  Row(children: [
                    for (final p in ShiftPeriod.values) ...[
                      Expanded(
                        child: _PeriodTile(
                          period: p,
                          selected: _period == p,
                          onTap: () => _pickPeriod(p),
                        ),
                      ),
                      if (p != ShiftPeriod.values.last)
                        const SizedBox(width: 6),
                    ],
                  ]),
                  const SizedBox(height: AppSpacing.lg),
                  Row(children: [
                    Expanded(
                      child: _TimeField(
                        label: S.shiftStart,
                        value: AppDate.hm(_start),
                        onTap: () => _pickTime(isStart: true),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _TimeField(
                        label: S.shiftEnd,
                        value: AppDate.hm(_end),
                        onTap: () => _pickTime(isStart: false),
                      ),
                    ),
                  ]),
                  if (crosses) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(children: [
                      Icon(Icons.nightlight_round, size: 14, color: c.info),
                      const SizedBox(width: 6),
                      Text(S.crossesMidnight,
                          style: TextStyle(color: c.info, fontSize: 12)),
                    ]),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  const _Label(S.shiftCenter),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _center,
                    decoration: const InputDecoration(
                        hintText: S.detachmentCenterPlaceholder),
                    textInputAction: TextInputAction.done,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? S.required
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const _Label(S.shiftNeededLabel),
                  const SizedBox(height: 6),
                  _Stepper(
                    value: _needed,
                    min: 1,
                    max: 40,
                    onChanged: (v) => setState(() => _needed = v),
                  ),
                  const SizedBox(height: 6),
                  Text(S.shiftNeededHelp,
                      style:
                          TextStyle(color: c.ink3, fontSize: 12, height: 1.5)),
                  const SizedBox(height: AppSpacing.lg),
                  RepeatDaysPicker(
                    firstDay: _anchorDay,
                    windowDays: _repeatWindowDays,
                    selected: _repeatDays,
                    locked: _lockedDays,
                    loading: _loadingRepeat,
                    onToggle: (day) => setState(() {
                      if (_lockedDays.contains(day)) return;
                      if (!_repeatDays.remove(day)) _repeatDays.add(day);
                    }),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
          Container(
            key: const Key('shift-sticky-action'),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: c.bg,
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    key: const Key('shift-save-error'),
                    style: TextStyle(color: c.crit, fontSize: 12),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                FilledButton(
                  key: const Key('shift-save-button'),
                  // Block save until the existing repeat set has loaded, or a
                  // fast save would reconcile against just the anchor day and
                  // drop the other occurrences.
                  onPressed: (_busy || _loadingRepeat) ? null : _save,
                  child: _busy
                      ? SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.primaryInk,
                          ),
                        )
                      : Text(_isNew ? S.addShift : S.saveChanges),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_start == _end) {
      setState(() => _error = S.startAfterEnd);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(shiftRepositoryProvider);
    // Days other than the anchor mean the shift repeats.
    final extraDays = _repeatDays.where((d) => d != _anchorDay).toList()
      ..sort();

    String? errorMessage;
    bool? offline;
    String? anchorId = widget.existing?.id;

    if (_isNew) {
      final created = await repo.create(
        detachmentId: widget.detachmentId,
        date: widget.date,
        centerName: _center.text.trim(),
        startMinutes: _start,
        endMinutes: _end,
        needed: _needed,
        repeatOn: extraDays,
      );
      created.when(
        success: (shift, {stale = false}) => anchorId = shift.id,
        failure: (message, _) => errorMessage = message,
        offline: (_) => offline = true,
      );
    } else {
      final updated = await repo.update(widget.existing!.copyWith(
        centerName: _center.text.trim(),
        startMinutes: _start,
        endMinutes: _end,
        needed: _needed,
      ));
      updated.when(
        success: (_, {stale = false}) {},
        failure: (message, _) => errorMessage = message,
        offline: (_) => offline = true,
      );

      // Reconcile the repeat set on save — no separate "apply" step. Only run
      // it when there is something to reconcile: an edit that touched the day
      // set, or a shift that already sits behind a template.
      final touchesRepeat =
          extraDays.isNotEmpty || widget.existing!.templateId != null;
      if (errorMessage == null &&
          offline != true &&
          anchorId != null &&
          touchesRepeat) {
        final reconciled =
            await repo.updateRepeat(anchorId, _repeatDays.toList());
        reconciled.when(
          success: (_, {stale = false}) {},
          failure: (message, _) => errorMessage = message,
          offline: (_) => offline = true,
        );
      }
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (errorMessage != null) {
      setState(() => _error = errorMessage);
      return;
    }
    if (offline == true) {
      setState(() => _error = S.offlineTitle);
      return;
    }
    ref.invalidate(weekShiftsProvider);
    ref.invalidate(todaysShiftsProvider);
    ref.invalidate(shiftTemplatesProvider);
    ref.invalidate(templateOccurrencesProvider);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(const SnackBar(content: Text(S.shiftSaved)));
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          color: context.c.ink2,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      );
}

class _PeriodTile extends StatelessWidget {
  const _PeriodTile({
    required this.period,
    required this.selected,
    required this.onTap,
  });

  final ShiftPeriod period;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (label, icon) = switch (period) {
      ShiftPeriod.morning => (S.periodMorning, Icons.wb_sunny_outlined),
      ShiftPeriod.evening => (S.periodEvening, Icons.wb_twilight_rounded),
      ShiftPeriod.night => (S.periodNight, Icons.nightlight_round),
      ShiftPeriod.custom => (S.periodCustom, Icons.tune_rounded),
    };
    final times = period.times;
    return PressScale(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: AnimatedContainer(
        duration: effectiveDuration(context, MotionTokens.short),
        curve: effectiveCurve(context, MotionTokens.standard),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? c.primaryTint : c.surface,
          border: Border.all(color: selected ? c.primary : c.line),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Column(children: [
          Icon(icon, size: 18, color: selected ? c.primary : c.ink3),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                color: selected ? c.primary : c.ink2,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              )),
          if (times != null) ...[
            const SizedBox(height: 2),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Text(
                AppDate.minuteRange(times.$1, times.$2),
                style: TextStyle(color: c.ink3, fontSize: 10),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.ink2, fontSize: 13)),
        const SizedBox(height: 6),
        PressScale(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line2),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: c.ink3),
                // A clock reads left-to-right even in an RTL layout.
                Directionality(
                  textDirection: TextDirection.ltr,
                  child:
                      Text(value, style: AppTypography.digits(c.ink, size: 16)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Plus/minus around a number. No keyboard, so no invalid state to validate
/// and no numeric-keypad detour for a value that is almost always nudged by
/// one.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line2),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(children: [
        _Round(
          icon: Icons.remove_rounded,
          enabled: value > min,
          onTap: () => onChanged(value - 1),
        ),
        Expanded(
          child: Center(
            child: TabularDigits(
              toArabicIndic('$value'),
              style: AppTypography.digits(c.ink, size: 18),
            ),
          ),
        ),
        _Round(
          icon: Icons.add_rounded,
          enabled: value < max,
          onTap: () => onChanged(value + 1),
        ),
      ]),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PressScale(
      onTap: onTap,
      enabled: enabled,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? c.primaryTint : c.surface2,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: enabled ? c.primary : c.ink3),
      ),
    );
  }
}
