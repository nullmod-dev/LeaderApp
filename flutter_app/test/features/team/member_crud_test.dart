import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/team/data/mock_team_repository.dart';
import 'package:mtm/features/team/domain/team_models.dart';

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
  const detachment = 'd_dam_central';

  test('a new member joins their detachment roster and nobody else\'s',
      () async {
    final repo = MockTeamRepository();
    final before =
        ok<List<TeamMember>>(await repo.listForDetachment(detachment)).length;

    final created = ok<TeamMember>(await repo.create(
      detachmentId: detachment,
      name: 'سلام الحموي',
      department: 'الإسعاف',
      personalNumber: '150',
      role: TeamRole.administrator,
    ));

    expect(created.detachmentId, detachment);
    expect(created.department, 'الإسعاف');
    expect(created.personalNumber, '150');
    // Nobody has taken attendance for someone who just joined.
    expect(created.attendance, AttendanceState.notCheckedIn);

    final after =
        ok<List<TeamMember>>(await repo.listForDetachment(detachment));
    expect(after.length, before + 1);

    final other = ok<List<TeamMember>>(await repo.listForDetachment('d_homs'));
    expect(other.any((m) => m.id == created.id), isFalse);
  });

  test('the monogram is derived from the name, and follows a rename', () async {
    final repo = MockTeamRepository();
    final created = ok<TeamMember>(await repo.create(
      detachmentId: detachment,
      name: 'سلام الحموي',
      department: 'الإسعاف',
      personalNumber: '151',
      role: TeamRole.administrator,
    ));
    expect(created.initials, 'سا');

    // Two distinct first letters, so the assertion proves the second word's
    // initial is really recomputed rather than carried over from 'سلام'.
    final renamed =
        ok<TeamMember>(await repo.update(created.copyWith(name: 'ريم قاسم')));
    expect(renamed.initials, 'رق');
  });

  test('a personal number cannot be taken twice inside one detachment',
      () async {
    final repo = MockTeamRepository();
    // 101 belongs to أحمد كنعان in the seeded d_dam_central roster.
    final clash = await repo.create(
      detachmentId: detachment,
      name: 'اسم آخر',
      department: 'الإسعاف',
      personalNumber: '101',
      role: TeamRole.member,
    );
    expect(failureCode(clash), 'number_taken');

    // The same number in a different detachment is fine — it identifies a
    // member inside their own roster, not across the organisation.
    final elsewhere = await repo.create(
      detachmentId: 'd_homs',
      name: 'اسم آخر',
      department: 'الإسعاف',
      personalNumber: '101',
      role: TeamRole.member,
    );
    expect(failureCode(elsewhere), isNull);
  });

  test('an edit may keep its own number but not take someone else\'s',
      () async {
    final repo = MockTeamRepository();
    final m1 = ok<TeamMember>(await repo.byId('m1'));

    // Keeping its own number is not a clash with itself.
    final samePerson = await repo.update(m1.copyWith(name: 'أحمد كنعان'));
    expect(failureCode(samePerson), isNull);

    // 102 belongs to ليلى ياسين in the same detachment.
    final steal = await repo.update(m1.copyWith(personalNumber: '102'));
    expect(failureCode(steal), 'number_taken');
  });

  test('deleting removes the member and frees their number', () async {
    final repo = MockTeamRepository();
    ok<void>(await repo.delete('m1'));

    expect(failureCode(await repo.byId('m1')), 'not_found');

    final roster =
        ok<List<TeamMember>>(await repo.listForDetachment(detachment));
    expect(roster.any((m) => m.id == 'm1'), isFalse);

    // 101 was m1's; with m1 gone it can be issued again.
    final reused = await repo.create(
      detachmentId: detachment,
      name: 'عضو جديد',
      department: 'الإسعاف',
      personalNumber: '101',
      role: TeamRole.member,
    );
    expect(failureCode(reused), isNull);
  });
}
