import 'shift_models.dart';

/// How long attendance stays on the ordinary path after a shift ends.
///
/// One hour, anchored to the shift's real end time — not to when the
/// attendance entry was created or to check-in time. This is not a new
/// choice: it is the legacy program's own decision, carried verbatim.
///
/// * `medical_team/lib/features/detachments/data/attendance_lock.dart`
///   (`attendanceGracePeriod`) — the executable source of truth, with its own
///   boundary test suite.
/// * `LEGACY-EXTRACTION-REPORT.md` (D-16) — "once a date's shift end time
///   plus a one hour grace period has passed, that date's attendance becomes
///   read-only."
/// * `CAPABILITIES.md` and `core/access/capability.dart` — `shift.attendance.record`
///   is scoped to "inside the one-hour window"; `shift.attendance.override`
///   is scoped to "after the one-hour lock."
///
/// One deliberate divergence from both the legacy program and MTM-PRO's own
/// (separately designed, unbuilt) three-layer scheme: there is no second,
/// longer grace layer here. Once the hour closes, only
/// `Cap.shiftAttendanceOverride` continues — and only through an append-only
/// correction, never by mutating the original entry. See `HANDOFF.md` for the
/// full citation trail behind this choice.
const Duration attendanceEditGracePeriod = Duration(hours: 1);

/// Stable, non-textual failure code returned when an ordinary edit is
/// attempted after the window has closed. Never shown to a user directly —
/// [MockShiftRepository] pairs it with Arabic copy from `strings.dart`, the
/// way every other repository failure code already works.
const String attendanceWindowExpiredCode = 'attendance_window_expired';

/// The one-hour ordinary edit window for one dated shift, resolved at [now].
class AttendanceWindow {
  const AttendanceWindow({required this.lockTime, required this.isOpen});

  /// The instant the ordinary window closes: the shift's real end time
  /// (already correct for a shift that crosses midnight — see [Shift.end])
  /// plus [attendanceEditGracePeriod].
  final DateTime lockTime;

  /// True while `now` is still strictly before [lockTime]. `now == lockTime`
  /// counts as closed — matching the legacy boundary test ("locked exactly
  /// when the grace hour elapses").
  final bool isOpen;

  /// Time left in the window at the `now` it was resolved for; zero once
  /// closed.
  Duration remaining(DateTime now) =>
      isOpen ? lockTime.difference(now) : Duration.zero;

  factory AttendanceWindow.of(Shift shift, {required DateTime now}) {
    final lockTime = shift.end.add(attendanceEditGracePeriod);
    return AttendanceWindow(
      lockTime: lockTime,
      isOpen: now.isBefore(lockTime),
    );
  }
}

/// What a session may do with one member's attendance on one shift, right
/// now.
enum AttendanceEditMode {
  /// The ordinary controls — `recordCheckIn` and friends. Gated on the
  /// window being open and on holding either attendance capability.
  ordinary,

  /// The window has closed; only `Cap.shiftAttendanceOverride` continues,
  /// and only by appending a correction.
  correctionOnly,

  /// Neither applies. Nothing to show but the current state.
  readOnly,
}

/// Combines [window] with the session's two attendance capabilities.
///
/// `Cap.shiftAttendanceRecord` and `Cap.shiftAttendanceOverride` both drive
/// the ordinary path while the window is open — a Main Admin uses the exact
/// same controls a sub-Admin does, not a separate one. Once the window
/// closes, only override authority keeps working, and it never falls back to
/// [AttendanceEditMode.ordinary]: the two mutation paths are disjoint by
/// construction, so there is no state where both an ordinary control and a
/// correction control could act on the same entry at once.
AttendanceEditMode resolveAttendanceEditMode({
  required AttendanceWindow window,
  required bool canRecord,
  required bool canOverride,
}) {
  if (window.isOpen && (canRecord || canOverride)) {
    return AttendanceEditMode.ordinary;
  }
  if (canOverride) return AttendanceEditMode.correctionOnly;
  return AttendanceEditMode.readOnly;
}
