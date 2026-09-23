import '../../../core/format/app_date.dart';
import '../../../core/format/app_time.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../l10n/strings.dart';
import '../../conflict/domain/conflict_models.dart';
import '../domain/shift_models.dart';

/// Builds the generic conflict view model from two typed [Shift] records.
///
/// This adapter is where shift field names and formatting live. The generic
/// conflict screen never sees `shift_manager_id`, a record JSON map, member
/// ids, or any field the shift feature did not explicitly select here.
ConflictPresentation presentShiftConflict({
  required String conflictId,
  required String localOperationId,
  required Shift local,
  required Shift current,
  String? baseVersion,
  String? currentVersion,
}) {
  final differences = <ConflictFieldComparison>[];

  void add({
    required bool changed,
    required String fieldId,
    required String label,
    required String localValue,
    required String currentValue,
    ConflictValueDirection direction = ConflictValueDirection.natural,
  }) {
    if (!changed) return;
    differences.add(ConflictFieldComparison(
      fieldId: fieldId,
      label: label,
      localValue: localValue,
      currentValue: currentValue,
      valueDirection: direction,
    ));
  }

  add(
    changed: local.manager?.id != current.manager?.id,
    fieldId: 'manager',
    label: S.shiftManager,
    localValue: local.manager?.name ?? S.shiftManagerUnset,
    currentValue: current.manager?.name ?? S.shiftManagerUnset,
  );
  add(
    changed: local.date != current.date,
    fieldId: 'date',
    label: S.conflictShiftDate,
    localValue:
        AppTime.weekdayDay(local.date),
    currentValue:
        AppTime.weekdayDay(current.date),
  );
  add(
    changed: local.startMinutes != current.startMinutes ||
        local.endMinutes != current.endMinutes,
    fieldId: 'time',
    label: S.conflictShiftTime,
    localValue: AppDate.minuteRange(local.startMinutes, local.endMinutes),
    currentValue: AppDate.minuteRange(current.startMinutes, current.endMinutes),
    direction: ConflictValueDirection.ltr,
  );
  add(
    changed: local.needed != current.needed,
    fieldId: 'needed',
    label: S.shiftNeededLabel,
    localValue: toArabicIndic('${local.needed}'),
    currentValue: toArabicIndic('${current.needed}'),
  );

  // A stale-write response should identify at least one differing field. If
  // the server cannot do that yet, the owning integration must fetch/compare
  // typed records before opening this screen rather than show raw payloads.
  assert(differences.isNotEmpty);

  return ConflictPresentation(
    conflictId: conflictId,
    localOperationId: localOperationId,
    entityType: 'shift',
    entityId: local.id,
    recordTitle: '${S.conflictShiftRecord} · ${local.centerName}',
    recordSubtitle:
        AppTime.weekdayDay(local.date),
    baseVersion: baseVersion,
    currentVersion: currentVersion,
    differences: differences,
  );
}
