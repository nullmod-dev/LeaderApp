import 'dart:math';

import '../../../core/result/result.dart';
import '../domain/team_models.dart';
import '../domain/team_repository.dart';

/// In-memory roster. Every detachment seeded in `MockDetachmentRepository`
/// has members here, the archived one included — its roster is what the
/// archive's Team tab reads back.
///
/// **This is the current roster, not a snapshot.** There is no per-detachment
/// membership history in this domain: `listForDetachment` answers with who is
/// on the roster now, and a member removed from an archived detachment simply
/// stops appearing in its history. The archive's Team tab says so on screen
/// rather than implying a snapshot it does not have.
///
/// The list is mutable and survives for the life of the process, so an add,
/// an edit, and a delete all persist across navigation the way they will
/// against the real backend.
class MockTeamRepository implements TeamRepository {
  /// [members] replaces the seeded roster — the Customer Demo workspace
  /// passes its own, and a test can pass an empty one.
  MockTeamRepository({List<TeamMember>? members})
      : _members = List.of(members ?? _defaultMembers());

  final _rand = Random(21);

  /// Feeds the ids of members created at runtime. Seeded past the highest
  /// seeded id so a new member can never collide with one below.
  int _nextId = 30;

  final List<TeamMember> _members;

  static List<TeamMember> _defaultMembers() => [
    // ---- d_dam_central (10) ----
    TeamMember(
        id: 'm1',
        name: 'أحمد كنعان',
        initials: TeamMember.initialsOf('أحمد كنعان'),
        department: 'الإسعاف',
        personalNumber: '101',
        role: TeamRole.shiftSupervisor,
        detachmentId: 'd_dam_central',
        attendance: AttendanceState.checkedIn,
        phoneMasked: '+963 9xx xx xx 12'),
    TeamMember(
        id: 'm2',
        name: 'ليلى ياسين',
        initials: TeamMember.initialsOf('ليلى ياسين'),
        department: 'الإسعاف',
        personalNumber: '102',
        role: TeamRole.administrator,
        detachmentId: 'd_dam_central',
        attendance: AttendanceState.checkedIn,
        phoneMasked: '+963 9xx xx xx 44'),
    TeamMember(
        id: 'm3',
        name: 'سامي درويش',
        initials: TeamMember.initialsOf('سامي درويش'),
        department: 'الإسعاف',
        personalNumber: '103',
        role: TeamRole.administrator,
        detachmentId: 'd_dam_central',
        attendance: AttendanceState.checkedIn,
        phoneMasked: '+963 9xx xx xx 08'),
    TeamMember(
        id: 'm4',
        name: 'نور الحسن',
        initials: TeamMember.initialsOf('نور الحسن'),
        department: 'الإسناد اللوجستي',
        personalNumber: '104',
        role: TeamRole.member,
        detachmentId: 'd_dam_central',
        attendance: AttendanceState.checkedIn),
    TeamMember(
        id: 'm5',
        name: 'ياسر البكري',
        initials: TeamMember.initialsOf('ياسر البكري'),
        department: 'الإسناد اللوجستي',
        personalNumber: '105',
        role: TeamRole.member,
        detachmentId: 'd_dam_central',
        attendance: AttendanceState.absent),
    TeamMember(
        id: 'm6',
        name: 'رنا سعيد',
        initials: TeamMember.initialsOf('رنا سعيد'),
        department: 'التدريب',
        personalNumber: '106',
        role: TeamRole.followUp,
        detachmentId: 'd_dam_central',
        attendance: AttendanceState.notCheckedIn),
    TeamMember(
        id: 'm7',
        name: 'طارق خالد',
        initials: TeamMember.initialsOf('طارق خالد'),
        department: 'الاتصالات',
        personalNumber: '107',
        role: TeamRole.member,
        detachmentId: 'd_dam_central',
        attendance: AttendanceState.checkedIn),
    TeamMember(
        id: 'm8',
        name: 'دانا عمر',
        initials: TeamMember.initialsOf('دانا عمر'),
        department: 'الإسعاف',
        personalNumber: '108',
        role: TeamRole.administrator,
        detachmentId: 'd_dam_central',
        attendance: AttendanceState.checkedIn,
        phoneMasked: '+963 9xx xx xx 71'),
    TeamMember(
        id: 'm9',
        name: 'علي منصور',
        initials: TeamMember.initialsOf('علي منصور'),
        department: 'الإسناد اللوجستي',
        personalNumber: '109',
        role: TeamRole.member,
        detachmentId: 'd_dam_central',
        attendance: AttendanceState.absent),
    TeamMember(
        id: 'm10',
        name: 'هند شحادة',
        initials: TeamMember.initialsOf('هند شحادة'),
        department: 'الاتصالات',
        personalNumber: '110',
        role: TeamRole.member,
        detachmentId: 'd_dam_central',
        attendance: AttendanceState.checkedIn),

    // ---- d_dam_rural (6) ----
    TeamMember(
        id: 'm11',
        name: 'ماجد صالح',
        initials: TeamMember.initialsOf('ماجد صالح'),
        department: 'الإسعاف',
        personalNumber: '201',
        role: TeamRole.shiftSupervisor,
        detachmentId: 'd_dam_rural',
        attendance: AttendanceState.checkedIn,
        phoneMasked: '+963 9xx xx xx 30'),
    TeamMember(
        id: 'm12',
        name: 'ريم قاسم',
        initials: TeamMember.initialsOf('ريم قاسم'),
        department: 'الإسعاف',
        personalNumber: '202',
        role: TeamRole.administrator,
        detachmentId: 'd_dam_rural',
        attendance: AttendanceState.checkedIn),
    TeamMember(
        id: 'm13',
        name: 'حسام عابد',
        initials: TeamMember.initialsOf('حسام عابد'),
        department: 'الإسناد اللوجستي',
        personalNumber: '203',
        role: TeamRole.member,
        detachmentId: 'd_dam_rural',
        attendance: AttendanceState.checkedIn),
    TeamMember(
        id: 'm16',
        name: 'سلمى نجّار',
        initials: TeamMember.initialsOf('سلمى نجّار'),
        department: 'الإسعاف',
        personalNumber: '204',
        role: TeamRole.administrator,
        detachmentId: 'd_dam_rural',
        attendance: AttendanceState.checkedIn),
    TeamMember(
        id: 'm17',
        name: 'بشار الأحمد',
        initials: TeamMember.initialsOf('بشار الأحمد'),
        department: 'التدريب',
        personalNumber: '205',
        role: TeamRole.followUp,
        detachmentId: 'd_dam_rural',
        attendance: AttendanceState.notCheckedIn),
    TeamMember(
        id: 'm18',
        name: 'لمى حجازي',
        initials: TeamMember.initialsOf('لمى حجازي'),
        department: 'الاتصالات',
        personalNumber: '206',
        role: TeamRole.member,
        detachmentId: 'd_dam_rural',
        attendance: AttendanceState.absent),

    // ---- d_homs (5) ----
    TeamMember(
        id: 'm14',
        name: 'أمين رياض',
        initials: TeamMember.initialsOf('أمين رياض'),
        department: 'الإسعاف',
        personalNumber: '301',
        role: TeamRole.shiftSupervisor,
        detachmentId: 'd_homs',
        attendance: AttendanceState.checkedIn,
        phoneMasked: '+963 9xx xx xx 55'),
    TeamMember(
        id: 'm19',
        name: 'غادة الحموي',
        initials: TeamMember.initialsOf('غادة الحموي'),
        department: 'الإسعاف',
        personalNumber: '302',
        role: TeamRole.administrator,
        detachmentId: 'd_homs',
        attendance: AttendanceState.checkedIn),
    TeamMember(
        id: 'm20',
        name: 'وسيم الديب',
        initials: TeamMember.initialsOf('وسيم الديب'),
        department: 'الإسناد اللوجستي',
        personalNumber: '303',
        role: TeamRole.member,
        detachmentId: 'd_homs',
        attendance: AttendanceState.checkedIn),
    TeamMember(
        id: 'm21',
        name: 'رغد الشامي',
        initials: TeamMember.initialsOf('رغد الشامي'),
        department: 'الاتصالات',
        personalNumber: '304',
        role: TeamRole.member,
        detachmentId: 'd_homs',
        attendance: AttendanceState.checkedIn),
    TeamMember(
        id: 'm22',
        name: 'فادي عزّام',
        initials: TeamMember.initialsOf('فادي عزّام'),
        department: 'التدريب',
        personalNumber: '305',
        role: TeamRole.followUp,
        detachmentId: 'd_homs',
        attendance: AttendanceState.notCheckedIn),

    // ---- d_coast (4) ----
    TeamMember(
        id: 'm15',
        name: 'كنان عيسى',
        initials: TeamMember.initialsOf('كنان عيسى'),
        department: 'الإسعاف',
        personalNumber: '401',
        role: TeamRole.shiftSupervisor,
        detachmentId: 'd_coast',
        attendance: AttendanceState.checkedIn,
        phoneMasked: '+963 9xx xx xx 63'),
    TeamMember(
        id: 'm23',
        name: 'ميساء بدر',
        initials: TeamMember.initialsOf('ميساء بدر'),
        department: 'الإسعاف',
        personalNumber: '402',
        role: TeamRole.administrator,
        detachmentId: 'd_coast',
        attendance: AttendanceState.checkedIn),
    TeamMember(
        id: 'm24',
        name: 'رامي سلوم',
        initials: TeamMember.initialsOf('رامي سلوم'),
        department: 'الإسناد اللوجستي',
        personalNumber: '403',
        role: TeamRole.member,
        detachmentId: 'd_coast',
        attendance: AttendanceState.absent),
    TeamMember(
        id: 'm25',
        name: 'جود الحلاق',
        initials: TeamMember.initialsOf('جود الحلاق'),
        department: 'الاتصالات',
        personalNumber: '404',
        role: TeamRole.member,
        detachmentId: 'd_coast',
        attendance: AttendanceState.checkedIn),

    // ---- d_north_arch (4) ----
    // The archived detachment carries a real roster on purpose: an archive
    // whose every tab is empty cannot be reviewed, and "what happened here"
    // is the question Point 13 exists to answer. Their attendance is left at
    // the state their last shift ended in — nothing about a finished
    // detachment is live.
    TeamMember(
        id: 'm26',
        name: 'خالد العمر',
        initials: TeamMember.initialsOf('خالد العمر'),
        department: 'الإسعاف',
        personalNumber: '501',
        role: TeamRole.shiftSupervisor,
        detachmentId: 'd_north_arch',
        attendance: AttendanceState.checkedOut,
        phoneMasked: '+963 9xx xx xx 71'),
    TeamMember(
        id: 'm27',
        name: 'سلمى الأحمد',
        initials: TeamMember.initialsOf('سلمى الأحمد'),
        department: 'الإسعاف',
        personalNumber: '502',
        role: TeamRole.administrator,
        detachmentId: 'd_north_arch',
        attendance: AttendanceState.checkedOut,
        phoneMasked: '+963 9xx xx xx 33'),
    TeamMember(
        id: 'm28',
        name: 'وسيم قدور',
        initials: TeamMember.initialsOf('وسيم قدور'),
        department: 'الإسناد اللوجستي',
        personalNumber: '503',
        role: TeamRole.member,
        detachmentId: 'd_north_arch',
        attendance: AttendanceState.absent),
    TeamMember(
        id: 'm29',
        name: 'هبة الشيخ',
        initials: TeamMember.initialsOf('هبة الشيخ'),
        department: 'الاتصالات',
        personalNumber: '504',
        role: TeamRole.member,
        detachmentId: 'd_north_arch',
        attendance: AttendanceState.checkedOut),
  ];

  Future<void> _latency() => Future<void>.delayed(
        Duration(milliseconds: 260 + _rand.nextInt(320)),
      );

  /// A member's number identifies them inside their own detachment, so it has
  /// to be unique there. [exceptId] lets an edit keep its own number.
  bool _numberTaken(String detachmentId, String number, {String? exceptId}) =>
      _members.any((m) =>
          m.detachmentId == detachmentId &&
          m.personalNumber == number &&
          m.id != exceptId);

  bool _nameTaken(String detachmentId, String name, {String? exceptId}) {
    final key = memberNameKey(name);
    return _members.any(
      (member) =>
          member.detachmentId == detachmentId &&
          memberNameKey(member.name) == key &&
          member.id != exceptId,
    );
  }

  @override
  Future<Result<List<TeamMember>>> listForDetachment(
      String detachmentId) async {
    await _latency();
    return Success(
      _members.where((m) => m.detachmentId == detachmentId).toList(),
    );
  }

  @override
  Future<Result<TeamMember?>> findNameMatch(
    String detachmentId,
    String candidateName,
  ) async {
    await _latency();
    final key = memberNameKey(candidateName);
    if (key.isEmpty) return const Success(null);
    for (final member in _members) {
      if (member.detachmentId == detachmentId &&
          memberNameKey(member.name) == key) {
        return Success(member);
      }
    }
    return const Success(null);
  }

  @override
  Future<Result<TeamMember>> byId(String memberId) async {
    await _latency();
    final i = _members.indexWhere((m) => m.id == memberId);
    if (i < 0) return const Failure('لم يُعثر على العضو.', code: 'not_found');
    return Success(_members[i]);
  }

  @override
  Future<Result<TeamMember>> create({
    required String detachmentId,
    required String name,
    required String department,
    required String personalNumber,
    required TeamRole role,
  }) async {
    await _latency();
    final normalizedName = normalizeMemberName(name);
    final normalizedDepartment = department.trim();
    final normalizedNumber = personalNumber.trim();
    if (_nameTaken(detachmentId, normalizedName)) {
      return const Failure(
        'يوجد عضو بهذا الاسم في المفرزة.',
        code: 'name_taken',
      );
    }
    if (_numberTaken(detachmentId, normalizedNumber)) {
      return const Failure(
        'هذا الرقم مستخدم لعضو آخر في المفرزة.',
        code: 'number_taken',
      );
    }
    final member = TeamMember(
      id: 'm${_nextId++}',
      name: normalizedName,
      initials: TeamMember.initialsOf(normalizedName),
      department: normalizedDepartment,
      personalNumber: normalizedNumber,
      role: role,
      detachmentId: detachmentId,
      // A member who has just been added has not been invited to anything
      // yet, so no attendance has been taken for them.
      attendance: AttendanceState.notCheckedIn,
    );
    _members.add(member);
    return Success(member);
  }

  @override
  Future<Result<TeamMember>> createFromShift({
    required String detachmentId,
    required String name,
  }) async {
    await _latency();
    final normalizedName = normalizeMemberName(name);
    if (_nameTaken(detachmentId, normalizedName)) {
      return const Failure(
        'يوجد عضو بهذا الاسم في المفرزة.',
        code: 'name_taken',
      );
    }
    final id = _nextId++;
    final member = TeamMember(
      id: 'm$id',
      name: normalizedName,
      initials: TeamMember.initialsOf(normalizedName),
      personalNumber: 'shift-$id',
      role: TeamRole.member,
      detachmentId: detachmentId,
      attendance: AttendanceState.notCheckedIn,
    );
    _members.add(member);
    return Success(member);
  }

  @override
  Future<Result<TeamMember>> update(TeamMember member) async {
    await _latency();
    final i = _members.indexWhere((m) => m.id == member.id);
    if (i < 0) return const Failure('لم يُعثر على العضو.', code: 'not_found');
    final normalized = member.copyWith(
      name: normalizeMemberName(member.name),
      department: member.department.trim(),
      personalNumber: member.personalNumber.trim(),
    );
    if (_nameTaken(normalized.detachmentId, normalized.name,
        exceptId: normalized.id)) {
      return const Failure(
        'يوجد عضو بهذا الاسم في المفرزة.',
        code: 'name_taken',
      );
    }
    if (_numberTaken(normalized.detachmentId, normalized.personalNumber,
        exceptId: normalized.id)) {
      return const Failure(
        'هذا الرقم مستخدم لعضو آخر في المفرزة.',
        code: 'number_taken',
      );
    }
    _members[i] = normalized;
    return Success(normalized);
  }

  @override
  Future<Result<void>> delete(String memberId) async {
    await _latency();
    final i = _members.indexWhere((m) => m.id == memberId);
    if (i < 0) return const Failure('لم يُعثر على العضو.', code: 'not_found');
    _members.removeAt(i);
    return const Success(null);
  }

  @override
  Future<Result<TeamMember>> assignRole(String memberId, TeamRole role) async {
    await _latency();
    final i = _members.indexWhere((m) => m.id == memberId);
    if (i < 0) return const Failure('لم يُعثر على العضو.', code: 'not_found');
    _members[i] = _members[i].copyWith(role: role);
    return Success(_members[i]);
  }

  @override
  Future<Result<TeamMember>> setAttendance(
      String memberId, AttendanceState state) async {
    await _latency();
    final i = _members.indexWhere((m) => m.id == memberId);
    if (i < 0) return const Failure('لم يُعثر على العضو.', code: 'not_found');
    _members[i] = _members[i].copyWith(attendance: state);
    return Success(_members[i]);
  }
}
