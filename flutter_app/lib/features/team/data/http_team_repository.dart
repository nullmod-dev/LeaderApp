import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/team_models.dart';
import '../domain/team_repository.dart';

/// `/detachments/:id/members` and `/members/**` (`docs/api/members.md`).
/// Every capability is checked by the server in the member's detachment.
class HttpTeamRepository implements TeamRepository {
  HttpTeamRepository(this._api);

  final ApiClient _api;

  static TeamMember _one(Object? json) =>
      TeamMember.fromJson(json as Map<String, dynamic>);

  static String _path(String id) => '/members/${Uri.encodeComponent(id)}';

  @override
  Future<Result<List<TeamMember>>> listForDetachment(String detachmentId) =>
      _api.send(
        'GET',
        '/detachments/${Uri.encodeComponent(detachmentId)}/members',
        parse: (json) => [for (final row in json as List) _one(row)],
      );

  @override
  Future<Result<TeamMember?>> findNameMatch(
    String detachmentId,
    String candidateName,
  ) =>
      _api.send(
        'GET',
        '/members/match',
        query: {'detachmentId': detachmentId, 'name': candidateName},
        parse: (json) {
          final match = (json as Map<String, dynamic>)['match'];
          return match == null ? null : _one(match);
        },
      );

  @override
  Future<Result<TeamMember>> byId(String memberId) =>
      _api.send('GET', _path(memberId), parse: _one);

  @override
  Future<Result<TeamMember>> create({
    required String detachmentId,
    required String name,
    required String department,
    required String personalNumber,
    required TeamRole role,
  }) =>
      _api.send(
        'POST',
        '/members',
        body: {
          'detachmentId': detachmentId,
          'name': name,
          'department': department,
          'personalNumber': personalNumber,
          'role': role.name,
        },
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: _one,
      );

  @override
  Future<Result<TeamMember>> createFromShift({
    required String detachmentId,
    required String name,
  }) =>
      _api.send(
        'POST',
        '/members/from-shift',
        body: {'detachmentId': detachmentId, 'name': name},
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: _one,
      );

  /// `PUT` = the form's editable fields. `phone` is never sent, so the stored
  /// number survives (the roster only ever holds `phoneMasked`).
  @override
  Future<Result<TeamMember>> update(TeamMember member) => _api.send(
        'PUT',
        _path(member.id),
        body: {
          'id': member.id,
          'name': member.name,
          'department': member.department,
          'personalNumber': member.personalNumber,
          'role': member.role.name,
        },
        parse: _one,
      );

  @override
  Future<Result<void>> delete(String memberId) =>
      _api.send('DELETE', _path(memberId), parse: (_) {});

  @override
  Future<Result<TeamMember>> assignRole(String memberId, TeamRole role) =>
      _api.send(
        'PATCH',
        '${_path(memberId)}/role',
        body: {'role': role.name},
        parse: _one,
      );

  @override
  Future<Result<TeamMember>> setAttendance(
    String memberId,
    AttendanceState state,
  ) =>
      _api.send(
        'PATCH',
        '${_path(memberId)}/attendance',
        body: {'attendance': state.name},
        parse: _one,
      );
}
