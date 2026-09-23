import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/shift/data/mock_shift_repository.dart';
import 'package:mtm/features/shift/domain/attendance_correction.dart';
import 'package:mtm/features/shift/domain/attendance_policy.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/team/data/mock_team_repository.dart';
import 'package:mtm/features/team/domain/team_models.dart';

/// [MockShiftRepository]'s behavior around the one-hour ordinary window and
/// the append-only correction path — the repository half of Task 5. The
/// widget-facing policy math itself is pinned in `attendance_policy_test.dart`;
/// this file is about what the mock actually does when called.

T _ok<T>(Result<T> r) => r.when(
      success: (data, {stale = false}) => data,
      failure: (m, code) => fail('expected success, got failure: $m ($code)'),
      offline: (_) => fail('expected success, got offline'),
    );

String? _code<T>(Result<T> r) => r.when(
      success: (_, {stale = false}) => null,
      failure: (_, code) => code,
      offline: (_) => 'offline',
    );

const _author =
    AttendanceCorrectionAuthor(id: 'u1', displayName: 'أحمد المشرف');

/// A repository with an injectable clock, one freshly-created shift on
/// 2026-07-09 08:00-14:00, and one member assigned to it (seeded
/// `notCheckedIn`, per `assignVolunteer`).
Future<(MockShiftRepository, Shift, String)> _setUp({
  required DateTime Function() clock,
}) async {
  final r = MockShiftRepository(MockTeamRepository(), clock: clock);
  final created = _ok(await r.create(
    detachmentId: 'd_dam_central',
    date: DateTime(2026, 7, 9),
    centerName: 'مركز الاختبار',
    startMinutes: 8 * 60,
    endMinutes: 14 * 60,
    needed: 1,
  ));
  final candidate =
      _ok(await r.candidatesFor(created.id)).firstWhere((c) => !c.busy);
  final assigned =
      _ok(await r.assignVolunteer(created.id, candidate.member.id));
  return (r, assigned, candidate.member.id);
}

void main() {
  group('ordinary path window enforcement', () {
    test('recording works while the window is open', () async {
      final (r, s, memberId) =
          await _setUp(clock: () => DateTime(2026, 7, 9, 10));
      final result =
          await r.recordCheckIn(s.id, memberId, DateTime(2026, 7, 9, 8, 5));
      expect(_code(result), isNull);
      expect(
        _ok(result).attendees.firstWhere((a) => a.id == memberId).attendance,
        AttendanceState.checkedIn,
      );
    });

    test(
        'an ordinary check-in is denied after expiry with a typed, '
        'non-textual failure code', () async {
      final (r, s, memberId) =
          await _setUp(clock: () => DateTime(2026, 7, 9, 15));
      final result =
          await r.recordCheckIn(s.id, memberId, DateTime(2026, 7, 9, 8, 5));
      expect(_code(result), attendanceWindowExpiredCode);
    });

    test(
        'markAbsent, resetAttendance and markAttendance are all gated the '
        'same way once the window closes', () async {
      final (r, s, memberId) =
          await _setUp(clock: () => DateTime(2026, 7, 9, 15));
      expect(_code(await r.markAbsent(s.id, memberId)),
          attendanceWindowExpiredCode);
      expect(_code(await r.resetAttendance(s.id, memberId)),
          attendanceWindowExpiredCode);
      expect(
        _code(
            await r.markAttendance(s.id, memberId, AttendanceState.checkedIn)),
        attendanceWindowExpiredCode,
      );
    });

    test('a denied ordinary edit leaves the previous effective state unchanged',
        () async {
      DateTime now = DateTime(2026, 7, 9, 10);
      final (r, s, memberId) = await _setUp(clock: () => now);
      _ok(await r.recordCheckIn(s.id, memberId, DateTime(2026, 7, 9, 8, 5)));

      now = DateTime(2026, 7, 9, 15); // the window closes
      final before =
          _ok(await r.byId(s.id)).attendees.firstWhere((a) => a.id == memberId);

      final result =
          await r.recordCheckOut(s.id, memberId, DateTime(2026, 7, 9, 13, 55));
      expect(_code(result), attendanceWindowExpiredCode);

      final after =
          _ok(await r.byId(s.id)).attendees.firstWhere((a) => a.id == memberId);
      expect(after.attendance, before.attendance);
      expect(after.checkInAt, before.checkInAt);
      expect(after.checkOutAt, before.checkOutAt);
    });

    test(
        'checkout-before-checkin validation still holds while the window is open',
        () async {
      final (r, s, memberId) =
          await _setUp(clock: () => DateTime(2026, 7, 9, 10));
      _ok(await r.recordCheckIn(s.id, memberId, DateTime(2026, 7, 9, 9)));
      final result =
          await r.recordCheckOut(s.id, memberId, DateTime(2026, 7, 9, 8));
      expect(_code(result), 'checkout_before_checkin');
    });
  });

  group('addAttendanceCorrection — override authority', () {
    test('permits a correction after the window has expired', () async {
      final now = DateTime(2026, 7, 9, 15);
      final (r, s, memberId) = await _setUp(clock: () => now);
      final result = await r.addAttendanceCorrection(
        shiftId: s.id,
        memberId: memberId,
        status: AttendanceState.checkedIn,
        checkInAt: DateTime(2026, 7, 9, 8, 3),
        reason: 'نسي المشرف تسجيل الدخول وقت الشفت',
        author: _author,
        correctedAt: now,
      );
      expect(_code(result), isNull);
    });

    test(
        'has no lifetime expiry — a correction years after the shift still succeeds',
        () async {
      final now = DateTime(2030, 1, 1);
      final (r, s, memberId) = await _setUp(clock: () => now);
      final result = await r.addAttendanceCorrection(
        shiftId: s.id,
        memberId: memberId,
        status: AttendanceState.absent,
        reason: 'تصحيح متأخر جدا اكتُشف لاحقا',
        author: _author,
        correctedAt: now,
      );
      expect(_code(result), isNull);
    });

    test('a blank reason is rejected', () async {
      final (r, s, memberId) =
          await _setUp(clock: () => DateTime(2026, 7, 9, 15));
      final result = await r.addAttendanceCorrection(
        shiftId: s.id,
        memberId: memberId,
        status: AttendanceState.absent,
        reason: '   ',
        author: _author,
        correctedAt: DateTime(2026, 7, 9, 15),
      );
      expect(_code(result), 'validation');
    });

    test('a whitespace-only reason is rejected the same as an empty one',
        () async {
      final (r, s, memberId) =
          await _setUp(clock: () => DateTime(2026, 7, 9, 15));
      final result = await r.addAttendanceCorrection(
        shiftId: s.id,
        memberId: memberId,
        status: AttendanceState.absent,
        reason: '\n\t  ',
        author: _author,
        correctedAt: DateTime(2026, 7, 9, 15),
      );
      expect(_code(result), 'validation');
    });

    test('a valid reason is normalized (collapsed whitespace) and retained',
        () async {
      final (r, s, memberId) =
          await _setUp(clock: () => DateTime(2026, 7, 9, 15));
      final result = _ok(await r.addAttendanceCorrection(
        shiftId: s.id,
        memberId: memberId,
        status: AttendanceState.checkedOut,
        checkInAt: DateTime(2026, 7, 9, 8),
        checkOutAt: DateTime(2026, 7, 9, 14),
        reason: '  سبب   يحوي   مسافات   زائدة  ',
        author: _author,
        correctedAt: DateTime(2026, 7, 9, 15),
      ));
      final correction = result.correctionsFor(memberId).single;
      expect(correction.reason, 'سبب يحوي مسافات زائدة');
    });

    test('appends rather than replacing prior history', () async {
      DateTime now = DateTime(2026, 7, 9, 15);
      final (r, s, memberId) = await _setUp(clock: () => now);

      final first = _ok(await r.addAttendanceCorrection(
        shiftId: s.id,
        memberId: memberId,
        status: AttendanceState.checkedIn,
        checkInAt: DateTime(2026, 7, 9, 8),
        reason: 'أول تصحيح',
        author: _author,
        correctedAt: now,
      ));
      expect(first.correctionsFor(memberId), hasLength(1));

      now = DateTime(2026, 7, 10);
      final second = _ok(await r.addAttendanceCorrection(
        shiftId: s.id,
        memberId: memberId,
        status: AttendanceState.checkedOut,
        checkInAt: DateTime(2026, 7, 9, 8),
        checkOutAt: DateTime(2026, 7, 9, 14),
        reason: 'ثاني تصحيح',
        author: _author,
        correctedAt: now,
      ));
      final all = second.correctionsFor(memberId);
      expect(all, hasLength(2));
      expect(all[0].reason, 'أول تصحيح');
      expect(all[1].reason, 'ثاني تصحيح');
      expect(all[0].id, isNot(all[1].id));
    });

    test('before/after snapshots are accurate', () async {
      final (r, s, memberId) =
          await _setUp(clock: () => DateTime(2026, 7, 9, 15));
      final result = _ok(await r.addAttendanceCorrection(
        shiftId: s.id,
        memberId: memberId,
        status: AttendanceState.checkedIn,
        checkInAt: DateTime(2026, 7, 9, 8, 10),
        reason: 'سبب التصحيح',
        author: _author,
        correctedAt: DateTime(2026, 7, 9, 15),
      ));
      final correction = result.correctionsFor(memberId).single;
      expect(correction.before.status, AttendanceState.notCheckedIn);
      expect(correction.before.checkInAt, isNull);
      expect(correction.after.status, AttendanceState.checkedIn);
      expect(correction.after.checkInAt, DateTime(2026, 7, 9, 8, 10));
      expect(correction.author.displayName, 'أحمد المشرف');
    });

    test('the effective attendance reflects the latest correction', () async {
      final (r, s, memberId) =
          await _setUp(clock: () => DateTime(2026, 7, 9, 15));
      final result = _ok(await r.addAttendanceCorrection(
        shiftId: s.id,
        memberId: memberId,
        status: AttendanceState.absent,
        reason: 'غاب فعليا رغم عدم تسجيل ذلك',
        author: _author,
        correctedAt: DateTime(2026, 7, 9, 15),
      ));
      final member = result.attendees.firstWhere((a) => a.id == memberId);
      expect(member.attendance, AttendanceState.absent);
      expect(member.checkInAt, isNull);
      expect(member.checkOutAt, isNull);
    });

    test('statistics read the corrected state once, never doubled', () async {
      final (r, s, memberId) =
          await _setUp(clock: () => DateTime(2026, 7, 9, 15));
      final before = AttendanceStatistics.fromShifts([s]);
      expect(before.presentCount, 0);
      expect(before.pendingCount, 1);

      final corrected = _ok(await r.addAttendanceCorrection(
        shiftId: s.id,
        memberId: memberId,
        status: AttendanceState.checkedIn,
        checkInAt: DateTime(2026, 7, 9, 8),
        reason: 'حضر بالفعل ولم يُسجَّل',
        author: _author,
        correctedAt: DateTime(2026, 7, 9, 15),
      ));
      final after = AttendanceStatistics.fromShifts([corrected]);
      expect(after.presentCount, 1);
      expect(after.pendingCount, 0);
      // One shift, one member — the append must not fan out into two rows.
      expect(after.records, hasLength(1));
    });

    test(
        'a checkout before its check-in is rejected the same way the '
        'ordinary path rejects it', () async {
      final (r, s, memberId) =
          await _setUp(clock: () => DateTime(2026, 7, 9, 15));
      final result = await r.addAttendanceCorrection(
        shiftId: s.id,
        memberId: memberId,
        status: AttendanceState.checkedOut,
        checkInAt: DateTime(2026, 7, 9, 10),
        checkOutAt: DateTime(2026, 7, 9, 9),
        reason: 'سبب',
        author: _author,
        correctedAt: DateTime(2026, 7, 9, 15),
      );
      expect(_code(result), 'checkout_before_checkin');
    });

    test(
        'overnight normalization applies to a correction exactly as it does '
        'to the ordinary path', () async {
      final r = MockShiftRepository(MockTeamRepository(),
          clock: () => DateTime(2026, 7, 11));
      final created = _ok(await r.create(
        detachmentId: 'd_dam_central',
        date: DateTime(2026, 7, 9),
        centerName: 'مركز ليلي',
        startMinutes: 20 * 60,
        endMinutes: 2 * 60,
        needed: 1,
      ));
      final candidate =
          _ok(await r.candidatesFor(created.id)).firstWhere((c) => !c.busy);
      final assigned =
          _ok(await r.assignVolunteer(created.id, candidate.member.id));

      final result = _ok(await r.addAttendanceCorrection(
        shiftId: assigned.id,
        memberId: candidate.member.id,
        status: AttendanceState.checkedOut,
        checkInAt: DateTime(2026, 7, 9, 21),
        checkOutAt: DateTime(2026, 7, 9, 1), // clock-before-checkin on paper
        reason: 'تصحيح شفت ليلي',
        author: _author,
        correctedAt: DateTime(2026, 7, 11),
      ));
      final member =
          result.attendees.firstWhere((a) => a.id == candidate.member.id);
      expect(member.checkOutAt?.day, 10); // rolled to the next calendar day
      expect(member.checkOutAt!.isAfter(member.checkInAt!), isTrue);
    });

    test(
        'a failed correction (blank reason) leaves state and history unchanged',
        () async {
      final now = DateTime(2026, 7, 9, 15);
      final (r, s, memberId) = await _setUp(clock: () => now);
      final seeded = _ok(await r.addAttendanceCorrection(
        shiftId: s.id,
        memberId: memberId,
        status: AttendanceState.checkedIn,
        checkInAt: DateTime(2026, 7, 9, 8),
        reason: 'تصحيح أولي صالح',
        author: _author,
        correctedAt: now,
      ));
      final beforeCorrections = seeded.correctionsFor(memberId);
      final beforeMember = seeded.attendees.firstWhere((a) => a.id == memberId);

      final failed = await r.addAttendanceCorrection(
        shiftId: s.id,
        memberId: memberId,
        status: AttendanceState.absent,
        reason: '   ',
        author: _author,
        correctedAt: now,
      );
      expect(_code(failed), 'validation');

      final after = _ok(await r.byId(s.id));
      expect(
        after.correctionsFor(memberId).map((c) => c.id).toList(),
        beforeCorrections.map((c) => c.id).toList(),
      );
      final afterMember = after.attendees.firstWhere((a) => a.id == memberId);
      expect(afterMember.attendance, beforeMember.attendance);
      expect(afterMember.checkInAt, beforeMember.checkInAt);
    });

    test(
        'correcting one member never touches another attendee on the same shift',
        () async {
      final (r, s, memberId) =
          await _setUp(clock: () => DateTime(2026, 7, 9, 15));
      final other = _ok(await r.candidatesFor(s.id)).firstWhere((c) => !c.busy);
      final withOther = _ok(await r.assignVolunteer(s.id, other.member.id));

      final result = _ok(await r.addAttendanceCorrection(
        shiftId: withOther.id,
        memberId: memberId,
        status: AttendanceState.checkedIn,
        checkInAt: DateTime(2026, 7, 9, 8),
        reason: 'سبب يخص عضوا واحدا',
        author: _author,
        correctedAt: DateTime(2026, 7, 9, 15),
      ));
      final untouched =
          result.attendees.firstWhere((a) => a.id == other.member.id);
      expect(untouched.attendance, AttendanceState.notCheckedIn);
      expect(result.correctionsFor(other.member.id), isEmpty);
    });
  });
}
