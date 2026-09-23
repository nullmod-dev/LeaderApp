import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/team/data/mock_team_repository.dart';
import 'package:mtm/features/team/domain/team_models.dart';
import 'package:mtm/features/workshop/data/mock_workshop_repository.dart';
import 'package:mtm/features/workshop/domain/workshop_models.dart';
import 'package:mtm/features/workshop/domain/workshop_stats.dart';

/// Unwrap a Result, failing the test on anything but success.
T ok<T>(dynamic result) => (result as dynamic).when(
      success: (T data, {bool stale = false}) => data,
      failure: (String m, String? c) => fail('expected success, got: $m'),
      offline: (T? cached) => fail('expected success, got offline'),
    ) as T;

String? failureCode(dynamic result) => (result as dynamic).when(
      success: (_, {bool stale = false}) => null,
      failure: (String m, String? c) => c,
      offline: (_) => null,
    ) as String?;

void main() {
  const workshop = 'w1'; // 20 seats, 6 on the register, m2 + m8 organising
  const full = 'w4'; // 3 seats, 3 on the register

  late MockTeamRepository team;
  late MockWorkshopRepository repo;

  setUp(() {
    team = MockTeamRepository();
    repo = MockWorkshopRepository(team: team);
  });

  Future<List<WorkshopParticipant>> register(String id) async =>
      ok<List<WorkshopParticipant>>(await repo.participants(id));

  group('the register', () {
    test('a roster member joins by id, and the seat counts follow', () async {
      final before = await register(workshop);
      final added = ok<List<WorkshopParticipant>>(
        await repo.addMemberParticipants(workshop, ['m9']),
      );

      expect(added.single.memberId, 'm9');
      expect(added.single.kind, ParticipantKind.member);
      expect(added.single.name, 'علي منصور');
      // Nobody has taken attendance for somebody who has just registered.
      expect(added.single.attendance, AttendanceState.notCheckedIn);
      expect(added.single.paymentStatus, isNull);

      final after = await register(workshop);
      expect(after.length, before.length + 1);

      // The record's own counts are the register's, not a hand-kept number.
      final w = ok<Workshop>(await repo.byId(workshop));
      expect(w.registered, after.length);
      expect(
          w.guests, after.where((p) => p.kind == ParticipantKind.guest).length);
    });

    test('the same member cannot be registered twice', () async {
      // m1 is already on w1's register.
      expect(failureCode(await repo.addMemberParticipants(workshop, ['m1'])),
          'duplicate');
      // Nor twice in one request.
      ok<List<WorkshopParticipant>>(
          await repo.addMemberParticipants(workshop, ['m9', 'm9']));
      final after = await register(workshop);
      expect(after.where((p) => p.memberId == 'm9').length, 1);
    });

    test('somebody organising the workshop cannot also attend it', () async {
      expect(failureCode(await repo.addMemberParticipants(workshop, ['m2'])),
          'already_organizer');
      expect(failureCode(await repo.addOrganizers(workshop, ['m1'])),
          'already_participant');
    });

    test('a member who is not on the roster is refused', () async {
      expect(
        failureCode(await repo.addMemberParticipants(workshop, ['m_ghost'])),
        'not_found',
      );
    });

    test('the register never exceeds the seats, and refuses as a whole',
        () async {
      expect(failureCode(await repo.addMemberParticipants(full, ['m9'])),
          'workshop_full');

      // 15 free seats on w1: 16 people is refused, and nobody is added.
      final before = await register(workshop);
      final tooMany = [for (var i = 1; i <= 16; i++) 'm$i'];
      expect(failureCode(await repo.addMemberParticipants(workshop, tooMany)),
          anyOf('workshop_full', 'duplicate', 'already_organizer'));
      expect((await register(workshop)).length, before.length);
    });

    test('a guest joins by name and cannot be entered twice', () async {
      final guest = ok<WorkshopParticipant>(
          await repo.addGuestParticipant(workshop, '  زائر   تجريبي '));
      expect(guest.kind, ParticipantKind.guest);
      expect(guest.memberId, isNull);
      expect(guest.name, 'زائر تجريبي');
      expect(
        failureCode(await repo.addGuestParticipant(workshop, 'زائر تجريبي')),
        'duplicate',
      );
      expect(failureCode(await repo.addGuestParticipant(workshop, '   ')),
          'validation');
    });

    test('removing somebody from a workshop never deletes the team member',
        () async {
      final line =
          (await register(workshop)).firstWhere((p) => p.memberId == 'm1');
      ok<void>(await repo.removeParticipant(line.id));

      expect((await register(workshop)).any((p) => p.id == line.id), isFalse);
      // The person is still on the roster, unchanged.
      final member = ok<TeamMember>(await team.byId('m1'));
      expect(member.name, 'أحمد كنعان');
      expect(member.detachmentId, 'd_dam_central');

      // And they can be registered again afterwards.
      ok<List<WorkshopParticipant>>(
          await repo.addMemberParticipants(workshop, ['m1']));
    });

    test('attendance and payment are recorded per register line', () async {
      final line = (await register(workshop)).first;
      final present = ok<WorkshopParticipant>(await repo
          .setParticipantAttendance(line.id, AttendanceState.checkedIn));
      expect(present.attendance, AttendanceState.checkedIn);

      final unpaid = ok<WorkshopParticipant>(
          await repo.setParticipantPayment(line.id, PaymentStatus.unpaid));
      expect(unpaid.paymentStatus, PaymentStatus.unpaid);

      // "Not recorded" is a state of its own, and reachable again.
      final cleared = ok<WorkshopParticipant>(
          await repo.setParticipantPayment(line.id, null));
      expect(cleared.paymentStatus, isNull);
    });
  });

  group('the organising team', () {
    test('a member joins and leaves without touching the roster', () async {
      final added = ok<Workshop>(await repo.addOrganizers(workshop, ['m9']));
      expect(added.organizingTeam.map((m) => m.id), contains('m9'));
      // Their attendance belongs to this workshop, and starts unrecorded.
      expect(
          added.organizingTeam.last.attendance, AttendanceState.notCheckedIn);

      expect(
          failureCode(await repo.addOrganizers(workshop, ['m9'])), 'duplicate');

      final present = ok<Workshop>(await repo.setOrganizerAttendance(
          workshop, 'm9', AttendanceState.checkedIn));
      expect(
        present.organizingTeam.firstWhere((m) => m.id == 'm9').attendance,
        AttendanceState.checkedIn,
      );

      final removed = ok<Workshop>(await repo.removeOrganizer(workshop, 'm9'));
      expect(removed.organizingTeam.map((m) => m.id), isNot(contains('m9')));
      expect(ok<TeamMember>(await team.byId('m9')).name, 'علي منصور');
    });
  });

  group('create, edit and archive', () {
    test('a created workshop opens empty, scheduled and in the list', () async {
      final created = ok<Workshop>(await repo.create(
        name: '  إسعاف الأطفال  ',
        at: DateTime.now().add(const Duration(days: 3)),
        location: 'قاعة التدريب',
        capacity: 12,
        registrationFee: 5000,
      ));
      expect(created.name, 'إسعاف الأطفال');
      expect(created.status, WorkshopStatus.scheduled);
      expect(created.registered, 0);
      expect(created.archived, isFalse);
      expect(created.registrationFee, 5000);

      final list = ok<List<Workshop>>(await repo.list());
      expect(list.any((w) => w.id == created.id), isTrue);
      expect(
          failureCode(await repo.create(
            name: 'x',
            at: DateTime.now(),
            location: 'y',
            capacity: 0,
          )),
          'validation');
    });

    test('an edit saves the editable fields and leaves the register alone',
        () async {
      final before = ok<Workshop>(await repo.byId(workshop));
      final saved = ok<Workshop>(await repo.update(before.copyWith(
        name: 'اسم جديد',
        location: 'مكان جديد',
        status: WorkshopStatus.ongoing,
        registrationFee: 1000,
        // A stale form cannot wipe the organising team.
        organizingTeam: const [],
      )));

      expect(saved.name, 'اسم جديد');
      expect(saved.status, WorkshopStatus.ongoing);
      expect(saved.registrationFee, 1000);
      expect(saved.organizingTeam.length, before.organizingTeam.length);
      expect(saved.registered, before.registered);

      final reread = ok<Workshop>(await repo.byId(workshop));
      expect(reread.name, 'اسم جديد');
    });

    test('capacity cannot drop below the people already registered', () async {
      final w = ok<Workshop>(await repo.byId(workshop));
      expect(failureCode(await repo.update(w.copyWith(capacity: 2))),
          'capacity_below_registered');
    });

    test('an archived workshop is readable and closed to every change',
        () async {
      ok<Workshop>(await repo.setArchived(workshop, archived: true));
      final archived = ok<Workshop>(await repo.byId(workshop));
      expect(archived.archived, isTrue);
      expect(archived.registered, greaterThan(0));

      expect(failureCode(await repo.update(archived.copyWith(name: 'x'))),
          'archived');
      expect(failureCode(await repo.addMemberParticipants(workshop, ['m9'])),
          'archived');
      expect(failureCode(await repo.addGuestParticipant(workshop, 'ضيف')),
          'archived');
      expect(
          failureCode(await repo.addOrganizers(workshop, ['m9'])), 'archived');
      final line = (await register(workshop)).first;
      expect(failureCode(await repo.removeParticipant(line.id)), 'archived');
      expect(
        failureCode(await repo.setParticipantAttendance(
            line.id, AttendanceState.absent)),
        'archived',
      );

      ok<Workshop>(await repo.setArchived(workshop, archived: false));
      ok<List<WorkshopParticipant>>(
          await repo.addMemberParticipants(workshop, ['m9']));
    });
  });

  group('statistics', () {
    test('read the register as it is now, not a stored figure', () async {
      final before = WorkshopStats.of(
        ok<Workshop>(await repo.byId(workshop)),
        await register(workshop),
      );
      ok<List<WorkshopParticipant>>(
          await repo.addMemberParticipants(workshop, ['m9']));
      final line =
          (await register(workshop)).firstWhere((p) => p.memberId == 'm9');
      ok<WorkshopParticipant>(await repo.setParticipantAttendance(
          line.id, AttendanceState.checkedIn));
      ok<WorkshopParticipant>(
          await repo.setParticipantPayment(line.id, PaymentStatus.paid));

      final after = WorkshopStats.of(
        ok<Workshop>(await repo.byId(workshop)),
        await register(workshop),
      );
      expect(after.registeredCount, before.registeredCount + 1);
      expect(
          after.participantStats.present, before.participantStats.present + 1);
      expect(after.participantStats.paid, before.participantStats.paid + 1);
      expect(after.capacityPercent,
          ((after.registeredCount / after.capacity) * 100).round());
    });

    test('an organiser added later is counted as staffing, never as a seat',
        () async {
      ok<Workshop>(await repo.addOrganizers(workshop, ['m9']));
      final stats = WorkshopStats.of(
        ok<Workshop>(await repo.byId(workshop)),
        await register(workshop),
      );
      expect(stats.teamMembers.any((p) => p.name == 'علي منصور'), isTrue);
      expect(stats.participants.any((p) => p.name == 'علي منصور'), isFalse);
      // The team runs the workshop; it does not buy a seat at it.
      expect(stats.teamStats.paid, 0);
    });
  });
}
