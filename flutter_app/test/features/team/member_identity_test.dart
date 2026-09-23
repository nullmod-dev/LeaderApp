import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/team/data/mock_team_repository.dart';
import 'package:mtm/features/team/domain/team_models.dart';
import 'package:mtm/features/workshop/domain/workshop_models.dart';

T _success<T>(Result<T> result) => result.when(
      success: (data, {stale = false}) => data,
      failure: (message, code) => fail('$message ($code)'),
      offline: (_) => fail('offline'),
    );

String? _failureCode<T>(Result<T> result) => result.when(
      success: (_, {stale = false}) => null,
      failure: (_, code) => code,
      offline: (_) => 'offline',
    );

void main() {
  test('the roster exposes exactly the four approved roles', () {
    expect(
      TeamRole.values,
      [
        TeamRole.shiftSupervisor,
        TeamRole.administrator,
        TeamRole.followUp,
        TeamRole.member,
      ],
    );
  });

  test('old role and attendance wire values migrate safely', () {
    final member = TeamMember.fromJson({
      'id': 'legacy',
      'name': '  Legacy   Member ',
      'role': 'volunteer',
      'detachmentId': 'd',
      'attendance': 'present',
    });
    expect(member.name, 'Legacy Member');
    expect(member.role, TeamRole.member);
    expect(member.attendance, AttendanceState.checkedIn);
    expect(member.department, isEmpty);
    expect(member.personalNumber, isEmpty);
  });

  test('manual names are normalized and duplicates surface the existing id',
      () async {
    final repository = MockTeamRepository();
    final existing = _success(await repository.createFromShift(
      detachmentId: 'new_detachment',
      name: '  Rana   Smith  ',
    ));
    expect(existing.name, 'Rana Smith');

    final match = _success(await repository.findNameMatch(
      'new_detachment',
      ' rAnA    sMiTh ',
    ));
    expect(match?.id, existing.id);

    final duplicate = await repository.createFromShift(
      detachmentId: 'new_detachment',
      name: 'RANA SMITH',
    );
    expect(_failureCode(duplicate), 'name_taken');
    expect(
      _success(await repository.listForDetachment('new_detachment')),
      hasLength(1),
    );
  });

  test('every old attendance value still decodes, on both models', () {
    // There is no schema migration to run — the app is in-memory — so the
    // decoders are the whole backward-compatibility story. These are the
    // values written before the four-state model replaced them.
    const legacy = {
      'present': AttendanceState.checkedIn,
      'late': AttendanceState.checkedIn,
      'absent': AttendanceState.absent,
      'notInvited': AttendanceState.notCheckedIn,
    };
    legacy.forEach((wire, expected) {
      expect(attendanceStateFromWire(wire), expected, reason: wire);
      expect(
        WorkshopParticipant.fromJson({
          'id': 'p',
          'workshopId': 'w',
          'name': 'مشارك',
          'initials': 'م',
          'kind': 'member',
          'attendance': wire,
        }).attendance,
        expected,
        reason: 'workshop participant: $wire',
      );
    });

    // An unknown or missing value falls back rather than throwing.
    expect(
        attendanceStateFromWire('something-new'), AttendanceState.notCheckedIn);
    expect(
      WorkshopParticipant.fromJson({
        'id': 'p',
        'workshopId': 'w',
        'name': 'مشارك',
        'initials': 'م',
        'kind': 'member',
      }).attendance,
      AttendanceState.notCheckedIn,
    );

    // Old role names map onto the four approved roles.
    expect(teamRoleFromWire('lead'), TeamRole.shiftSupervisor);
    expect(teamRoleFromWire('medic'), TeamRole.administrator);
    expect(teamRoleFromWire('trainee'), TeamRole.followUp);
    expect(teamRoleFromWire('volunteer'), TeamRole.member);
    expect(teamRoleFromWire('anything-else'), TeamRole.member);
  });
}
