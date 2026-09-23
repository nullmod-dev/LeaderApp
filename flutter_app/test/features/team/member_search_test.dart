import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/team/domain/member_search.dart';
import 'package:mtm/features/team/domain/team_models.dart';

/// Roster search. The failure mode this guards against is a silent one: a
/// member who is genuinely on the roster not being found because the searcher
/// typed أحمد as احمد, and the screen then honestly reporting "no results".

TeamMember _member(
  String id,
  String name, {
  String department = 'الإسعاف',
  String number = '100',
  TeamRole role = TeamRole.member,
}) =>
    TeamMember(
      id: id,
      name: name,
      initials: TeamMember.initialsOf(name),
      department: department,
      personalNumber: number,
      role: role,
      detachmentId: 'd1',
      attendance: AttendanceState.notCheckedIn,
    );

final _roster = [
  _member('m1', 'أحمد كنعان', role: TeamRole.shiftSupervisor, number: '101'),
  _member('m2', 'ليلى ياسين', role: TeamRole.administrator, number: '102'),
  _member('m3', 'نور الحسن',
      department: 'الإسناد اللوجستي', number: '103', role: TeamRole.member),
  _member('m4', 'رنا سعيد',
      department: 'التدريب', number: '104', role: TeamRole.followUp),
];

void main() {
  group('search key folding', () {
    test('alef, ya, ta-marbuta and hamza variants fold together', () {
      expect(memberSearchKey('أحمد'), memberSearchKey('احمد'));
      expect(memberSearchKey('إسراء'), memberSearchKey('اسراء'));
      expect(memberSearchKey('ليلى'), memberSearchKey('ليلي'));
      expect(memberSearchKey('فاطمة'), memberSearchKey('فاطمه'));
    });

    test('diacritics and tatweel are decoration, not identity', () {
      expect(memberSearchKey('مُحَمَّـد'), memberSearchKey('محمد'));
    });

    test('Arabic-Indic digits match their ASCII form', () {
      expect(memberSearchKey('١٠٧'), '107');
    });

    test('whitespace is collapsed the way the roster stores it', () {
      expect(memberSearchKey('  أحمد   كنعان '), 'احمد كنعان');
    });

    test('identity matching stays strict — folding belongs to search only', () {
      // `memberNameKey` decides whether two records are the same person, so it
      // must not fold أ into ا: doing that there would merge two real people.
      expect(memberNameKey('أحمد'), isNot(memberNameKey('احمد')));
    });
  });

  group('filtering', () {
    test('a partial, unvocalised query still finds the member', () {
      final found = filterMembers(_roster, query: 'احمد');
      expect(found.map((m) => m.id), ['m1']);
    });

    test('a personal number typed either way finds its member', () {
      expect(filterMembers(_roster, query: '103').map((m) => m.id), ['m3']);
      expect(filterMembers(_roster, query: '١٠٣').map((m) => m.id), ['m3']);
    });

    test('a section name is searchable too', () {
      expect(
        filterMembers(_roster, query: 'التدريب').map((m) => m.id),
        ['m4'],
      );
    });

    test('an empty query and empty facets return the roster unchanged', () {
      expect(filterMembers(_roster).length, _roster.length);
      expect(filterMembers(_roster).map((m) => m.id), _roster.map((m) => m.id),
          reason: 'roster order is meaningful; search is not a ranking');
    });

    test('role and section narrow together, and a query narrows further', () {
      expect(
        filterMembers(_roster, roles: {TeamRole.member}).map((m) => m.id),
        ['m3'],
      );
      expect(
        filterMembers(_roster, departments: {'الإسعاف'}).map((m) => m.id),
        ['m1', 'm2'],
      );
      expect(
        filterMembers(
          _roster,
          query: 'ليلى',
          departments: {'الإسعاف'},
        ).map((m) => m.id),
        ['m2'],
      );
    });

    test('a query that matches nobody returns empty rather than everybody', () {
      expect(filterMembers(_roster, query: 'زياد'), isEmpty);
    });

    test('facets offered come from the roster, never from a fixed list', () {
      expect(departmentsOf(_roster), [
        'الإسعاف',
        'الإسناد اللوجستي',
        'التدريب',
      ]);
      expect(rolesOf(_roster), [
        TeamRole.shiftSupervisor,
        TeamRole.administrator,
        TeamRole.followUp,
        TeamRole.member,
      ]);
      // A roster with no sections offers no section filter at all.
      expect(departmentsOf([_member('x', 'اسم', department: '')]), isEmpty);
    });
  });
}
