import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../demo/data/demo_workspace.dart';
import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../team/data/team_providers.dart';
import '../domain/shift_conflict_snapshot.dart';
import '../domain/shift_models.dart';
import '../domain/shift_repository.dart';
import 'in_memory_shift_conflict_snapshot_store.dart';
import 'mock_shift_repository.dart';

final shiftRepositoryProvider = Provider<ShiftRepository>((ref) {
  // The mock resolves assignments against the same roster the Members tab
  // reads, so the two screens can never disagree about who exists.
  return ref.watch(demoWorkspaceProvider)?.shifts ??
      MockShiftRepository(
        ref.watch(teamRepositoryProvider),
        clock: ref.watch(clockProvider),
      );
});

/// Where the current-as-of-detection snapshot for a conflicted shift write
/// is kept. Override with a real (encrypted-DB backed) store in a shipping
/// build — see `ShiftConflictSnapshotStore`'s own doc comment.
final shiftConflictSnapshotStoreProvider =
    Provider<ShiftConflictSnapshotStore>((ref) {
  return InMemoryShiftConflictSnapshotStore();
});

/// Cache key for one week of one detachment's schedule.
///
/// A record-shaped key, per `DETACHMENT-SCOPING.md` §2 rule 1: the detachment
/// id is part of the key, so two detachments cannot collide on one entry.
class WeekQuery {
  WeekQuery({required this.detachmentId, required DateTime weekStart})
      : weekStart = startOfWeek(weekStart);

  final String detachmentId;
  final DateTime weekStart;

  WeekQuery shifted(int weeks) => WeekQuery(
        detachmentId: detachmentId,
        weekStart: addDays(weekStart, 7 * weeks),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeekQuery &&
          other.detachmentId == detachmentId &&
          other.weekStart == weekStart;

  @override
  int get hashCode => Object.hash(detachmentId, weekStart);
}

/// The selected week on the schedule tab, per detachment.
///
/// Family state, not a single global — a week picked in one detachment must
/// not be sitting there when another opens (`DETACHMENT-SCOPING.md` §2,
/// rule 3).
final selectedWeekProvider = StateProvider.autoDispose.family<DateTime, String>(
    (ref, detachmentId) => startOfWeek(ref.watch(clockProvider)()));

/// The selected day inside that week, as an offset 0–6 from Saturday.
final selectedDayOffsetProvider =
    StateProvider.autoDispose.family<int, String>((ref, detachmentId) {
  // Open on today when today is inside the shown week — the day someone
  // opening the schedule almost always wants.
  final now = ref.watch(clockProvider)();
  return dateOnly(now).difference(startOfWeek(now)).inDays;
});

final weekShiftsProvider = FutureProvider.autoDispose
    .family<Result<List<Shift>>, WeekQuery>((ref, q) async {
  return ref.read(shiftRepositoryProvider).listForWeek(
        q.detachmentId,
        q.weekStart,
      );
});

final todaysShiftsProvider = FutureProvider.autoDispose
    .family<Result<List<Shift>>, String>((ref, detId) async {
  return ref.read(shiftRepositoryProvider).listForDetachmentToday(detId);
});

/// How far back the schedule is searched for a detachment's last working day.
///
/// Bounded on purpose (§24): finding the week a finished detachment last ran
/// in must not turn into pulling every shift it ever had. Six months covers a
/// detachment that runs ten to fifteen days many times over.
const Duration scheduleLookback = Duration(days: 180);

/// The most recent day [detachmentId] actually ran a shift on, or `null` if it
/// ran none inside [scheduleLookback].
///
/// Only a *finished* detachment's schedule asks for this. A live one opens on
/// this week, which is the week the person opening it means; an archived one
/// opened on this week would show an empty day forever and read as broken.
/// One bounded range read, and only on the archive path.
final lastScheduledDayProvider = FutureProvider.autoDispose
    .family<DateTime?, String>((ref, detachmentId) async {
  final now = ref.watch(clockProvider)();
  final result = await ref.read(shiftRepositoryProvider).listForRange(
        detachmentId,
        dateOnly(now).subtract(scheduleLookback),
        dateOnly(now),
      );
  final shifts = result.when(
    success: (List<Shift> data, {bool stale = false}) => data,
    failure: (_, __) => const <Shift>[],
    offline: (cached) => cached ?? const <Shift>[],
  );
  if (shifts.isEmpty) return null;
  return shifts.map((s) => s.date).reduce((a, b) => a.isAfter(b) ? a : b);
});

final shiftByIdProvider =
    FutureProvider.autoDispose.family<Result<Shift>, String>((ref, id) async {
  return ref.read(shiftRepositoryProvider).byId(id);
});

final shiftTemplatesProvider = FutureProvider.autoDispose
    .family<Result<List<ShiftTemplate>>, String>((ref, detId) async {
  return ref.read(shiftRepositoryProvider).templates(detId);
});

/// Every shift a template has materialised. The shift editor reads this to
/// show which repeat days are locked because they already have people on them.
final templateOccurrencesProvider = FutureProvider.autoDispose
    .family<Result<List<Shift>>, String>((ref, templateId) async {
  return ref.read(shiftRepositoryProvider).shiftsForTemplate(templateId);
});

final shiftCandidatesProvider = FutureProvider.autoDispose
    .family<Result<List<ShiftCandidate>>, String>((ref, shiftId) async {
  return ref.read(shiftRepositoryProvider).candidatesFor(shiftId);
});

class AttendanceStatsQuery {
  AttendanceStatsQuery({
    required this.detachmentId,
    required DateTime from,
    required DateTime to,
    this.memberId,
  })  : from = dateOnly(from),
        to = dateOnly(to);

  final String detachmentId;
  final DateTime from;
  final DateTime to;
  final String? memberId;

  @override
  bool operator ==(Object other) =>
      other is AttendanceStatsQuery &&
      other.detachmentId == detachmentId &&
      other.from == from &&
      other.to == to &&
      other.memberId == memberId;

  @override
  int get hashCode => Object.hash(detachmentId, from, to, memberId);
}

final attendanceStatisticsProvider = FutureProvider.autoDispose
    .family<Result<AttendanceStatistics>, AttendanceStatsQuery>((ref, q) async {
  final result = await ref.read(shiftRepositoryProvider).listForRange(
        q.detachmentId,
        q.from,
        q.to,
      );
  return result.when(
    success: (shifts, {stale = false}) => Success(
      AttendanceStatistics.fromShifts(shifts, memberId: q.memberId),
      stale: stale,
    ),
    failure: (message, code) => Failure(message, code: code),
    offline: (cached) => Offline(
      cached: cached == null
          ? null
          : AttendanceStatistics.fromShifts(cached, memberId: q.memberId),
    ),
  );
});

class AttendanceEntryDefaults {
  const AttendanceEntryDefaults({this.checkInAt, this.checkOutAt});

  final DateTime? checkInAt;
  final DateTime? checkOutAt;

  AttendanceEntryDefaults copyWith(
          {DateTime? checkInAt, DateTime? checkOutAt}) =>
      AttendanceEntryDefaults(
        checkInAt: checkInAt ?? this.checkInAt,
        checkOutAt: checkOutAt ?? this.checkOutAt,
      );
}

/// Kept per shift so entering attendance for the next member starts with the
/// last date and time used, without mutating any previous member's record.
final attendanceEntryDefaultsProvider =
    StateProvider.family<AttendanceEntryDefaults, String>(
  (ref, shiftId) => const AttendanceEntryDefaults(),
);
