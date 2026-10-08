import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../../team/domain/team_models.dart';
import '../domain/attendance_correction.dart';
import '../domain/shift_models.dart';
import '../domain/shift_repository.dart';

/// `/detachments/:id/shifts/**`, `/shifts/**`, `/shift-templates/**`
/// (`docs/api/shifts.md`). Attendance windows, overlap and the template
/// reconciliation rules are the server's; this class only speaks the wire.
class HttpShiftRepository implements ShiftRepository {
  HttpShiftRepository(this._api);

  final ApiClient _api;

  static Shift _shift(Object? json) =>
      Shift.fromJson(json as Map<String, dynamic>);

  static ShiftTemplate _template(Object? json) =>
      ShiftTemplate.fromJson(json as Map<String, dynamic>);

  static List<Shift> _shifts(Object? json) =>
      [for (final row in json as List) _shift(row)];

  static String _det(String id) => '/detachments/${Uri.encodeComponent(id)}';
  static String _one(String id) => '/shifts/${Uri.encodeComponent(id)}';
  static String _member(String shiftId, String memberId) =>
      '${_one(shiftId)}/members/${Uri.encodeComponent(memberId)}';
  static String _tpl(String id) =>
      '/shift-templates/${Uri.encodeComponent(id)}';

  /// A calendar day on the wire: `YYYY-MM-DD`, never an instant.
  static String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// An instant on the wire: RFC 3339 UTC.
  static String _instant(DateTime d) => d.toUtc().toIso8601String();

  @override
  Future<Result<List<Shift>>> listForWeek(
    String detachmentId,
    DateTime weekStart,
  ) =>
      _api.send(
        'GET',
        '${_det(detachmentId)}/shifts/week',
        query: {'weekStart': _day(weekStart)},
        parse: (json) => _shifts((json as Map<String, dynamic>)['shifts']),
      );

  @override
  Future<Result<List<Shift>>> listForRange(
    String detachmentId,
    DateTime from,
    DateTime to,
  ) =>
      _api.send(
        'GET',
        '${_det(detachmentId)}/shifts',
        query: {'from': _day(from), 'to': _day(to)},
        parse: _shifts,
      );

  @override
  Future<Result<List<Shift>>> listForDetachmentToday(String detachmentId) =>
      _api.send('GET', '${_det(detachmentId)}/shifts/today', parse: _shifts);

  @override
  Future<Result<Shift>> byId(String id) =>
      _api.send('GET', _one(id), parse: _shift);

  @override
  Future<Result<Shift>> create({
    required String detachmentId,
    required DateTime date,
    required String centerName,
    required int startMinutes,
    required int endMinutes,
    required int needed,
    List<DateTime> repeatOn = const [],
  }) =>
      _api.send(
        'POST',
        '${_det(detachmentId)}/shifts',
        body: {
          'date': _day(date),
          'centerName': centerName,
          'startMinutes': startMinutes,
          'endMinutes': endMinutes,
          'needed': needed,
          if (repeatOn.isNotEmpty) 'repeatOn': [for (final d in repeatOn) _day(d)],
        },
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: _shift,
      );

  @override
  Future<Result<ShiftTemplate>> updateRepeat(
    String shiftId,
    List<DateTime> dates,
  ) =>
      _api.send(
        'PUT',
        '${_one(shiftId)}/repeat',
        body: {
          'dates': [for (final d in dates) _day(d)],
        },
        parse: (json) => _template((json as Map<String, dynamic>)['template']),
      );

  @override
  Future<Result<ShiftTemplate>> updateTemplateDates(
    String templateId,
    List<DateTime> dates,
  ) =>
      _api.send(
        'PUT',
        '${_tpl(templateId)}/dates',
        body: {
          'dates': [for (final d in dates) _day(d)],
        },
        parse: (json) => _template((json as Map<String, dynamic>)['template']),
      );

  @override
  Future<Result<List<Shift>>> shiftsForTemplate(String templateId) =>
      _api.send('GET', '${_tpl(templateId)}/shifts', parse: _shifts);

  @override
  Future<Result<Shift>> update(Shift shift) => _api.send(
        'PUT',
        _one(shift.id),
        body: {
          'date': _day(shift.date),
          'centerName': shift.centerName,
          'startMinutes': shift.startMinutes,
          'endMinutes': shift.endMinutes,
          'needed': shift.needed,
        },
        parse: _shift,
      );

  @override
  Future<Result<void>> delete(String id) =>
      _api.send('DELETE', _one(id), parse: (_) {});

  @override
  Future<Result<Shift>> assignVolunteer(String shiftId, String memberId) =>
      _api.send(
        'POST',
        '${_one(shiftId)}/assignments',
        body: {'memberId': memberId},
        parse: _shift,
      );

  @override
  Future<Result<Shift>> unassignVolunteer(String shiftId, String memberId) =>
      _api.send(
        'DELETE',
        '${_one(shiftId)}/assignments/${Uri.encodeComponent(memberId)}',
        parse: _shift,
      );

  @override
  Future<Result<Shift>> markAttendance(
    String shiftId,
    String memberId,
    AttendanceState state,
  ) =>
      _api.send(
        'PATCH',
        '${_member(shiftId, memberId)}/attendance',
        body: {'attendance': state.name},
        parse: _shift,
      );

  @override
  Future<Result<Shift>> recordCheckIn(
    String shiftId,
    String memberId,
    DateTime at,
  ) =>
      _api.send(
        'POST',
        '${_member(shiftId, memberId)}/check-in',
        body: {'at': _instant(at)},
        parse: _shift,
      );

  @override
  Future<Result<Shift>> recordCheckOut(
    String shiftId,
    String memberId,
    DateTime at,
  ) =>
      _api.send(
        'POST',
        '${_member(shiftId, memberId)}/check-out',
        body: {'at': _instant(at)},
        parse: _shift,
      );

  @override
  Future<Result<Shift>> markAbsent(String shiftId, String memberId) =>
      _api.send('POST', '${_member(shiftId, memberId)}/absent', parse: _shift);

  @override
  Future<Result<Shift>> resetAttendance(String shiftId, String memberId) =>
      _api.send('POST', '${_member(shiftId, memberId)}/reset', parse: _shift);

  /// The author is the calling account on the server; [correctedAt] travels
  /// as the advisory `clientCorrectedAt`, the server stamps its own time.
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
  }) =>
      _api.send(
        'POST',
        '${_member(shiftId, memberId)}/attendance-corrections',
        body: {
          'status': status.name,
          'checkInAt': checkInAt == null ? null : _instant(checkInAt),
          'checkOutAt': checkOutAt == null ? null : _instant(checkOutAt),
          'reason': reason,
          'correctedAt': _instant(correctedAt),
        },
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: _shift,
      );

  @override
  Future<Result<List<ShiftCandidate>>> candidatesFor(String shiftId) =>
      _api.send(
        'GET',
        '${_one(shiftId)}/candidates',
        parse: (json) => [
          for (final row in json as List) _candidate(row as Map<String, dynamic>),
        ],
      );

  /// `busyWith` is a short reference on the wire (shift id, centre, day and
  /// minutes) — enough for the sheet's "busy with" line.
  static ShiftCandidate _candidate(Map<String, dynamic> j) {
    final busyWith = j['busyWith'];
    return ShiftCandidate(
      member: TeamMember.fromJson(j['member'] as Map<String, dynamic>),
      busy: (j['busy'] as bool?) ?? false,
      busyWith: busyWith is Map<String, dynamic>
          ? Shift(
              id: busyWith['shiftId'] as String,
              detachmentId: busyWith['detachmentId'] as String,
              date: DateTime.parse(busyWith['date'] as String),
              centerName: (busyWith['centerName'] as String?) ?? '',
              startMinutes: busyWith['startMinutes'] as int,
              endMinutes: busyWith['endMinutes'] as int,
              needed: 0,
              attendees: const [],
            )
          : null,
    );
  }

  @override
  Future<Result<int>> quickFill(String shiftId) => _api.send(
        'POST',
        '${_one(shiftId)}/quick-fill',
        parse: (json) => (json as Map<String, dynamic>)['added'] as int,
      );

  @override
  Future<Result<List<ShiftTemplate>>> templates(String detachmentId) =>
      _api.send(
        'GET',
        '${_det(detachmentId)}/shift-templates',
        query: const {'active': 'true'},
        parse: (json) => [for (final row in json as List) _template(row)],
      );

  @override
  Future<Result<void>> stopTemplate(String templateId) =>
      _api.send('POST', '${_tpl(templateId)}/stop', parse: (_) {});

  @override
  Future<Result<int>> copyDay({
    required String detachmentId,
    required DateTime fromDay,
    required DateTime toDay,
  }) =>
      _api.send(
        'POST',
        '${_det(detachmentId)}/shifts/copy-day',
        body: {'fromDay': _day(fromDay), 'toDay': _day(toDay)},
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: (json) => (json as Map<String, dynamic>)['created'] as int,
      );

  @override
  Future<Result<int>> copyWeek({
    required String detachmentId,
    required DateTime fromWeekStart,
    required DateTime toWeekStart,
  }) =>
      _api.send(
        'POST',
        '${_det(detachmentId)}/shifts/copy-week',
        body: {
          'fromWeekStart': _day(fromWeekStart),
          'toWeekStart': _day(toWeekStart),
        },
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: (json) => (json as Map<String, dynamic>)['created'] as int,
      );
}
