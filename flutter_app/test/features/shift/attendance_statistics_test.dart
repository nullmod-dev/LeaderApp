import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/shift/data/shift_providers.dart';
import 'package:mtm/features/shift/data/mock_shift_repository.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/team/data/mock_team_repository.dart';
import 'package:mtm/features/team/domain/team_models.dart';

T _success<T>(Result<T> result) => result.when(
      success: (data, {stale = false}) => data,
      failure: (message, code) => fail('$message ($code)'),
      offline: (_) => fail('offline'),
    );

String? _code<T>(Result<T> result) => result.when(
      success: (_, {stale = false}) => null,
      failure: (_, code) => code,
      offline: (_) => 'offline',
    );

void main() {
  test('last check-in and checkout defaults persist independently', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final checkIn = DateTime(2026, 9, 2, 8, 15);
    final checkOut = DateTime(2026, 9, 2, 14, 10);
    final notifier =
        container.read(attendanceEntryDefaultsProvider('shift').notifier);
    notifier.state = notifier.state.copyWith(checkInAt: checkIn);
    notifier.state = notifier.state.copyWith(checkOutAt: checkOut);
    final defaults = container.read(attendanceEntryDefaultsProvider('shift'));
    expect(defaults.checkInAt, checkIn);
    expect(defaults.checkOutAt, checkOut);
  });

  test('check-in/out edits preserve dates and affect only one member',
      () async {
    // Frozen at the start of "this week" so the one-hour attendance window
    // stays open for every seeded shift touched below, regardless of which
    // real day/time the suite runs on — see `schedule_test.dart`'s `_repo()`
    // for the same reasoning, and `attendance_policy_test.dart` for the
    // window's own boundary tests.
    final repository = MockShiftRepository(
      MockTeamRepository(),
      clock: () => startOfWeek(DateTime.now()),
    );
    final week = startOfWeek(DateTime.now());
    final shift = _success(await repository.listForWeek('d_dam_central', week))
        .firstWhere((value) => value.attendees.length >= 2);
    final member = shift.attendees.first;
    final untouched = shift.attendees[1];
    final checkIn = shift.start.add(const Duration(minutes: 7));
    final checkOut = shift.end.subtract(const Duration(minutes: 3));

    _success(await repository.recordCheckIn(shift.id, member.id, checkIn));
    final completed = _success(
      await repository.recordCheckOut(shift.id, member.id, checkOut),
    );
    final updated = completed.attendees.firstWhere((x) => x.id == member.id);
    expect(updated.attendance, AttendanceState.checkedOut);
    expect(updated.checkInAt, checkIn);
    expect(updated.checkOutAt, checkOut);
    expect(
      completed.attendees.firstWhere((x) => x.id == untouched.id).checkInAt,
      untouched.checkInAt,
    );

    final editedCheckIn = checkIn.add(const Duration(minutes: 2));
    final edited = _success(
      await repository.recordCheckIn(shift.id, member.id, editedCheckIn),
    );
    final editedMember = edited.attendees.firstWhere((x) => x.id == member.id);
    expect(editedMember.checkInAt, editedCheckIn);
    expect(editedMember.checkOutAt, checkOut);
  });

  test('overnight checkout on the shift date resolves to the next day',
      () async {
    // Frozen at the start of "this week" so the one-hour attendance window
    // stays open for every seeded shift touched below, regardless of which
    // real day/time the suite runs on — see `schedule_test.dart`'s `_repo()`
    // for the same reasoning, and `attendance_policy_test.dart` for the
    // window's own boundary tests.
    final repository = MockShiftRepository(
      MockTeamRepository(),
      clock: () => startOfWeek(DateTime.now()),
    );
    final day = dateOnly(DateTime.now()).add(const Duration(days: 20));
    final shift = _success(await repository.create(
      detachmentId: 'd_dam_central',
      date: day,
      centerName: 'Night center',
      startMinutes: 20 * 60,
      endMinutes: 2 * 60,
      needed: 2,
    ));
    final candidate = _success(await repository.candidatesFor(shift.id))
        .firstWhere((value) => !value.busy);
    _success(await repository.assignVolunteer(shift.id, candidate.member.id));
    final checkIn = day.add(const Duration(hours: 23));
    _success(await repository.recordCheckIn(
      shift.id,
      candidate.member.id,
      checkIn,
    ));
    final completed = _success(await repository.recordCheckOut(
      shift.id,
      candidate.member.id,
      day.add(const Duration(hours: 1)),
    ));
    final attendee = completed.attendees.single;
    expect(attendee.checkOutAt?.day, day.add(const Duration(days: 1)).day);
    expect(attendee.checkOutAt!.isAfter(checkIn), isTrue);
  });

  test('day shift rejects checkout before check-in', () async {
    // Frozen at the start of "this week" so the one-hour attendance window
    // stays open for every seeded shift touched below, regardless of which
    // real day/time the suite runs on — see `schedule_test.dart`'s `_repo()`
    // for the same reasoning, and `attendance_policy_test.dart` for the
    // window's own boundary tests.
    final repository = MockShiftRepository(
      MockTeamRepository(),
      clock: () => startOfWeek(DateTime.now()),
    );
    final week = startOfWeek(DateTime.now());
    final shift = _success(await repository.listForWeek('d_dam_central', week))
        .firstWhere(
            (value) => value.attendees.isNotEmpty && !value.crossesMidnight);
    final member = shift.attendees.first;
    _success(await repository.recordCheckIn(
      shift.id,
      member.id,
      shift.start.add(const Duration(hours: 2)),
    ));
    final result = await repository.recordCheckOut(
      shift.id,
      member.id,
      shift.start.add(const Duration(hours: 1)),
    );
    expect(_code(result), 'checkout_before_checkin');
  });

  test('statistics follow reviewed-row totals and support member filtering',
      () {
    TeamMember member(String id, AttendanceState state) => TeamMember(
          id: id,
          name: 'Member $id',
          initials: 'M',
          role: TeamRole.member,
          detachmentId: 'd',
          attendance: state,
          checkInAt: state == AttendanceState.checkedOut
              ? DateTime(2026, 9, 1, 8)
              : null,
          checkOutAt: state == AttendanceState.checkedOut
              ? DateTime(2026, 9, 1, 14)
              : null,
        );
    Shift shift(String id, int day, List<TeamMember> attendees) => Shift(
          id: id,
          detachmentId: 'd',
          date: DateTime(2026, 9, day),
          centerName: 'Center',
          startMinutes: 480,
          endMinutes: 840,
          needed: 2,
          attendees: attendees,
        );
    final shifts = [
      shift('s1', 1, [
        member('a', AttendanceState.checkedOut),
        member('b', AttendanceState.absent),
      ]),
      shift('s2', 2, [
        member('a', AttendanceState.checkedIn),
        member('b', AttendanceState.notCheckedIn),
      ]),
    ];
    final all = AttendanceStatistics.fromShifts(shifts);
    expect(all.presentCount, 2);
    expect(all.absentCount, 1);
    expect(all.completedCount, 1);
    expect(all.attendancePercent, 67);
    expect(all.members.first.records.first.shiftDate.day, 2);

    final filtered = AttendanceStatistics.fromShifts(shifts, memberId: 'b');
    expect(filtered.members, hasLength(1));
    expect(filtered.absentCount, 1);
    expect(filtered.presentCount, 0);
  });

  test('absence and reset clear the timestamps they replace', () async {
    // Frozen at the start of "this week" so the one-hour attendance window
    // stays open for every seeded shift touched below, regardless of which
    // real day/time the suite runs on — see `schedule_test.dart`'s `_repo()`
    // for the same reasoning, and `attendance_policy_test.dart` for the
    // window's own boundary tests.
    final repository = MockShiftRepository(
      MockTeamRepository(),
      clock: () => startOfWeek(DateTime.now()),
    );
    final week = startOfWeek(DateTime.now());
    final shift = _success(await repository.listForWeek('d_dam_central', week))
        .firstWhere((value) => value.attendees.length >= 2);
    final member = shift.attendees.first;
    final other = shift.attendees[1];

    _success(await repository.recordCheckIn(
        shift.id, member.id, shift.start.add(const Duration(minutes: 5))));
    _success(await repository.recordCheckOut(
        shift.id, member.id, shift.end.subtract(const Duration(minutes: 5))));
    _success(await repository.recordCheckIn(
        shift.id, other.id, shift.start.add(const Duration(minutes: 9))));
    final otherCheckIn = shift.start.add(const Duration(minutes: 9));

    final absent = _success(await repository.markAbsent(shift.id, member.id));
    final marked = absent.attendees.firstWhere((x) => x.id == member.id);
    expect(marked.attendance, AttendanceState.absent);
    expect(marked.checkInAt, isNull);
    expect(marked.checkOutAt, isNull);
    // Marking one member never touches another's record.
    expect(
      absent.attendees.firstWhere((x) => x.id == other.id).checkInAt,
      otherCheckIn,
    );

    final reset =
        _success(await repository.resetAttendance(shift.id, member.id));
    final cleared = reset.attendees.firstWhere((x) => x.id == member.id);
    expect(cleared.attendance, AttendanceState.notCheckedIn);
    expect(cleared.checkInAt, isNull);
    expect(cleared.checkOutAt, isNull);
    expect(
      reset.attendees.firstWhere((x) => x.id == other.id).attendance,
      AttendanceState.checkedIn,
    );
  });

  test('a retained default seeds the next entry without rewriting a saved one',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Frozen at the start of "this week" so the one-hour attendance window
    // stays open for every seeded shift touched below, regardless of which
    // real day/time the suite runs on — see `schedule_test.dart`'s `_repo()`
    // for the same reasoning, and `attendance_policy_test.dart` for the
    // window's own boundary tests.
    final repository = MockShiftRepository(
      MockTeamRepository(),
      clock: () => startOfWeek(DateTime.now()),
    );
    final week = startOfWeek(DateTime.now());
    final shift = _success(await repository.listForWeek('d_dam_central', week))
        .firstWhere((value) => value.attendees.length >= 2);
    final first = shift.attendees.first;
    final second = shift.attendees[1];

    final firstCheckIn = shift.start.add(const Duration(minutes: 4));
    _success(await repository.recordCheckIn(shift.id, first.id, firstCheckIn));
    // What the attendance sheet stores after a successful save.
    final defaults =
        container.read(attendanceEntryDefaultsProvider(shift.id).notifier);
    defaults.state = defaults.state.copyWith(checkInAt: firstCheckIn);

    // The next member starts from that default...
    final reused =
        container.read(attendanceEntryDefaultsProvider(shift.id)).checkInAt!;
    final saved =
        _success(await repository.recordCheckIn(shift.id, second.id, reused));
    expect(
      saved.attendees.firstWhere((x) => x.id == second.id).checkInAt,
      firstCheckIn,
    );

    // ...and moving the default afterwards leaves both saved rows alone.
    final later = firstCheckIn.add(const Duration(minutes: 30));
    defaults.state = defaults.state.copyWith(checkInAt: later);
    final current = _success(await repository.byId(shift.id));
    expect(
      current.attendees.firstWhere((x) => x.id == first.id).checkInAt,
      firstCheckIn,
    );
    expect(
      current.attendees.firstWhere((x) => x.id == second.id).checkInAt,
      firstCheckIn,
    );
    expect(
      container.read(attendanceEntryDefaultsProvider(shift.id)).checkInAt,
      later,
    );
  });

  group('legacy parity', () {
    // The legacy program (medical_team) computed
    //   present = COUNT(status = 'present')
    //   total   = COUNT(*)                     -- status is present|absent only
    //   percent = round(present / total * 100).clamp(0, 100), 0 when total = 0
    // over attendance rows of non-cancelled occurrences. These tests pin the
    // same arithmetic, and pin the one state legacy could not represent.
    TeamMember member(String id, AttendanceState state) => TeamMember(
          id: id,
          name: 'Member $id',
          initials: 'M',
          role: TeamRole.member,
          detachmentId: 'd',
          attendance: state,
        );
    Shift shift(String id, int day, List<TeamMember> attendees) => Shift(
          id: id,
          detachmentId: 'd',
          date: DateTime(2026, 9, day),
          centerName: 'Center',
          startMinutes: 480,
          endMinutes: 840,
          needed: 2,
          attendees: attendees,
        );

    test('no reviewed rows reads as zero percent, never as a division error',
        () {
      final empty = AttendanceStatistics.fromShifts([
        shift('s', 1, [member('a', AttendanceState.notCheckedIn)]),
      ]);
      expect(empty.reviewedCount, 0);
      expect(empty.attendancePercent, 0);
      expect(empty.pendingCount, 1);
    });

    test('the percentage rounds and stays inside 0..100', () {
      final all = AttendanceStatistics.fromShifts([
        shift('s', 1, [
          member('a', AttendanceState.checkedOut),
          member('b', AttendanceState.checkedIn),
        ]),
      ]);
      expect(all.attendancePercent, 100);

      final none = AttendanceStatistics.fromShifts([
        shift('s', 1, [member('a', AttendanceState.absent)]),
      ]);
      expect(none.attendancePercent, 0);

      // 1 of 3 reviewed → 33.33… rounds to 33.
      final third = AttendanceStatistics.fromShifts([
        shift('s', 1, [
          member('a', AttendanceState.checkedIn),
          member('b', AttendanceState.absent),
          member('c', AttendanceState.absent),
        ]),
      ]);
      expect(third.attendancePercent, 33);
    });

    test('an unreviewed assignment is not counted as an absence', () {
      final stats = AttendanceStatistics.fromShifts([
        shift('s', 1, [
          member('a', AttendanceState.checkedIn),
          member('b', AttendanceState.notCheckedIn),
        ]),
      ]);
      // Legacy would have read 50% here, because its seeded row defaulted to
      // 'absent'. This app keeps the two apart, so the denominator is 1.
      expect(stats.absentCount, 0);
      expect(stats.pendingCount, 1);
      expect(stats.reviewedCount, 1);
      expect(stats.attendancePercent, 100);
    });

    test('the report reads a member\'s days oldest first, the screen newest',
        () {
      final stats = AttendanceStatistics.fromShifts([
        shift('s1', 1, [member('a', AttendanceState.checkedOut)]),
        shift('s2', 5, [member('a', AttendanceState.absent)]),
        shift('s3', 3, [member('a', AttendanceState.checkedIn)]),
      ]);
      final summary = stats.members.single;
      expect([for (final r in summary.records) r.shiftDate.day], [5, 3, 1]);
      expect(
        [for (final r in summary.recordsOldestFirst) r.shiftDate.day],
        [1, 3, 5],
      );
    });
  });
}
