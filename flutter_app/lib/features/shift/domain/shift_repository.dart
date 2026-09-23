import '../../../core/result/result.dart';
import '../../team/domain/team_models.dart';
import 'attendance_correction.dart';
import 'shift_models.dart';

abstract class ShiftRepository {
  /// Every shift starting in the seven days from [weekStart] (a Saturday),
  /// ordered by day then start time.
  Future<Result<List<Shift>>> listForWeek(
      String detachmentId, DateTime weekStart);

  /// Every shift whose start date is inside the inclusive date range.
  Future<Result<List<Shift>>> listForRange(
    String detachmentId,
    DateTime from,
    DateTime to,
  );

  Future<Result<List<Shift>>> listForDetachmentToday(String detachmentId);

  Future<Result<Shift>> byId(String id);

  /// Creates one dated shift on [date]. When [repeatOn] is non-empty it also
  /// files a [ShiftTemplate] whose dates are `{date} ∪ repeatOn`, and
  /// materialises one shift per date (each tagged with the template id),
  /// skipping any date that already carries a shift at the same start time.
  /// Returns the shift for [date].
  Future<Result<Shift>> create({
    required String detachmentId,
    required DateTime date,
    required String centerName,
    required int startMinutes,
    required int endMinutes,
    required int needed,
    List<DateTime> repeatOn = const [],
  });

  /// Reconciles the repeat set of the template behind [shiftId] to exactly
  /// [dates] (which always includes the anchor shift's own date):
  ///
  /// * a date with no shift for this template is materialised;
  /// * a shift of this template on a date **not** in [dates] is deleted — but
  ///   only when it has no attendees; a staffed day is kept and its date
  ///   folded back into the set, so the template never diverges from reality;
  /// * the anchor shift's current centre / time / headcount are written onto
  ///   the template, so newly materialised siblings match it (existing
  ///   siblings are left frozen).
  ///
  /// If [dates] collapses to just the anchor date the template is deactivated.
  /// The anchor gains a [Shift.templateId] if it did not have one.
  Future<Result<ShiftTemplate>> updateRepeat(
    String shiftId,
    List<DateTime> dates,
  );

  /// Reconciles a template's own shift set to exactly [dates], without going
  /// through one of its shifts. This is what the templates sheet edits: the
  /// user picks the days the repeat should run on and the template's
  /// occurrences follow.
  ///
  /// Same safety rules as [updateRepeat]: a missing day is materialised from
  /// the *template's* spec, a surplus day is deleted only when its shift has
  /// no attendees, and a staffed day is kept and folded back into the set.
  /// Emptying the set down to one day (or none) deactivates the template
  /// while leaving every shift it already produced in place.
  Future<Result<ShiftTemplate>> updateTemplateDates(
    String templateId,
    List<DateTime> dates,
  );

  /// Every shift this template has materialised, past and future, ordered by
  /// day then start time. Used by the editor to show which repeat days are
  /// locked because they are already staffed.
  Future<Result<List<Shift>>> shiftsForTemplate(String templateId);

  Future<Result<Shift>> update(Shift shift);

  Future<Result<void>> delete(String id);

  Future<Result<Shift>> assignVolunteer(String shiftId, String memberId);

  Future<Result<Shift>> unassignVolunteer(String shiftId, String memberId);

  Future<Result<Shift>> markAttendance(
      String shiftId, String memberId, AttendanceState state);

  Future<Result<Shift>> recordCheckIn(
    String shiftId,
    String memberId,
    DateTime at,
  );

  Future<Result<Shift>> recordCheckOut(
    String shiftId,
    String memberId,
    DateTime at,
  );

  Future<Result<Shift>> markAbsent(String shiftId, String memberId);

  Future<Result<Shift>> resetAttendance(String shiftId, String memberId);

  /// Appends an immutable correction to [memberId]'s attendance on [shiftId]
  /// and, once appended, updates the *effective* attendance to [status] /
  /// [checkInAt] / [checkOutAt]. Available indefinitely — this is the only
  /// path attendance may change through once the one-hour ordinary window has
  /// closed (`Cap.shiftAttendanceOverride`), and it never mutates or removes
  /// an earlier correction.
  ///
  /// [reason] must be non-empty once normalized
  /// ([normalizeCorrectionReason]) or the call fails validation. A checkout
  /// before its check-in is rejected the same way the ordinary path rejects
  /// it. A failed call leaves the stored effective attendance and the
  /// correction history unchanged.
  Future<Result<Shift>> addAttendanceCorrection({
    required String shiftId,
    required String memberId,
    required AttendanceState status,
    DateTime? checkInAt,
    DateTime? checkOutAt,
    required String reason,
    required AttendanceCorrectionAuthor author,
    required DateTime correctedAt,
  });

  /// The roster, each member marked with whether they already work a shift
  /// that overlaps this one. Members already on *this* shift are not offered.
  Future<Result<List<ShiftCandidate>>> candidatesFor(String shiftId);

  /// Fills the gap with free members, most-rested first. Returns how many
  /// were added — zero is a legitimate answer and the caller says so.
  Future<Result<int>> quickFill(String shiftId);

  Future<Result<List<ShiftTemplate>>> templates(String detachmentId);

  /// Stops a repeat. Occurrences it already produced are untouched.
  Future<Result<void>> stopTemplate(String templateId);

  /// Copies one day's shifts onto another day, **without** their
  /// assignments — a schedule repeats, the people on it do not. Returns how
  /// many shifts were created; a day that already has a shift at the same
  /// start time is skipped, so running this twice adds nothing the second
  /// time. Copied shifts are independent: they carry no [Shift.templateId],
  /// because the source's template does not know about the new day.
  ///
  /// This is the day-level twin of [copyWeek] and the one the schedule
  /// screen offers: a detachment runs for ten to fifteen days, so "the same
  /// as yesterday" is the repetition people actually reach for.
  Future<Result<int>> copyDay({
    required String detachmentId,
    required DateTime fromDay,
    required DateTime toDay,
  });

  /// Copies a whole week's shifts onto another week, **without** their
  /// assignments — a schedule repeats, the people on it do not.
  /// Returns how many shifts were created. Duplicates are skipped.
  Future<Result<int>> copyWeek({
    required String detachmentId,
    required DateTime fromWeekStart,
    required DateTime toWeekStart,
  });
}
