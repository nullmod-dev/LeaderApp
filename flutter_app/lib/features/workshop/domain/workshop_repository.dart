import '../../../core/result/result.dart';
import '../../team/domain/team_models.dart';
import 'workshop_models.dart';

/// Workshops are organisation-level (`CAPABILITIES.md` §0, ruling B/Q2).
///
/// Every mutation is an online command: none is queued in the sync outbox,
/// and each one answers with the record as the repository now holds it. A
/// mutation on an archived workshop fails with code `archived`.
///
/// People on a workshop are **references** to the tenant's roster, resolved
/// by member id — never a second person model. Taking somebody off a
/// workshop never deletes them from the roster.
abstract class WorkshopRepository {
  Future<Result<List<Workshop>>> list();
  Future<Result<Workshop>> byId(String id);
  Future<Result<Workshop>> create({
    required String name,
    required DateTime at,
    required String location,
    required int capacity,
    double registrationFee = 0,
  });

  /// Saves the editable fields of [w] — name, date, location, capacity,
  /// status and fee. The register counts, the organising team and the
  /// archive flag are the repository's own and are never taken from [w].
  /// Fails with `capacity_below_registered` when [w] would seat fewer people
  /// than are already registered.
  Future<Result<Workshop>> update(Workshop w);

  /// Archives or restores a workshop (`workshop.archive`).
  Future<Result<Workshop>> setArchived(String id, {required bool archived});

  Future<Result<List<WorkshopParticipant>>> participants(String workshopId);

  /// Registers roster members by id. All or nothing: an unknown member
  /// (`not_found`), somebody already on the register (`duplicate`) or on the
  /// organising team (`already_organizer`), or more people than the free
  /// seats (`workshop_full`) rejects the whole request.
  Future<Result<List<WorkshopParticipant>>> addMemberParticipants(
    String workshopId,
    List<String> memberIds,
  );

  /// Registers somebody from outside the team by name. Fails with
  /// `duplicate` when a guest of the same name is already registered.
  Future<Result<WorkshopParticipant>> addGuestParticipant(
    String workshopId,
    String name,
  );

  /// Takes one line off the register. The roster is untouched.
  Future<Result<void>> removeParticipant(String participantId);

  Future<Result<WorkshopParticipant>> setParticipantAttendance(
      String participantId, AttendanceState state);

  /// Records paid / unpaid, or clears the record back to "not recorded" when
  /// [status] is `null` (`workshop.payment.record`).
  Future<Result<WorkshopParticipant>> setParticipantPayment(
      String participantId, PaymentStatus? status);

  /// Adds roster members to the organising team, by id. Same all-or-nothing
  /// rules as [addMemberParticipants], with `already_participant` for
  /// somebody already registered as a participant; no seat limit applies.
  Future<Result<Workshop>> addOrganizers(
    String workshopId,
    List<String> memberIds,
  );

  /// Takes one member off the organising team. The roster is untouched.
  Future<Result<Workshop>> removeOrganizer(String workshopId, String memberId);

  Future<Result<Workshop>> setOrganizerAttendance(
    String workshopId,
    String memberId,
    AttendanceState state,
  );
}
