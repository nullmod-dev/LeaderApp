import 'dart:math';

import '../../../core/result/result.dart';
import '../../team/domain/team_models.dart';
import '../../../l10n/strings.dart';
import '../../team/domain/team_repository.dart';
import '../domain/attendance_correction.dart';
import '../domain/attendance_policy.dart';
import '../domain/shift_models.dart';
import '../domain/shift_repository.dart';

/// The weekly repeats one detachment runs: weekday, period, centre, how many
/// are needed, and the roster ids that start out assigned.
typedef ShiftSeedPlan = Map<
    String,
    List<
        (
          int weekday,
          ShiftPeriod period,
          String center,
          int needed,
          List<String> members
        )>>;

/// The same, for a detachment that has ended: each row also says how many
/// weeks back it ran.
typedef ShiftHistorySeedPlan = Map<
    String,
    List<
        (
          int weeksAgo,
          int weekday,
          ShiftPeriod period,
          String center,
          int needed,
          List<String> members
        )>>;

class _AttendanceValidation implements Exception {
  const _AttendanceValidation(this.code);

  final String code;
}

/// In-memory schedule for every detachment — the archived one included, whose
/// occurrences are seeded in the past and finished.
///
/// Two rules hold this file together:
///
/// 1. **The roster is read, never copied.** Every attendee is resolved
///    through [TeamRepository], so the schedule cannot show a person the
///    Members tab does not have, and a rename shows up on both.
/// 2. **Occurrences are dated relative to today.** The seed is built at
///    construction from this week's Saturday, so the schedule always has
///    something in it whenever the app is opened — including a filled last
///    week, which is what makes "copy last week" demonstrable.
class MockShiftRepository implements ShiftRepository {
  /// [clock] is injectable so a test can pin every meaning of "now": seed
  /// dates as well as the one-hour attendance window. Production passes
  /// nothing and gets [DateTime.now].
  /// [plan] and [history] replace the seeded weeks — the Customer Demo
  /// workspace passes its own small schedule and no archive.
  MockShiftRepository(
    this._directory, {
    DateTime Function()? clock,
    ShiftSeedPlan? plan,
    ShiftHistorySeedPlan? history,
  })  : _clock = clock ?? DateTime.now,
        _seedPlan = plan ?? _plan,
        _seedHistory = history ?? _historyPlan {
    _seed();
  }

  final ShiftSeedPlan _seedPlan;
  final ShiftHistorySeedPlan _seedHistory;

  final TeamRepository _directory;
  final DateTime Function() _clock;
  final _rand = Random(31);

  final List<Shift> _shifts = [];
  final List<ShiftTemplate> _templates = [];

  int _nextShift = 1;
  int _nextTemplate = 1;
  int _nextCorrection = 1;

  // ---------------------------------------------------------------------
  // Seed
  // ---------------------------------------------------------------------

  /// Weekly repeats per detachment, and the roster ids that start out
  /// assigned to each. Distinct per detachment on purpose: switching
  /// detachments has to show a visibly different week, otherwise a scoping
  /// leak looks the same as correct behaviour.
  static const ShiftSeedPlan _plan = <String,
      List<
          (
            int weekday,
            ShiftPeriod period,
            String center,
            int needed,
            List<String> members
          )>>{
    'd_dam_central': [
      (
        DateTime.saturday,
        ShiftPeriod.morning,
        'مركز الشعلان',
        8,
        ['m1', 'm2', 'm4', 'm7']
      ),
      (DateTime.saturday, ShiftPeriod.evening, 'مركز الشعلان', 6, ['m3', 'm8']),
      (DateTime.sunday, ShiftPeriod.morning, 'مركز الشعلان', 6, ['m1', 'm10']),
      (DateTime.monday, ShiftPeriod.evening, 'مركز المهاجرين', 8, ['m2']),
      (DateTime.wednesday, ShiftPeriod.night, 'مركز المهاجرين', 5, []),
      (
        DateTime.thursday,
        ShiftPeriod.morning,
        'مركز الشعلان',
        7,
        ['m1', 'm5', 'm9']
      ),
    ],
    'd_dam_rural': [
      (
        DateTime.saturday,
        ShiftPeriod.morning,
        'مركز داريا',
        6,
        ['m11', 'm12', 'm16']
      ),
      (DateTime.monday, ShiftPeriod.evening, 'مركز صحنايا', 6, ['m13']),
      (DateTime.tuesday, ShiftPeriod.morning, 'مركز داريا', 4, ['m11', 'm18']),
      (DateTime.friday, ShiftPeriod.evening, 'مركز صحنايا', 5, ['m17']),
    ],
    'd_homs': [
      (DateTime.sunday, ShiftPeriod.morning, 'مركز الوعر', 5, ['m14', 'm19']),
      (DateTime.tuesday, ShiftPeriod.evening, 'مركز الوعر', 5, ['m20']),
      (DateTime.thursday, ShiftPeriod.night, 'مركز الوعر', 4, ['m14']),
    ],
    'd_coast': [
      (
        DateTime.saturday,
        ShiftPeriod.morning,
        'مركز اللاذقية',
        4,
        ['m15', 'm23']
      ),
      (DateTime.wednesday, ShiftPeriod.evening, 'مركز جبلة', 5, ['m24']),
    ],
    // d_north_arch is archived: it ran, and it stopped. Its schedule is
    // seeded separately, in the past, by [_historyPlan].
  };

  /// The archived detachment's finished schedule.
  ///
  /// Dated three and four weeks back rather than relative to this week,
  /// because a detachment that has ended does not have a "this week". Every
  /// occurrence is completed, so the archive's shifts, its attendance, and
  /// the statistics drawn from them all have real records behind them
  /// instead of an empty tab.
  static const ShiftHistorySeedPlan _historyPlan = <String,
      List<
          (
            int weeksAgo,
            int weekday,
            ShiftPeriod period,
            String center,
            int needed,
            List<String> members
          )>>{
    'd_north_arch': [
      (
        4,
        DateTime.saturday,
        ShiftPeriod.morning,
        'مركز الأشرفية',
        4,
        ['m26', 'm27', 'm28']
      ),
      (4, DateTime.monday, ShiftPeriod.evening, 'مركز الأشرفية', 4, ['m29']),
      // A night shift, so the archive carries the one case a reader has to be
      // able to trust: a run that ends after midnight still belongs to the
      // day it began.
      (
        4,
        DateTime.wednesday,
        ShiftPeriod.night,
        'مركز الأشرفية',
        3,
        ['m26', 'm29']
      ),
      (
        3,
        DateTime.sunday,
        ShiftPeriod.morning,
        'مركز الأشرفية',
        4,
        ['m27', 'm28', 'm29']
      ),
      (3, DateTime.tuesday, ShiftPeriod.evening, 'مركز الأشرفية', 3, ['m26']),
    ],
  };

  void _seed() {
    final thisWeek = startOfWeek(_clock());
    final lastWeek = thisWeek.subtract(const Duration(days: 7));

    for (final entry in _seedPlan.entries) {
      for (final row in entry.value) {
        final (weekday, period, center, needed, members) = row;
        final times = period.times!;
        final lastDay = _dayOfWeek(lastWeek, weekday);
        final thisDay = _dayOfWeek(thisWeek, weekday);
        _templates.add(ShiftTemplate(
          id: 'tpl${_nextTemplate++}',
          detachmentId: entry.key,
          centerName: center,
          // The template carries the two days it has actually run so far. A
          // real detachment would extend this set forward as it schedules.
          dates: [lastDay, thisDay],
          startMinutes: times.$1,
          endMinutes: times.$2,
          needed: needed,
        ));
        final templateId = 'tpl${_nextTemplate - 1}';

        // Last week ran; this week is being staffed. Last week is seeded a
        // little fuller so the two weeks read differently at a glance.
        for (final (weekStart, ids) in [
          (lastWeek, members),
          (
            thisWeek,
            members.take(members.length - (members.isEmpty ? 0 : 1)).toList()
          ),
        ]) {
          final shiftDate = _dayOfWeek(weekStart, weekday);
          _shifts.add(Shift(
            id: 'sh${_nextShift++}',
            detachmentId: entry.key,
            templateId: templateId,
            date: shiftDate,
            centerName: center,
            startMinutes: times.$1,
            endMinutes: times.$2,
            needed: needed,
            attendees: _placeholders(
              entry.key,
              ids,
              shiftDate,
              times,
              completed: weekStart == lastWeek,
            ),
          ));
        }
      }
    }

    for (final entry in _seedHistory.entries) {
      for (final row in entry.value) {
        final (weeksAgo, weekday, period, center, needed, members) = row;
        final times = period.times!;
        final weekStart = thisWeek.subtract(Duration(days: 7 * weeksAgo));
        final shiftDate = _dayOfWeek(weekStart, weekday);
        // No template: the repeat that produced these is over, and a live
        // template on an archived detachment would offer to materialise days
        // it can no longer run.
        _shifts.add(Shift(
          id: 'sh${_nextShift++}',
          detachmentId: entry.key,
          date: shiftDate,
          centerName: center,
          startMinutes: times.$1,
          endMinutes: times.$2,
          needed: needed,
          attendees: _placeholders(
            entry.key,
            members,
            shiftDate,
            times,
            completed: true,
          ),
        ));
      }
    }
  }

  /// The date of [weekday] inside the week beginning [weekStart] (Saturday).
  static DateTime _dayOfWeek(DateTime weekStart, int weekday) =>
      addDays(weekStart, (weekday - weekStartsOn) % 7);

  /// Seed attendees are placeholders carrying only an id; every read
  /// re-resolves them against the live roster in [_hydrate], so a member
  /// renamed or deleted on the Members tab is renamed or gone here too.
  static List<TeamMember> _placeholders(
    String detachmentId,
    List<String> ids,
    DateTime date,
    (int, int) times, {
    required bool completed,
  }) =>
      [
        for (final (index, id) in ids.indexed)
          TeamMember(
            id: id,
            name: '',
            initials: '',
            role: TeamRole.member,
            detachmentId: detachmentId,
            // Every third seeded attendee of a finished shift did not come, so
            // the absence path — statistics, report rows, the absent chip —
            // has real data behind it. The rosters are small, so a wider
            // modulus would silently never fire.
            attendance: completed
                ? index % 3 == 2
                    ? AttendanceState.absent
                    : AttendanceState.checkedOut
                : AttendanceState.notCheckedIn,
            checkInAt: completed && index % 3 != 2
                ? date.add(Duration(minutes: times.$1))
                : null,
            checkOutAt: completed && index % 3 != 2
                ? date
                    .add(Duration(days: times.$2 <= times.$1 ? 1 : 0))
                    .add(Duration(minutes: times.$2))
                : null,
          ),
      ];

  // ---------------------------------------------------------------------
  // Roster resolution
  // ---------------------------------------------------------------------

  Future<void> _latency() => Future<void>.delayed(
        Duration(milliseconds: 260 + _rand.nextInt(300)),
      );

  Future<List<TeamMember>> _roster(String detachmentId) async {
    final result = await _directory.listForDetachment(detachmentId);
    return result.when(
      success: (data, {stale = false}) => data,
      failure: (_, __) => const <TeamMember>[],
      offline: (cached) => cached ?? const <TeamMember>[],
    );
  }

  /// Replaces each attendee with the live roster record, keeping the
  /// attendance state recorded on the shift. A member who has left the
  /// detachment simply falls out of the list.
  Shift _hydrate(Shift shift, List<TeamMember> roster) {
    final by = {for (final m in roster) m.id: m};
    final attendees = <TeamMember>[
      for (final a in shift.attendees)
        if (by[a.id] != null)
          by[a.id]!.copyWith(
            attendance: a.attendance,
            checkInAt: a.checkInAt,
            checkOutAt: a.checkOutAt,
          ),
    ];
    return shift.copyWith(attendees: attendees);
  }

  Future<List<Shift>> _hydrateAll(
      String detachmentId, Iterable<Shift> shifts) async {
    final roster = await _roster(detachmentId);
    return [for (final s in shifts) _hydrate(s, roster)];
  }

  int _indexOf(String shiftId) => _shifts.indexWhere((s) => s.id == shiftId);

  static int _order(Shift a, Shift b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.startMinutes.compareTo(b.startMinutes);
  }

  // ---------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------

  @override
  Future<Result<List<Shift>>> listForWeek(
      String detachmentId, DateTime weekStart) async {
    await _latency();
    final start = startOfWeek(weekStart);
    // Calendar days, not 168 hours: in a DST week the absolute span is 167
    // or 169, and the exclusive bound would then drop the last day of the
    // week or pull in the first day of the next one.
    final end = addDays(start, 7);
    final week = _shifts
        .where((s) =>
            s.detachmentId == detachmentId &&
            !s.date.isBefore(start) &&
            s.date.isBefore(end))
        .toList()
      ..sort(_order);
    return Success(await _hydrateAll(detachmentId, week));
  }

  @override
  Future<Result<List<Shift>>> listForRange(
    String detachmentId,
    DateTime from,
    DateTime to,
  ) async {
    await _latency();
    final start = dateOnly(from);
    final end = addDays(dateOnly(to), 1);
    final range = _shifts
        .where(
          (shift) =>
              shift.detachmentId == detachmentId &&
              !shift.date.isBefore(start) &&
              shift.date.isBefore(end),
        )
        .toList()
      ..sort(_order);
    return Success(await _hydrateAll(detachmentId, range));
  }

  @override
  Future<Result<List<Shift>>> listForDetachmentToday(
      String detachmentId) async {
    await _latency();
    final today = dateOnly(_clock());
    final list = _shifts
        .where((s) => s.detachmentId == detachmentId && s.date == today)
        .toList()
      ..sort(_order);
    return Success(await _hydrateAll(detachmentId, list));
  }

  @override
  Future<Result<Shift>> byId(String id) async {
    await _latency();
    final i = _indexOf(id);
    // Never fall back to another detachment's shift.
    if (i < 0) return const Failure('لم يُعثر على الشفت.', code: 'not_found');
    final roster = await _roster(_shifts[i].detachmentId);
    return Success(_hydrate(_shifts[i], roster));
  }

  // ---------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------

  @override
  Future<Result<Shift>> create({
    required String detachmentId,
    required DateTime date,
    required String centerName,
    required int startMinutes,
    required int endMinutes,
    required int needed,
    List<DateTime> repeatOn = const [],
  }) async {
    await _latency();
    if (startMinutes == endMinutes) {
      return const Failure('وقت البداية يجب أن يختلف عن وقت النهاية.',
          code: 'validation');
    }
    if (needed <= 0) {
      return const Failure('عدد المطلوبين يجب أن يكون أكبر من صفر.',
          code: 'validation');
    }
    if (centerName.trim().isEmpty) {
      return const Failure('اسم المركز مطلوب.', code: 'validation');
    }

    final day = dateOnly(date);
    final center = centerName.trim();

    // The anchor day is always part of the repeat set. Anything else in
    // [repeatOn] joins it; one day on its own is not a repeat.
    final repeatDays = <DateTime>{day, for (final d in repeatOn) dateOnly(d)};

    String? templateId;
    if (repeatDays.length > 1) {
      final template = ShiftTemplate(
        id: 'tpl${_nextTemplate++}',
        detachmentId: detachmentId,
        centerName: center,
        dates: repeatDays,
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        needed: needed,
      );
      _templates.add(template);
      templateId = template.id;
    }

    Shift make(DateTime on) => Shift(
          id: 'sh${_nextShift++}',
          detachmentId: detachmentId,
          templateId: templateId,
          date: on,
          centerName: center,
          startMinutes: startMinutes,
          endMinutes: endMinutes,
          needed: needed,
          attendees: const [],
        );

    final anchor = make(day);
    _shifts.add(anchor);

    if (templateId != null) {
      for (final on in repeatDays) {
        if (on == day) continue;
        // Dedupe: never stack a second shift on a day+time that already has one.
        if (_exists(detachmentId, on, startMinutes)) continue;
        _shifts.add(make(on));
      }
    }
    return Success(anchor);
  }

  @override
  Future<Result<ShiftTemplate>> updateRepeat(
    String shiftId,
    List<DateTime> dates,
  ) async {
    await _latency();
    final i = _indexOf(shiftId);
    if (i < 0) return const Failure('لم يُعثر على الشفت.', code: 'not_found');
    final anchor = _shifts[i];

    final wanted = <DateTime>{
      dateOnly(anchor.date),
      for (final d in dates) dateOnly(d),
    };

    // Find or start the template this shift repeats on.
    var ti = anchor.templateId == null
        ? -1
        : _templates.indexWhere((t) => t.id == anchor.templateId);
    String templateId;
    if (ti < 0) {
      final template = ShiftTemplate(
        id: 'tpl${_nextTemplate++}',
        detachmentId: anchor.detachmentId,
        centerName: anchor.centerName,
        dates: wanted,
        startMinutes: anchor.startMinutes,
        endMinutes: anchor.endMinutes,
        needed: anchor.needed,
      );
      _templates.add(template);
      ti = _templates.length - 1;
      templateId = template.id;
      _shifts[i] = anchor.copyWith(templateId: templateId);
    } else {
      templateId = _templates[ti].id;
    }

    final settled = _reconcileTemplateShifts(
      templateId: templateId,
      wanted: wanted,
      detachmentId: anchor.detachmentId,
      centerName: anchor.centerName,
      startMinutes: anchor.startMinutes,
      endMinutes: anchor.endMinutes,
      needed: anchor.needed,
    );

    // The template mirrors the anchor's current spec so future siblings match
    // it; existing siblings stay frozen. One lone day means the repeat is off.
    _templates[ti] = _templates[ti].copyWith(
      centerName: anchor.centerName,
      startMinutes: anchor.startMinutes,
      endMinutes: anchor.endMinutes,
      needed: anchor.needed,
      dates: settled,
      active: settled.length > 1,
    );
    return Success(_templates[ti]);
  }

  @override
  Future<Result<ShiftTemplate>> updateTemplateDates(
    String templateId,
    List<DateTime> dates,
  ) async {
    await _latency();
    final ti = _templates.indexWhere((t) => t.id == templateId);
    if (ti < 0) return const Failure('لم يُعثر على القالب.', code: 'not_found');
    final template = _templates[ti];

    final settled = _reconcileTemplateShifts(
      templateId: templateId,
      wanted: {for (final d in dates) dateOnly(d)},
      detachmentId: template.detachmentId,
      centerName: template.centerName,
      startMinutes: template.startMinutes,
      endMinutes: template.endMinutes,
      needed: template.needed,
    );

    // Unlike `updateRepeat` there is no anchor shift to mirror: the user is
    // editing the template itself, so its own spec is the truth and only the
    // day set moves. A repeat that is down to one day (or none) stops being a
    // repeat — the shifts it already made stay exactly where they are.
    _templates[ti] = template.copyWith(
      dates: settled,
      active: settled.length > 1,
    );
    return Success(_templates[ti]);
  }

  /// Brings the shifts carrying [templateId] into line with [wanted], and
  /// returns the day set that actually survived.
  ///
  /// Three rules, in this order, and they are the whole safety story of the
  /// repeat feature:
  ///
  /// * a day in [wanted] with no shift for this template is **materialised**
  ///   from the spec passed in — unless that day+time already carries some
  ///   other shift, which is the dedupe guard;
  /// * a shift of this template on a day not in [wanted] is **deleted only
  ///   when it is empty**;
  /// * a shift with attendees is **never** deleted; its day is folded back
  ///   into the returned set instead, so the template can never claim a day
  ///   set that contradicts the shifts on the ground.
  Set<DateTime> _reconcileTemplateShifts({
    required String templateId,
    required Set<DateTime> wanted,
    required String detachmentId,
    required String centerName,
    required int startMinutes,
    required int endMinutes,
    required int needed,
  }) {
    final settled = <DateTime>{...wanted};

    final mine = _shifts.where((s) => s.templateId == templateId).toList();
    for (final s in mine) {
      if (settled.contains(s.date)) continue;
      if (s.attendees.isNotEmpty) {
        settled.add(s.date);
        continue;
      }
      _shifts.removeWhere((x) => x.id == s.id);
    }

    final present = _shifts
        .where((s) => s.templateId == templateId)
        .map((s) => s.date)
        .toSet();
    for (final on in settled) {
      if (present.contains(on)) continue;
      if (_exists(detachmentId, on, startMinutes)) continue;
      _shifts.add(Shift(
        id: 'sh${_nextShift++}',
        detachmentId: detachmentId,
        templateId: templateId,
        date: on,
        centerName: centerName,
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        needed: needed,
        attendees: const [],
      ));
    }
    return settled;
  }

  @override
  Future<Result<List<Shift>>> shiftsForTemplate(String templateId) async {
    await _latency();
    final list = _shifts.where((s) => s.templateId == templateId).toList()
      ..sort(_order);
    if (list.isEmpty) return const Success(<Shift>[]);
    return Success(await _hydrateAll(list.first.detachmentId, list));
  }

  @override
  Future<Result<Shift>> update(Shift shift) async {
    await _latency();
    final i = _indexOf(shift.id);
    if (i < 0) return const Failure('لم يُعثر على الشفت.', code: 'not_found');
    if (shift.startMinutes == shift.endMinutes) {
      return const Failure('وقت البداية يجب أن يختلف عن وقت النهاية.',
          code: 'validation');
    }
    if (shift.needed <= 0) {
      return const Failure('عدد المطلوبين يجب أن يكون أكبر من صفر.',
          code: 'validation');
    }
    // Keep the stored attendee ids; the caller may be handing back a
    // hydrated copy, and the roster is re-resolved on the next read anyway.
    _shifts[i] = shift.copyWith(date: dateOnly(shift.date));
    return Success(_shifts[i]);
  }

  @override
  Future<Result<void>> delete(String id) async {
    await _latency();
    final i = _indexOf(id);
    if (i < 0) return const Failure('لم يُعثر على الشفت.', code: 'not_found');
    _shifts.removeAt(i);
    return const Success(null);
  }

  @override
  Future<Result<Shift>> assignVolunteer(String shiftId, String memberId) async {
    await _latency();
    final i = _indexOf(shiftId);
    if (i < 0) return const Failure('لم يُعثر على الشفت.', code: 'not_found');
    final shift = _shifts[i];

    if (shift.attendees.any((a) => a.id == memberId)) {
      return const Failure('هذا المتطوع مسند بالفعل.', code: 'conflict');
    }

    final roster = await _roster(shift.detachmentId);
    final member = roster.where((m) => m.id == memberId).firstOrNull;
    // A member from another detachment must not be assignable here.
    if (member == null) {
      return const Failure('العضو ليس في هذه المفرزة.', code: 'not_found');
    }
    if (_clashFor(memberId, shift) != null) {
      return const Failure('هذا العضو مسند لشفت آخر يتقاطع مع هذا الوقت.',
          code: 'conflict');
    }

    _shifts[i] = shift.copyWith(attendees: [
      ...shift.attendees,
      member.copyWith(attendance: AttendanceState.notCheckedIn),
    ]);
    return Success(_hydrate(_shifts[i], roster));
  }

  @override
  Future<Result<Shift>> unassignVolunteer(
      String shiftId, String memberId) async {
    await _latency();
    final i = _indexOf(shiftId);
    if (i < 0) return const Failure('لم يُعثر على الشفت.', code: 'not_found');
    final shift = _shifts[i];
    final attendees = shift.attendees.where((a) => a.id != memberId).toList();
    if (attendees.length == shift.attendees.length) {
      return const Failure('العضو غير مسند لهذا الشفت.', code: 'not_found');
    }
    _shifts[i] = shift.copyWith(attendees: attendees);
    final roster = await _roster(shift.detachmentId);
    return Success(_hydrate(_shifts[i], roster));
  }

  @override
  Future<Result<Shift>> markAttendance(
      String shiftId, String memberId, AttendanceState state) async {
    return switch (state) {
      AttendanceState.absent => markAbsent(shiftId, memberId),
      AttendanceState.notCheckedIn => resetAttendance(shiftId, memberId),
      AttendanceState.checkedIn => recordCheckIn(shiftId, memberId, _clock()),
      AttendanceState.checkedOut => recordCheckOut(shiftId, memberId, _clock()),
    };
  }

  Future<Result<Shift>> _updateAttendance(
    String shiftId,
    String memberId,
    TeamMember Function(Shift shift, TeamMember attendee) update,
  ) async {
    await _latency();
    final i = _indexOf(shiftId);
    if (i < 0) return const Failure('لم يُعثر على الشفت.', code: 'not_found');
    final shift = _shifts[i];

    // The ordinary path only exists while the one-hour window is open — see
    // `attendance_policy.dart`. Once it closes, `addAttendanceCorrection` is
    // the only way attendance may change; that method never routes through
    // here, so this check cannot be bypassed by the four public methods below.
    if (!AttendanceWindow.of(shift, now: _clock()).isOpen) {
      return const Failure(
        S.attendanceWindowExpired,
        code: attendanceWindowExpiredCode,
      );
    }

    final at = shift.attendees.indexWhere((a) => a.id == memberId);
    if (at < 0) {
      return const Failure('العضو غير مسند لهذا الشفت.', code: 'not_found');
    }
    final attendees = [...shift.attendees];
    try {
      attendees[at] = update(shift, attendees[at]);
    } on _AttendanceValidation catch (error) {
      return Failure(
        error.code == 'check_in_required'
            ? S.checkoutRequiresCheckin
            : S.checkoutBeforeCheckin,
        code: error.code,
      );
    }
    _shifts[i] = shift.copyWith(attendees: attendees);
    final roster = await _roster(shift.detachmentId);
    return Success(_hydrate(_shifts[i], roster));
  }

  @override
  Future<Result<Shift>> recordCheckIn(
    String shiftId,
    String memberId,
    DateTime at,
  ) =>
      _updateAttendance(
        shiftId,
        memberId,
        (_, attendee) {
          final checkOut = attendee.checkOutAt;
          if (checkOut != null && at.isAfter(checkOut)) {
            throw const _AttendanceValidation('checkin_after_checkout');
          }
          return attendee.copyWith(
            attendance: checkOut == null
                ? AttendanceState.checkedIn
                : AttendanceState.checkedOut,
            checkInAt: at,
          );
        },
      );

  @override
  Future<Result<Shift>> recordCheckOut(
    String shiftId,
    String memberId,
    DateTime at,
  ) =>
      _updateAttendance(shiftId, memberId, (shift, attendee) {
        final checkIn = attendee.checkInAt;
        if (checkIn == null) {
          throw const _AttendanceValidation('check_in_required');
        }
        var normalized = at;
        if (normalized.isBefore(checkIn) &&
            shift.crossesMidnight &&
            dateOnly(normalized) == shift.date) {
          normalized = normalized.add(const Duration(days: 1));
        }
        if (normalized.isBefore(checkIn)) {
          throw const _AttendanceValidation('checkout_before_checkin');
        }
        return attendee.copyWith(
          attendance: AttendanceState.checkedOut,
          checkOutAt: normalized,
        );
      });

  @override
  Future<Result<Shift>> markAbsent(String shiftId, String memberId) =>
      _updateAttendance(
        shiftId,
        memberId,
        (_, attendee) => attendee.copyWith(
          attendance: AttendanceState.absent,
          clearCheckIn: true,
          clearCheckOut: true,
        ),
      );

  @override
  Future<Result<Shift>> resetAttendance(String shiftId, String memberId) =>
      _updateAttendance(
        shiftId,
        memberId,
        (_, attendee) => attendee.copyWith(
          attendance: AttendanceState.notCheckedIn,
          clearCheckIn: true,
          clearCheckOut: true,
        ),
      );

  @override
  Future<Result<Shift>> addAttendanceCorrection({
    required String shiftId,
    required String memberId,
    required AttendanceState status,
    DateTime? checkInAt,
    DateTime? checkOutAt,
    required String reason,
    required AttendanceCorrectionAuthor author,
    required DateTime correctedAt,
  }) async {
    await _latency();
    final normalizedReason = normalizeCorrectionReason(reason);
    if (normalizedReason == null) {
      return const Failure(S.correctionReasonRequired, code: 'validation');
    }

    final i = _indexOf(shiftId);
    if (i < 0) return const Failure('لم يُعثر على الشفت.', code: 'not_found');
    final shift = _shifts[i];

    final at = shift.attendees.indexWhere((a) => a.id == memberId);
    if (at < 0) {
      return const Failure('العضو غير مسند لهذا الشفت.', code: 'not_found');
    }
    final attendee = shift.attendees[at];

    // Same physical-consistency rule as the ordinary path (`recordCheckOut`),
    // including the overnight normalization — a correction must not be able
    // to store a state the ordinary path itself would refuse.
    var normalizedCheckOut = checkOutAt;
    if (checkInAt != null && normalizedCheckOut != null) {
      if (normalizedCheckOut.isBefore(checkInAt) &&
          shift.crossesMidnight &&
          dateOnly(normalizedCheckOut) == shift.date) {
        normalizedCheckOut = normalizedCheckOut.add(const Duration(days: 1));
      }
      if (normalizedCheckOut.isBefore(checkInAt)) {
        return const Failure(S.checkoutBeforeCheckin,
            code: 'checkout_before_checkin');
      }
    }

    final correction = AttendanceCorrection(
      id: 'corr${_nextCorrection++}',
      shiftId: shiftId,
      memberId: memberId,
      before: AttendanceSnapshot.of(attendee),
      after: AttendanceSnapshot(
        status: status,
        checkInAt: checkInAt,
        checkOutAt: normalizedCheckOut,
      ),
      reason: normalizedReason,
      author: author,
      correctedAt: correctedAt,
    );

    final attendees = [...shift.attendees];
    attendees[at] = attendee.copyWith(
      attendance: status,
      checkInAt: checkInAt,
      checkOutAt: normalizedCheckOut,
      clearCheckIn: checkInAt == null,
      clearCheckOut: normalizedCheckOut == null,
    );

    // The append and the effective-state update happen together, after every
    // validation above has passed — a failed call above returns before this
    // point and neither the attendee's state nor `corrections` is touched.
    _shifts[i] = shift.copyWith(
      attendees: attendees,
      corrections: [...shift.corrections, correction],
    );
    final roster = await _roster(shift.detachmentId);
    return Success(_hydrate(_shifts[i], roster));
  }

  // ---------------------------------------------------------------------
  // Assignment helpers
  // ---------------------------------------------------------------------

  /// The other shift [memberId] already works that overlaps [shift], if any.
  Shift? _clashFor(String memberId, Shift shift) {
    for (final other in _shifts) {
      if (other.id == shift.id) continue;
      if (other.detachmentId != shift.detachmentId) continue;
      if (!other.attendees.any((a) => a.id == memberId)) continue;
      if (other.overlaps(shift)) return other;
    }
    return null;
  }

  @override
  Future<Result<List<ShiftCandidate>>> candidatesFor(String shiftId) async {
    await _latency();
    final i = _indexOf(shiftId);
    if (i < 0) return const Failure('لم يُعثر على الشفت.', code: 'not_found');
    final shift = _shifts[i];
    final roster = await _roster(shift.detachmentId);
    final already = shift.attendees.map((a) => a.id).toSet();

    final out = <ShiftCandidate>[
      for (final m in roster)
        if (!already.contains(m.id))
          ShiftCandidate(
            member: m,
            busy: _clashFor(m.id, shift) != null,
            busyWith: _clashFor(m.id, shift),
          ),
    ];
    // Free members first, then by role so leads and medics surface before
    // trainees — the order someone staffing a shift actually wants.
    out.sort((a, b) {
      if (a.busy != b.busy) return a.busy ? 1 : -1;
      return a.member.role.index.compareTo(b.member.role.index);
    });
    return Success(out);
  }

  @override
  Future<Result<int>> quickFill(String shiftId) async {
    final candidates = await candidatesFor(shiftId);
    final free = candidates.when(
      success: (data, {stale = false}) =>
          data.where((c) => !c.busy).map((c) => c.member).toList(),
      failure: (_, __) => const <TeamMember>[],
      offline: (cached) => const <TeamMember>[],
    );
    final i = _indexOf(shiftId);
    if (i < 0) return const Failure('لم يُعثر على الشفت.', code: 'not_found');

    var added = 0;
    for (final m in free) {
      if (_shifts[i].gap == 0) break;
      // Re-check per member: each assignment changes who is still free.
      if (_clashFor(m.id, _shifts[i]) != null) continue;
      _shifts[i] = _shifts[i].copyWith(attendees: [
        ..._shifts[i].attendees,
        m.copyWith(attendance: AttendanceState.notCheckedIn),
      ]);
      added++;
    }
    return Success(added);
  }

  // ---------------------------------------------------------------------
  // Templates and bulk week operations
  // ---------------------------------------------------------------------

  @override
  Future<Result<List<ShiftTemplate>>> templates(String detachmentId) async {
    await _latency();
    final out = _templates
        .where((t) => t.detachmentId == detachmentId && t.active)
        .toList()
      ..sort((a, b) {
        final byFirst = (a.firstDate ?? DateTime(9999))
            .compareTo(b.firstDate ?? DateTime(9999));
        return byFirst != 0
            ? byFirst
            : a.startMinutes.compareTo(b.startMinutes);
      });
    return Success(out);
  }

  @override
  Future<Result<void>> stopTemplate(String templateId) async {
    await _latency();
    final i = _templates.indexWhere((t) => t.id == templateId);
    if (i < 0) return const Failure('لم يُعثر على القالب.', code: 'not_found');
    // Deactivated, not deleted: the shifts it already produced still point at
    // it, and a past week has to keep reading the way it was worked.
    _templates[i] = _templates[i].copyWith(active: false);
    return const Success(null);
  }

  /// True when [detachmentId] already has a shift at this day and start time.
  bool _exists(String detachmentId, DateTime day, int startMinutes) =>
      _shifts.any((s) =>
          s.detachmentId == detachmentId &&
          s.date == day &&
          s.startMinutes == startMinutes);

  @override
  Future<Result<int>> copyWeek({
    required String detachmentId,
    required DateTime fromWeekStart,
    required DateTime toWeekStart,
  }) async {
    await _latency();
    final from = startOfWeek(fromWeekStart);
    final to = startOfWeek(toWeekStart);
    if (from == to) {
      return const Failure('لا يمكن نسخ الأسبوع على نفسه.', code: 'validation');
    }

    final end = addDays(from, 7);
    final source = _shifts
        .where((s) =>
            s.detachmentId == detachmentId &&
            !s.date.isBefore(from) &&
            s.date.isBefore(end))
        .toList()
      ..sort(_order);

    return Success(_cloneOnto(
      detachmentId: detachmentId,
      source: source,
      // Calendar arithmetic on both halves. `s.date.difference(from).inDays`
      // counts absolute 24-hour spans, so a source week containing a DST
      // change reports six days between two dates that are seven apart and
      // two source days collapse onto one target day; `to.add(Duration(days:
      // n))` then lands the result at 23:00 the previous day when the
      // *target* week changes offset, which stops the copy being a
      // normalized date and makes `_exists` and every `s.date == day` read
      // in this repository miss it. Both failures are silent.
      dayFor: (s) => addDays(to, calendarDaysBetween(from, s.date)),
    ));
  }

  @override
  Future<Result<int>> copyDay({
    required String detachmentId,
    required DateTime fromDay,
    required DateTime toDay,
  }) async {
    await _latency();
    final from = dateOnly(fromDay);
    final to = dateOnly(toDay);
    if (from == to) {
      return const Failure('لا يمكن نسخ اليوم على نفسه.', code: 'validation');
    }

    final source = _shifts
        .where((s) => s.detachmentId == detachmentId && s.date == from)
        .toList()
      ..sort(_order);

    return Success(_cloneOnto(
      detachmentId: detachmentId,
      source: source,
      dayFor: (_) => to,
    ));
  }

  /// Clones [source] onto the day each shift maps to, and answers how many
  /// were actually added.
  ///
  /// Two rules the callers both need and neither should re-implement:
  /// a day+time that already has a shift is skipped, so copying twice is
  /// harmless; and assignments are dropped, because the schedule repeats but
  /// the people on it do not — copying names forward is how a lead ends up
  /// publishing a roster nobody agreed to.
  int _cloneOnto({
    required String detachmentId,
    required List<Shift> source,
    required DateTime Function(Shift) dayFor,
  }) {
    var added = 0;
    for (final s in source) {
      final day = dayFor(s);
      if (_exists(detachmentId, day, s.startMinutes)) continue;
      _shifts.add(Shift(
        id: 'sh${_nextShift++}',
        detachmentId: detachmentId,
        // A copied shift is independent: it does not join the source shift's
        // template, whose date set does not know about this day.
        date: day,
        centerName: s.centerName,
        startMinutes: s.startMinutes,
        endMinutes: s.endMinutes,
        needed: s.needed,
        attendees: const [],
      ));
      added++;
    }
    return added;
  }
}
