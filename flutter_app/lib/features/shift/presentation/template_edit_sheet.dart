import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/async_result.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../l10n/strings.dart';
import '../data/shift_providers.dart';
import '../domain/shift_models.dart';
import 'repeat_days_picker.dart';

/// Edit which days a saved template runs on.
///
/// This is the *template* half of the repeat feature. The shift editor lets
/// you set the days while creating or editing one shift; this lets you come
/// back to a repeat you already made and change its days without hunting for
/// one of its occurrences first.
///
/// Both surfaces drive the same grid ([RepeatDaysPicker]) and the same
/// reconcile rules in the repository, so there is exactly one repetition
/// model in the app — a day is added by materialising a shift, removed by
/// deleting an *empty* shift, and a day whose shift has people on it is
/// locked in the grid and can never be removed by a date edit.
///
/// Returns `true` when the days were saved.
Future<bool?> showTemplateEditor({
  required BuildContext context,
  required ShiftTemplate template,
}) {
  return showAppSheet<bool>(
    context: context,
    title: S.templateEditTitle,
    child: _TemplateEditBody(template: template),
  );
}

class _TemplateEditBody extends ConsumerStatefulWidget {
  const _TemplateEditBody({required this.template});

  final ShiftTemplate template;

  @override
  ConsumerState<_TemplateEditBody> createState() => _TemplateEditBodyState();
}

class _TemplateEditBodyState extends ConsumerState<_TemplateEditBody> {
  /// At least three weeks of room, which covers a whole detachment — they
  /// run ten to fifteen days — and always enough to show every day the
  /// template already occupies, however far out it reaches.
  static const int _minWindowDays = 21;

  late final Set<DateTime> _selected = {...widget.template.dates};
  bool _saving = false;

  /// Where the grid starts: the earlier of today and the template's first
  /// day, so an existing day is never off the left edge of the window.
  DateTime get _windowStart {
    final today = dateOnly(DateTime.now());
    final first = widget.template.firstDate;
    if (first == null || !first.isBefore(today)) return today;
    return first;
  }

  int get _windowDays {
    final last = widget.template.lastDate;
    final span = last == null ? 0 : last.difference(_windowStart).inDays + 1;
    return span > _minWindowDays ? span : _minWindowDays;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final occurrences = ref.watch(
      templateOccurrencesProvider(widget.template.id),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      child: AsyncResultView<List<Shift>>(
        value: occurrences,
        onRetry: () => ref.invalidate(templateOccurrencesProvider),
        loading: const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
        builder: (context, shifts, stale) {
          // A day whose shift already has people on it cannot be removed —
          // the repository refuses it, so the grid must not offer it either.
          final locked = <DateTime>{
            for (final s in shifts)
              if (s.attendees.isNotEmpty) s.date,
          };
          final aboutToStop = _selected.length < 2;

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RepeatDaysPicker(
                firstDay: _windowStart,
                windowDays: _windowDays,
                selected: _selected,
                locked: locked,
                loading: false,
                title: S.templateEditTitle,
                help: S.templateEditSub,
                onToggle: (day) {
                  if (locked.contains(day)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text(S.templateLockedDay)),
                    );
                    return;
                  }
                  setState(() {
                    if (!_selected.remove(day)) _selected.add(day);
                  });
                },
              ),
              if (aboutToStop) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  S.templateNeedsTwoDays,
                  style: TextStyle(color: c.warn, fontSize: 12, height: 1.5),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(locked),
                  child: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(S.save),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save(Set<DateTime> locked) async {
    setState(() => _saving = true);
    // Locked days go back in whatever the grid state says: the repository
    // folds them in anyway, and sending them keeps the two in step.
    final dates = <DateTime>{..._selected, ...locked}.toList()..sort();
    final result = await ref
        .read(shiftRepositoryProvider)
        .updateTemplateDates(widget.template.id, dates);
    ref.invalidate(shiftTemplatesProvider);
    ref.invalidate(templateOccurrencesProvider);
    ref.invalidate(weekShiftsProvider);
    ref.invalidate(todaysShiftsProvider);
    if (!mounted) return;
    setState(() => _saving = false);
    result.when(
      success: (_, {stale = false}) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(S.templateSaved)),
        );
      },
      failure: (message, _) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message))),
      offline: (_) => ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.offlineTitle))),
    );
  }
}
