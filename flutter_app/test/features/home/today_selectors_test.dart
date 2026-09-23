import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/features/detachment/domain/storage_status.dart';
import 'package:mtm/features/home/domain/home_models.dart';
import 'package:mtm/features/home/domain/today_selectors.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/shift/domain/shift_selectors.dart';
import 'package:mtm/features/team/domain/team_models.dart';

/// The dashboard's decision layer. Everything here is invisible on screen when
/// it is wrong — a shift silently reported as "now" that ended an hour ago, an
/// alert raised for a user who cannot act on it — so it is pinned here rather
/// than eyeballed.

const _det = 'd1';
final _today = DateTime(2026, 9, 5);

TeamMember _member(String id, AttendanceState state,
        {TeamRole role = TeamRole.member}) =>
    TeamMember(
      id: id,
      name: id,
      initials: 'x',
      role: role,
      detachmentId: _det,
      attendance: state,
    );

Shift _shift({
  required String id,
  required DateTime date,
  required int startMinutes,
  required int endMinutes,
  int needed = 2,
  List<TeamMember> attendees = const [],
}) =>
    Shift(
      id: id,
      detachmentId: _det,
      date: date,
      centerName: 'مركز',
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      needed: needed,
      attendees: attendees,
    );

HomeSummary _summary({
  List<Shift> shifts = const [],
  StorageStatus storage = StorageStatus.healthy,
  int lowStock = 0,
  int expiring = 0,
}) =>
    HomeSummary(
      detachmentId: _det,
      detachmentName: 'مفرزة',
      region: 'دمشق',
      mainCenter: 'مركز',
      shifts: shifts,
      rosterCount: 5,
      storageStatus: storage,
      lowStockCount: lowStock,
      expiringSoonCount: expiring,
    );

/// Everything granted inside `_det`, which is what a sub-Admin session looks
/// like to these functions.
const _operator = Capabilities(scoped: {_det: Cap.scoped});
const _volunteer = Capabilities(
  scoped: {
    _det: {Cap.detachmentView, Cap.memberView}
  },
);

void main() {
  group('current and next shift', () {
    test(
        'a night shift from yesterday is still the current one after '
        'midnight', () {
      // 20:00 → 02:00 dated the 4th, asked at 01:00 on the 5th. Reading the
      // calendar day instead of the clock would report "no shift running".
      final night = _shift(
        id: 'night',
        date: _today.subtract(const Duration(days: 1)),
        startMinutes: 20 * 60,
        endMinutes: 2 * 60,
      );
      final morning = _shift(
        id: 'morning',
        date: _today,
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
      );
      final now = DateTime(2026, 9, 5, 1);

      expect(currentShiftOf([night, morning], now)?.id, 'night');
      expect(nextShiftOf([night, morning], now)?.id, 'morning');
    });

    test('a shift that has just ended is neither current nor next', () {
      final ended = _shift(
        id: 'ended',
        date: _today,
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
      );
      final now = DateTime(2026, 9, 5, 14, 0, 1);

      expect(currentShiftOf([ended], now), isNull);
      expect(nextShiftOf([ended], now), isNull);
    });

    test(
        'the boundary belongs to the shift that is starting, not the one '
        'that ended', () {
      final first = _shift(
          id: 'first', date: _today, startMinutes: 8 * 60, endMinutes: 14 * 60);
      final second = _shift(
          id: 'second',
          date: _today,
          startMinutes: 14 * 60,
          endMinutes: 20 * 60);
      final now = DateTime(2026, 9, 5, 14);

      expect(currentShiftOf([first, second], now)?.id, 'second');
    });

    test(
        'overlapping shifts resolve to the earlier start, whatever the list '
        'order', () {
      final late = _shift(
          id: 'late', date: _today, startMinutes: 10 * 60, endMinutes: 16 * 60);
      final early = _shift(
          id: 'early', date: _today, startMinutes: 8 * 60, endMinutes: 16 * 60);
      final now = DateTime(2026, 9, 5, 11);

      expect(currentShiftOf([late, early], now)?.id, 'early');
      expect(currentShiftOf([early, late], now)?.id, 'early');
    });

    test('next reaches into tomorrow when today is finished', () {
      final tomorrow = _shift(
        id: 'tomorrow',
        date: _today.add(const Duration(days: 1)),
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
      );
      final now = DateTime(2026, 9, 5, 22);

      expect(nextShiftOf([tomorrow], now)?.id, 'tomorrow');
      expect(shiftsOnDay([tomorrow], now), isEmpty);
    });
  });

  group('attendance counting', () {
    test('checked-out counts as present, and the rest are counted apart', () {
      final shift = _shift(
        id: 's',
        date: _today,
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
        needed: 5,
        attendees: [
          _member('a', AttendanceState.checkedIn),
          _member('b', AttendanceState.checkedOut),
          _member('c', AttendanceState.absent),
          _member('d', AttendanceState.notCheckedIn),
        ],
      );

      expect(
        attendanceOf(shift),
        const TodayAttendance(
          needed: 5,
          assigned: 4,
          present: 2,
          absent: 1,
          awaiting: 1,
        ),
      );
      expect(attendanceOf(shift).gap, 1);
      expect(attendanceOf(shift).progress, 0.5);
    });

    test(
        'an unstaffed shift reports zero progress rather than dividing by '
        'zero', () {
      final shift = _shift(
          id: 's', date: _today, startMinutes: 8 * 60, endMinutes: 14 * 60);
      expect(attendanceOf(shift).progress, 0);
      expect(attendanceOf(null), TodayAttendance.none);
    });
  });

  group('alert visibility', () {
    test(
        'a volunteer is not told about gaps, attendance, or stock they '
        'cannot act on', () {
      final now = DateTime(2026, 9, 5, 10);
      final understaffed = _shift(
        id: 'gap',
        date: _today,
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
        needed: 4,
        attendees: [_member('a', AttendanceState.checkedIn)],
      );

      final alerts = buildDashboardAlerts(
        summary: _summary(
          shifts: [understaffed],
          storage: StorageStatus.low,
          lowStock: 3,
        ),
        now: now,
        capabilities: _volunteer,
      );

      expect(alerts, isEmpty);
    });

    test('an operator sees the gap and the stock warning, worst first', () {
      final now = DateTime(2026, 9, 5, 10);
      final understaffed = _shift(
        id: 'gap',
        date: _today,
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
        needed: 4,
        attendees: [_member('a', AttendanceState.checkedIn)],
      );

      final alerts = buildDashboardAlerts(
        summary: _summary(
          shifts: [understaffed],
          storage: StorageStatus.low,
          lowStock: 3,
        ),
        now: now,
        capabilities: _operator,
      );

      expect(
        alerts.map((a) => a.kind),
        [DashboardAlertKind.understaffedShift, DashboardAlertKind.lowStock],
      );
      expect(alerts.first.count, 3, reason: 'four needed, one assigned');
      expect(alerts.first.shiftId, 'gap');
    });

    test('a gap on a shift that already ended is history, not a decision', () {
      final ended = _shift(
        id: 'gap',
        date: _today,
        startMinutes: 8 * 60,
        endMinutes: 14 * 60,
        needed: 4,
        attendees: [_member('a', AttendanceState.checkedIn)],
      );

      final alerts = buildDashboardAlerts(
        summary: _summary(shifts: [ended]),
        now: DateTime(2026, 9, 5, 14, 30),
        capabilities: _operator,
      );

      expect(
        alerts.where((a) => a.kind == DashboardAlertKind.understaffedShift),
        isEmpty,
      );
    });

    test(
        'missing attendance is raised only after the shift ends and only '
        'while the one-hour window is open', () {
      Shift shiftWith(AttendanceState state) => _shift(
            id: 'att',
            date: _today,
            startMinutes: 8 * 60,
            endMinutes: 14 * 60,
            needed: 1,
            attendees: [_member('a', state)],
          );

      List<DashboardAlertKind> kindsAt(DateTime now, AttendanceState state) =>
          buildDashboardAlerts(
            summary: _summary(shifts: [shiftWith(state)]),
            now: now,
            capabilities: _operator,
          ).map((a) => a.kind).toList();

      // Still running: not missing, just not over.
      expect(
        kindsAt(DateTime(2026, 9, 5, 12), AttendanceState.notCheckedIn),
        isNot(contains(DashboardAlertKind.missingAttendance)),
      );
      // Ended, window open.
      expect(
        kindsAt(DateTime(2026, 9, 5, 14, 30), AttendanceState.notCheckedIn),
        contains(DashboardAlertKind.missingAttendance),
      );
      // Window closed an hour after the end — no longer a tap away.
      expect(
        kindsAt(DateTime(2026, 9, 5, 15, 30), AttendanceState.notCheckedIn),
        isNot(contains(DashboardAlertKind.missingAttendance)),
      );
      // Someone marked absent is recorded, not missing.
      expect(
        kindsAt(DateTime(2026, 9, 5, 14, 30), AttendanceState.absent),
        isNot(contains(DashboardAlertKind.missingAttendance)),
      );
    });

    test('sync alerts are the user\'s own queued work, so no grant gates them',
        () {
      final alerts = buildDashboardAlerts(
        summary: _summary(),
        now: DateTime(2026, 9, 5, 10),
        capabilities: _volunteer,
        pendingOperations: 2,
        operationsNeedingReview: 1,
      );

      expect(
        alerts.map((a) => a.kind),
        [DashboardAlertKind.needsReview, DashboardAlertKind.pendingSync],
      );
    });

    test('a failed run reports the failure instead of a second pending line',
        () {
      final alerts = buildDashboardAlerts(
        summary: _summary(),
        now: DateTime(2026, 9, 5, 10),
        capabilities: _operator,
        pendingOperations: 3,
        lastSyncFailed: true,
      );

      expect(alerts.map((a) => a.kind), [DashboardAlertKind.failedSync]);
      expect(alerts.single.count, 3);
    });

    test('a healthy detachment with nothing queued raises nothing at all', () {
      expect(
        buildDashboardAlerts(
          summary: _summary(
            shifts: [
              _shift(
                id: 'ok',
                date: _today,
                startMinutes: 8 * 60,
                endMinutes: 14 * 60,
                needed: 1,
                attendees: [_member('a', AttendanceState.checkedIn)],
              ),
            ],
          ),
          now: DateTime(2026, 9, 5, 10),
          capabilities: _operator,
        ),
        isEmpty,
      );
    });

    test(
        'an empty store raises no stock alert — nothing is known, so nothing '
        'is claimed', () {
      expect(
        buildDashboardAlerts(
          summary: _summary(storage: StorageStatus.empty),
          now: DateTime(2026, 9, 5, 10),
          capabilities: _operator,
        ),
        isEmpty,
      );
    });
  });
}
