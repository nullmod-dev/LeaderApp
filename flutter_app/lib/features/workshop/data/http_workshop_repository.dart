import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../../team/domain/team_models.dart';
import '../domain/workshop_models.dart';
import '../domain/workshop_repository.dart';

/// `/workshops/**` and `/workshop-participants/**` (`docs/api/workshops.md`).
/// Seats, duplicates, organiser exclusivity and the archive lock are decided
/// by the server in one transaction.
class HttpWorkshopRepository implements WorkshopRepository {
  HttpWorkshopRepository(this._api);

  final ApiClient _api;

  static Workshop _workshop(Object? json) =>
      Workshop.fromJson(json as Map<String, dynamic>);

  static WorkshopParticipant _participant(Object? json) =>
      WorkshopParticipant.fromJson(json as Map<String, dynamic>);

  static String _one(String id) => '/workshops/${Uri.encodeComponent(id)}';
  static String _line(String id) =>
      '/workshop-participants/${Uri.encodeComponent(id)}';

  @override
  Future<Result<List<Workshop>>> list() => _api.send(
        'GET',
        '/workshops',
        parse: (json) => [for (final row in json as List) _workshop(row)],
      );

  @override
  Future<Result<Workshop>> byId(String id) =>
      _api.send('GET', _one(id), parse: _workshop);

  @override
  Future<Result<Workshop>> create({
    required String name,
    required DateTime at,
    required String location,
    required int capacity,
    double registrationFee = 0,
  }) =>
      _api.send(
        'POST',
        '/workshops',
        body: {
          'name': name,
          'at': at.toUtc().toIso8601String(),
          'location': location,
          'capacity': capacity,
          'registrationFee': registrationFee,
        },
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: _workshop,
      );

  /// Only the editable fields travel; the register counts, the organising
  /// team and the archive flag stay the server's.
  @override
  Future<Result<Workshop>> update(Workshop w) => _api.send(
        'PUT',
        _one(w.id),
        body: {
          'id': w.id,
          'name': w.name,
          'at': w.at.toUtc().toIso8601String(),
          'location': w.location,
          'capacity': w.capacity,
          'status': w.status.name,
          'registrationFee': w.registrationFee,
        },
        parse: _workshop,
      );

  @override
  Future<Result<Workshop>> setArchived(String id, {required bool archived}) =>
      _api.send(
        'PATCH',
        '${_one(id)}/archive',
        body: {'archived': archived},
        parse: _workshop,
      );

  @override
  Future<Result<List<WorkshopParticipant>>> participants(String workshopId) =>
      _api.send(
        'GET',
        '${_one(workshopId)}/participants',
        parse: (json) => [for (final row in json as List) _participant(row)],
      );

  @override
  Future<Result<List<WorkshopParticipant>>> addMemberParticipants(
    String workshopId,
    List<String> memberIds,
  ) =>
      _api.send(
        'POST',
        '${_one(workshopId)}/participants',
        body: {'memberIds': memberIds},
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: (json) => [for (final row in json as List) _participant(row)],
      );

  @override
  Future<Result<WorkshopParticipant>> addTeamMember(
    String workshopId, {
    required String name,
    required WorkshopRole role,
    required bool paid,
  }) =>
      _api.send(
        'POST',
        '${_one(workshopId)}/team-members',
        body: {'name': name, 'role': role.name, 'paid': paid},
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: _participant,
      );

  @override
  Future<Result<WorkshopParticipant>> updateTeamMember(
    String participantId, {
    required String name,
    required WorkshopRole role,
    required bool paid,
  }) =>
      _api.send(
        'PUT',
        _line(participantId),
        body: {'name': name, 'role': role.name, 'paid': paid},
        parse: _participant,
      );

  @override
  Future<Result<WorkshopParticipant>> addGuestParticipant(
    String workshopId,
    String name, {
    bool paid = false,
  }) =>
      _api.send(
        'POST',
        '${_one(workshopId)}/guests',
        body: {'name': name, 'paid': paid},
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: _participant,
      );

  @override
  Future<Result<void>> removeParticipant(String participantId) =>
      _api.send('DELETE', _line(participantId), parse: (_) {});

  @override
  Future<Result<WorkshopParticipant>> setParticipantAttendance(
    String participantId,
    AttendanceState state,
  ) =>
      _api.send(
        'PATCH',
        '${_line(participantId)}/attendance',
        body: {'attendance': state.name},
        parse: _participant,
      );

  @override
  Future<Result<WorkshopParticipant>> setParticipantPayment(
    String participantId,
    PaymentStatus? status,
  ) =>
      _api.send(
        'PATCH',
        '${_line(participantId)}/payment',
        body: {'paymentStatus': status?.name},
        parse: _participant,
      );

  @override
  Future<Result<Workshop>> addOrganizers(
    String workshopId,
    List<String> memberIds,
  ) =>
      _api.send(
        'POST',
        '${_one(workshopId)}/organizers',
        body: {'memberIds': memberIds},
        parse: _workshop,
      );

  @override
  Future<Result<Workshop>> removeOrganizer(String workshopId, String memberId) =>
      _api.send(
        'DELETE',
        '${_one(workshopId)}/organizers/${Uri.encodeComponent(memberId)}',
        parse: _workshop,
      );

  @override
  Future<Result<Workshop>> setOrganizerAttendance(
    String workshopId,
    String memberId,
    AttendanceState state,
  ) =>
      _api.send(
        'PATCH',
        '${_one(workshopId)}/organizers/${Uri.encodeComponent(memberId)}/attendance',
        body: {'attendance': state.name},
        parse: _workshop,
      );
}
