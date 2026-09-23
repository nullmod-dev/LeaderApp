import '../../../core/time/calendar_day.dart';
import '../../team/domain/team_models.dart';
import 'attendance_correction.dart';

/// Calendar-day arithmetic, re-exported so every schedule file keeps reading
/// `dateOnly`/`addDays` from the domain it already imports. The definitions
/// live in `core/time/calendar_day.dart` because non-schedule code (date
/// formatting, reports) needs the same rule and must not import a feature.
export '../../../core/time/calendar_day.dart'
    show dateOnly, addDays, calendarDaysBetween;

/// Where a week begins in this app: **Saturday**.
///
/// Not a preference — it is how a Syrian volunteer week is actually worked,
/// and the whole schedule screen (the day strip, "copy last week", the weekly
/// repeat) reads off it. Kept in one place so nothing can disagree.
const int weekStartsOn = DateTime.saturday;

/// The Saturday on or before [d], at local midnight.
///
/// Steps by calendar day, not by `Duration`: subtracting six absolute days
/// from a Saturday midnight across a DST boundary lands at 23:00 or 01:00,
/// and a week start that is not midnight breaks every `s.date == day` in the
/// schedule. See `core/time/calendar_day.dart`.
DateTime startOfWeek(DateTime d) {
  final day = dateOnly(d);
  return addDays(day, -((day.weekday - weekStartsOn) % 7));
}

/// The three shifts almost every detachment actually runs, plus an escape
/// hatch. Offering these as one tap is the single biggest thing that makes
/// scheduling easy for someone who has never done it: nobody should have to
/// operate two time pickers to say "the morning shift".
enum ShiftPeriod { morning, evening, night, custom }

extension ShiftPeriodTimes on ShiftPeriod {
  /// Minutes from midnight. `night` deliberately ends *after* midnight.
  (int start, int end)? get times => switch (this) {
        ShiftPeriod.morning => (8 * 60, 14 * 60),
        ShiftPeriod.evening => (14 * 60, 20 * 60),
        ShiftPeriod.night => (20 * 60, 2 * 60),
        ShiftPeriod.custom => null,
      };

  /// Which preset a pair of times matches, or [ShiftPeriod.custom].
  static ShiftPeriod match(int start, int end) {
    for (final p in ShiftPeriod.values) {
      final t = p.times;
      if (t != null && t.$1 == start && t.$2 == end) return p;
    }
    return ShiftPeriod.custom;
  }
}

/// A repeating shift, as the exact set of days it runs on.
///
/// The legacy program stored a *weekly* template plus dated occurrences, which
/// suited a standing schedule that outlives any one week. A detachment here
/// runs for ten to fifteen days and then ends, so there is no standing weekly
/// rule to keep — what the user actually wants is to point at the specific
/// days a shift should exist. [dates] is therefore an explicit list of
/// day-dates (local midnight, sorted, no duplicates), not a weekday.
///
/// The template *owns* the shifts on those dates: creating or editing the
/// repeat set materialises the missing days and removes the surplus ones (a
/// day that has people assigned is never removed — see
/// `MockShiftRepository.updateRepeat`). Editing a single materialised shift
/// does not edit the template; one day's change is not the whole set's rule.
///
/// Stopping a template never touches the occurrences it already produced —
/// last month's attendance has to keep reading the same way after this
/// month's schedule changes.
class ShiftTemplate {
  ShiftTemplate({
    required this.id,
    required this.detachmentId,
    required this.centerName,
    required Iterable<DateTime> dates,
    required this.startMinutes,
    required this.endMinutes,
    required this.needed,
    this.active = true,
  }) : dates = _normalizeDates(dates);

  final String id;
  final String detachmentId;
  final String centerName;

  /// Every day this shift runs, as local midnight, ascending, deduplicated.
  final List<DateTime> dates;

  final int startMinutes;
  final int endMinutes;
  final int needed;
  final bool active;

  ShiftPeriod get period => ShiftPeriodTimes.match(startMinutes, endMinutes);

  int get dayCount => dates.length;
  DateTime? get firstDate => dates.isEmpty ? null : dates.first;
  DateTime? get lastDate => dates.isEmpty ? null : dates.last;

  static List<DateTime> _normalizeDates(Iterable<DateTime> input) {
    final seen = <DateTime>{for (final d in input) dateOnly(d)};
    return seen.toList()..sort();
  }

  ShiftTemplate copyWith({
    String? centerName,
    Iterable<DateTime>? dates,
    int? startMinutes,
    int? endMinutes,
    int? needed,
    bool? active,
  }) =>
      ShiftTemplate(
        id: id,
        detachmentId: detachmentId,
        centerName: centerName ?? this.centerName,
        dates: dates ?? this.dates,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
        needed: needed ?? this.needed,
        active: active ?? this.active,
      );

  factory ShiftTemplate.fromJson(Map<String, dynamic> j) => ShiftTemplate(
        id: j['id'] as String,
        detachmentId: j['detachmentId'] as String,
        centerName: j['centerName'] as String,
        dates: (j['dates'] as List)
            .map((e) => DateTime.parse(e as String))
            .toList(),
        startMinutes: j['startMinutes'] as int,
        endMinutes: j['endMinutes'] as int,
        needed: j['needed'] as int,
        active: (j['active'] as bool?) ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'detachmentId': detachmentId,
        'centerName': centerName,
        'dates': [for (final d in dates) d.toIso8601String()],
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'needed': needed,
        'active': active,
      };
}

/// One dated shift — the thing people are actually assigned to.
///
/// `assigned` and `hasCoverageGap` used to be stored fields that the caller
/// had to keep in step with the attendee list. They are derived now, so the
/// count on the card and the chips under it cannot drift apart.
class Shift {
  const Shift({
    required this.id,
    required this.detachmentId,
    required this.date,
    required this.centerName,
    required this.startMinutes,
    required this.endMinutes,
    required this.needed,
    required this.attendees,
    this.templateId,
    this.corrections = const [],
  });

  final String id;
  final String detachmentId;

  /// Local midnight of the day the shift *starts*. A night shift that runs
  /// past midnight still belongs to the day it began.
  final DateTime date;

  final String centerName;
  final int startMinutes;
  final int endMinutes;
  final int needed;
  final List<TeamMember> attendees;

  /// Set when the shift was produced by a weekly repeat. Editing the shift
  /// does not edit the template — one week's change is not next week's rule.
  final String? templateId;

  /// Append-only attendance corrections for this shift's attendees, oldest
  /// first. Lives here rather than on [TeamMember] because a `TeamMember`
  /// also doubles as a workshop's organising-team projection, which has no
  /// business carrying shift audit data — the correction belongs to the
  /// assignment, not the roster record. See
  /// `MockShiftRepository.addAttendanceCorrection`, the only writer.
  final List<AttendanceCorrection> corrections;

  /// [corrections] narrowed to one member, oldest first — what the
  /// attendance sheet's "سجل التصحيحات" section shows.
  List<AttendanceCorrection> correctionsFor(String memberId) => [
        for (final c in corrections)
          if (c.memberId == memberId) c,
      ];

  /// The person answerable for this shift — the assigned member whose role is
  /// [TeamRole.shiftSupervisor], or `null` when nobody on the shift holds it.
  ///
  /// Derived rather than stored: a supervisor is a person on the shift, and a
  /// stored field would be one more thing to keep in step with the attendee
  /// list. Where two supervisors are assigned the first one wins, which is
  /// the same order the roster shows them in — the card names *a* supervisor
  /// to ask, and the full list is one tap away in the management sheet.
  TeamMember? get manager {
    for (final a in attendees) {
      if (a.role == TeamRole.shiftSupervisor) return a;
    }
    return null;
  }

  int get assigned => attendees.length;
  int get gap => (needed - assigned).clamp(0, needed);
  bool get hasCoverageGap => assigned < needed;

  /// True when the shift runs past midnight, e.g. 20:00 → 02:00.
  bool get crossesMidnight => endMinutes <= startMinutes;

  DateTime get start => date.add(Duration(minutes: startMinutes));
  DateTime get end => date
      .add(Duration(days: crossesMidnight ? 1 : 0))
      .add(Duration(minutes: endMinutes));

  ShiftPeriod get period => ShiftPeriodTimes.match(startMinutes, endMinutes);

  int get coveragePercent =>
      needed == 0 ? 100 : ((assigned / needed) * 100).round().clamp(0, 100);

  /// Whole-hour accessors kept for the screens that only ever show hours.
  int get startHour => startMinutes ~/ 60;
  int get endHour => endMinutes ~/ 60;

  /// Two shifts collide when their real time ranges intersect — which is why
  /// [start] and [end] resolve the midnight crossing first. Assigning the
  /// same person to 20:00–02:00 and 00:00–06:00 is a double booking even
  /// though the two rows carry different dates.
  bool overlaps(Shift other) =>
      start.isBefore(other.end) && other.start.isBefore(end);

  bool get isPast => end.isBefore(DateTime.now());
  bool get isRunningNow {
    final now = DateTime.now();
    return !start.isAfter(now) && end.isAfter(now);
  }

  Shift copyWith({
    DateTime? date,
    String? centerName,
    int? startMinutes,
    int? endMinutes,
    int? needed,
    List<TeamMember>? attendees,
    String? templateId,
    List<AttendanceCorrection>? corrections,
  }) =>
      Shift(
        id: id,
        detachmentId: detachmentId,
        templateId: templateId ?? this.templateId,
        date: date ?? this.date,
        centerName: centerName ?? this.centerName,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
        needed: needed ?? this.needed,
        attendees: attendees ?? this.attendees,
        corrections: corrections ?? this.corrections,
      );

  factory Shift.fromJson(Map<String, dynamic> j) => Shift(
        id: j['id'] as String,
        detachmentId: j['detachmentId'] as String,
        templateId: j['templateId'] as String?,
        date: DateTime.parse(j['date'] as String),
        centerName: j['centerName'] as String,
        startMinutes: j['startMinutes'] as int,
        endMinutes: j['endMinutes'] as int,
        needed: j['needed'] as int,
        attendees: (j['attendees'] as List)
            .map((e) => TeamMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        corrections: ((j['corrections'] as List?) ?? const [])
            .map(
                (e) => AttendanceCorrection.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'detachmentId': detachmentId,
        if (templateId != null) 'templateId': templateId,
        'date': date.toIso8601String(),
        'centerName': centerName,
        'startMinutes': startMinutes,
        'endMinutes': endMinutes,
        'needed': needed,
        'attendees': attendees.map((a) => a.toJson()).toList(),
        if (corrections.isNotEmpty)
          'corrections': corrections.map((c) => c.toJson()).toList(),
      };
}

/// A roster member offered for assignment, with the one thing the person
/// assigning actually needs to know: whether they are already working.
///
/// The screen shows busy members rather than hiding them — a lead who cannot
/// find someone in the list assumes the list is broken, and then assigns them
/// twice through some other route.
class ShiftCandidate {
  const ShiftCandidate({
    required this.member,
    required this.busy,
    this.busyWith,
  });

  final TeamMember member;
  final bool busy;

  /// The shift they are already on, for the conflict line.
  final Shift? busyWith;
}

/// What one week of the schedule adds up to. Read by the week header and by
/// the exported report, so both quote the same numbers.
class WeekSummary {
  const WeekSummary({
    required this.shiftCount,
    required this.assignedTotal,
    required this.neededTotal,
    required this.gapShiftCount,
  });

  final int shiftCount;
  final int assignedTotal;
  final int neededTotal;
  final int gapShiftCount;

  int get coveragePercent => neededTotal == 0
      ? 100
      : ((assignedTotal / neededTotal) * 100).round().clamp(0, 100);

  factory WeekSummary.of(List<Shift> shifts) => WeekSummary(
        shiftCount: shifts.length,
        assignedTotal: shifts.fold(0, (s, x) => s + x.assigned),
        neededTotal: shifts.fold(0, (s, x) => s + x.needed),
        gapShiftCount: shifts.where((x) => x.hasCoverageGap).length,
      );
}

/// One member's assignment and attendance facts for one dated shift.
class AttendanceRecord {
  const AttendanceRecord({
    required this.shiftId,
    required this.shiftDate,
    required this.centerName,
    required this.member,
  });

  final String shiftId;
  final DateTime shiftDate;
  final String centerName;
  final TeamMember member;

  AttendanceState get status => member.attendance;
  DateTime? get checkInAt => member.checkInAt;
  DateTime? get checkOutAt => member.checkOutAt;
  bool get isPresent =>
      status == AttendanceState.checkedIn ||
      status == AttendanceState.checkedOut;
  bool get isCompleted => status == AttendanceState.checkedOut;
  bool get isAbsent => status == AttendanceState.absent;
  bool get isPending => status == AttendanceState.notCheckedIn;
}

class MemberAttendanceSummary {
  const MemberAttendanceSummary({
    required this.memberId,
    required this.memberName,
    required this.role,
    required this.records,
  });

  final String memberId;
  final String memberName;
  final TeamRole role;
  final List<AttendanceRecord> records;

  int get presentCount => records.where((record) => record.isPresent).length;
  int get absentCount => records.where((record) => record.isAbsent).length;
  int get completedCount =>
      records.where((record) => record.isCompleted).length;

  /// Assignments nobody has reviewed yet. The legacy program had no such
  /// state — its rows were seeded `absent` — so this count is always zero
  /// over legacy-shaped data and is reported separately rather than being
  /// folded into [absentCount].
  int get pendingCount => records.where((record) => record.isPending).length;

  /// Oldest first. The legacy attendance report printed a member's days
  /// ascending (`ORDER BY rec.date ASC`) while the on-screen drill-down
  /// listed them newest first; [records] keeps the screen order.
  List<AttendanceRecord> get recordsOldestFirst =>
      [...records]..sort((a, b) => a.shiftDate.compareTo(b.shiftDate));
}

/// Attendance totals follow the legacy application's reviewed-row rule.
///
/// Legacy (`detachment_stats_providers.dart`) counted every
/// `shift_occurrence_attendance` row on a non-cancelled occurrence, where the
/// status column was `present` or `absent` only, and read
/// `round(present / (present + absent) * 100).clamp(0, 100)`, or `0` when
/// there were no rows. That is reproduced exactly here: checked-in and
/// checked-out assignments are present, absences are absent, and the two are
/// the whole denominator.
///
/// The one place the two models can differ is [pendingCount]. The legacy
/// schema defaulted a seeded row to `absent`, so "nobody reviewed this" and
/// "this person did not come" were the same value. This app separates them
/// into `notCheckedIn` and `absent`, so an unreviewed assignment is neither
/// present nor absent and is surfaced on its own instead of silently
/// depressing the percentage.
class AttendanceStatistics {
  const AttendanceStatistics({required this.members});

  final List<MemberAttendanceSummary> members;

  int get presentCount =>
      members.fold(0, (total, member) => total + member.presentCount);
  int get absentCount =>
      members.fold(0, (total, member) => total + member.absentCount);
  int get completedCount =>
      members.fold(0, (total, member) => total + member.completedCount);
  int get pendingCount =>
      members.fold(0, (total, member) => total + member.pendingCount);
  int get reviewedCount => presentCount + absentCount;
  int get attendancePercent => reviewedCount == 0
      ? 0
      : ((presentCount / reviewedCount) * 100).round().clamp(0, 100);

  List<AttendanceRecord> get records => [
        for (final member in members) ...member.records,
      ];

  factory AttendanceStatistics.fromShifts(
    Iterable<Shift> shifts, {
    String? memberId,
  }) {
    final grouped = <String, List<AttendanceRecord>>{};
    for (final shift in shifts) {
      for (final member in shift.attendees) {
        if (memberId != null && member.id != memberId) continue;
        grouped.putIfAbsent(member.id, () => []).add(
              AttendanceRecord(
                shiftId: shift.id,
                shiftDate: shift.date,
                centerName: shift.centerName,
                member: member,
              ),
            );
      }
    }
    final summaries = <MemberAttendanceSummary>[
      for (final entry in grouped.entries)
        MemberAttendanceSummary(
          memberId: entry.key,
          memberName: entry.value.first.member.name,
          role: entry.value.first.member.role,
          records: entry.value
            ..sort(
              (a, b) => b.shiftDate.compareTo(a.shiftDate),
            ),
        ),
    ]..sort((a, b) {
        final byRole = a.role.index.compareTo(b.role.index);
        return byRole != 0 ? byRole : a.memberName.compareTo(b.memberName);
      });
    return AttendanceStatistics(members: summaries);
  }
}
