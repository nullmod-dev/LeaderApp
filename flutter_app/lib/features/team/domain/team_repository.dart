import '../../../core/result/result.dart';
import 'team_models.dart';

abstract class TeamRepository {
  Future<Result<List<TeamMember>>> listForDetachment(String detachmentId);

  /// Finds a normalized, case-insensitive name match inside one detachment.
  Future<Result<TeamMember?>> findNameMatch(
      String detachmentId, String candidateName);

  /// One member, for the edit form to seed itself from.
  Future<Result<TeamMember>> byId(String memberId);

  /// Adds a member to one detachment's roster. The caller passes only what
  /// the form collects; the id, the monogram, and the starting attendance are
  /// the repository's to assign.
  Future<Result<TeamMember>> create({
    required String detachmentId,
    required String name,
    required String department,
    required String personalNumber,
    required TeamRole role,
  });

  /// Creates a real roster member from the shift-assignment flow. The
  /// repository supplies the internal personal number and default role.
  Future<Result<TeamMember>> createFromShift({
    required String detachmentId,
    required String name,
  });

  /// Saves the editable fields of [member]: name, department, number, role.
  Future<Result<TeamMember>> update(TeamMember member);

  Future<Result<void>> delete(String memberId);

  Future<Result<TeamMember>> assignRole(String memberId, TeamRole role);
  Future<Result<TeamMember>> setAttendance(
      String memberId, AttendanceState state);
}
