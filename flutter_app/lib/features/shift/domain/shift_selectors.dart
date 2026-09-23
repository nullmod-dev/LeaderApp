import '../../team/domain/team_models.dart';
import 'shift_models.dart';

/// Time-based questions about a set of shifts, as pure functions.
///
/// "What is running now", "what is next", and "how does attendance stand" are
/// answers a user acts on, and a wrong one is invisible on screen — so they
/// live here, testable, instead of being re-derived inline by each screen that
/// needs them. The Today dashboard and a member's own page both read these, so
/// the two can never disagree about which shift is current.

/// The shift running at [now].
///
/// Resolved from real timestamps rather than from the calendar day: a
/// 20:00–02:00 shift dated yesterday is still the shift you are working at
/// 01:00. Where two shifts genuinely overlap the earlier start wins, so the
/// answer is stable rather than dependent on list order.
Shift? currentShiftOf(List<Shift> shifts, DateTime now) {
  Shift? best;
  for (final shift in shifts) {
    if (shift.start.isAfter(now)) continue;
    if (!shift.end.isAfter(now)) continue;
    if (best == null || shift.start.isBefore(best.start)) best = shift;
  }
  return best;
}

/// The first shift that has not started yet at [now], or null when nothing is
/// scheduled ahead inside the window [HomeSummary.shifts] covers.
Shift? nextShiftOf(List<Shift> shifts, DateTime now) {
  Shift? best;
  for (final shift in shifts) {
    if (!shift.start.isAfter(now)) continue;
    if (best == null || shift.start.isBefore(best.start)) best = shift;
  }
  return best;
}

/// The shifts dated on [now]'s own day, ordered by start time — what "today's
/// schedule" means on the dashboard.
List<Shift> shiftsOnDay(List<Shift> shifts, DateTime day) {
  final target = dateOnly(day);
  final out = [
    for (final shift in shifts)
      if (shift.date == target) shift,
  ];
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// One shift's attendance, counted once so no two places can disagree.
///
/// [present] folds checked-in and checked-out together on purpose: someone who
/// finished their hours attended. [awaiting] is the count the dashboard calls
/// "missing" — assigned, not marked absent, and not checked in yet.
class TodayAttendance {
  const TodayAttendance({
    required this.needed,
    required this.assigned,
    required this.present,
    required this.absent,
    required this.awaiting,
  });

  static const none = TodayAttendance(
    needed: 0,
    assigned: 0,
    present: 0,
    absent: 0,
    awaiting: 0,
  );

  final int needed;
  final int assigned;
  final int present;
  final int absent;
  final int awaiting;

  /// Places still unfilled against the shift's headcount.
  int get gap => (needed - assigned).clamp(0, needed);

  /// Present over assigned, `0` when nobody is assigned — never a division by
  /// zero and never a fabricated 100%.
  double get progress => assigned == 0 ? 0 : present / assigned;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TodayAttendance &&
          other.needed == needed &&
          other.assigned == assigned &&
          other.present == present &&
          other.absent == absent &&
          other.awaiting == awaiting;

  @override
  int get hashCode => Object.hash(needed, assigned, present, absent, awaiting);

  @override
  String toString() => 'TodayAttendance(needed: $needed, assigned: $assigned, '
      'present: $present, absent: $absent, awaiting: $awaiting)';
}

TodayAttendance attendanceOf(Shift? shift) {
  if (shift == null) return TodayAttendance.none;
  var present = 0;
  var absent = 0;
  var awaiting = 0;
  for (final attendee in shift.attendees) {
    switch (attendee.attendance) {
      case AttendanceState.checkedIn:
      case AttendanceState.checkedOut:
        present++;
      case AttendanceState.absent:
        absent++;
      case AttendanceState.notCheckedIn:
        awaiting++;
    }
  }
  return TodayAttendance(
    needed: shift.needed,
    assigned: shift.attendees.length,
    present: present,
    absent: absent,
    awaiting: awaiting,
  );
}
