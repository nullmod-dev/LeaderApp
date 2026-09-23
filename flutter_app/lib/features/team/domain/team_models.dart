/// The only four roster roles supported by the application.
///
/// Older mock payloads used `lead`, `medic`, `trainee`, and `volunteer`.
/// [teamRoleFromWire] keeps those records readable while every new write uses
/// the names below.
enum TeamRole { shiftSupervisor, administrator, followUp, member }

/// A shift assignment's attendance state.
enum AttendanceState { notCheckedIn, checkedIn, checkedOut, absent }

/// Collapses leading, trailing, and repeated whitespace.
String normalizeMemberName(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

/// A comparison key for fast, whitespace-tolerant, case-insensitive search.
String memberNameKey(String value) => normalizeMemberName(value).toLowerCase();

TeamRole teamRoleFromWire(String value) => switch (value) {
      'shiftSupervisor' || 'lead' => TeamRole.shiftSupervisor,
      'administrator' || 'medic' => TeamRole.administrator,
      'followUp' || 'trainee' => TeamRole.followUp,
      'member' || 'volunteer' => TeamRole.member,
      _ => TeamRole.member,
    };

AttendanceState attendanceStateFromWire(String value) => switch (value) {
      'checkedIn' || 'present' || 'late' => AttendanceState.checkedIn,
      'checkedOut' => AttendanceState.checkedOut,
      'absent' => AttendanceState.absent,
      'notCheckedIn' || 'notInvited' => AttendanceState.notCheckedIn,
      _ => AttendanceState.notCheckedIn,
    };

class TeamMember {
  const TeamMember({
    required this.id,
    required this.name,
    required this.initials,
    this.department = '',
    this.personalNumber = '',
    required this.role,
    required this.detachmentId,
    required this.attendance,
    this.phoneMasked,
    this.checkInAt,
    this.checkOutAt,
  });

  final String id;
  final String name;

  /// Monogram shown on the roster avatar. Derived from [name] by
  /// [initialsOf] — never typed by hand, so it can never drift from the name
  /// after a rename.
  final String initials;

  /// The member's section inside the detachment ("الإسعاف", "اللوجستيات").
  /// Free text on purpose: the set of sections differs per detachment and no
  /// fixed list has been ruled on.
  ///
  /// Empty outside a detachment roster. `TeamMember` doubles as the
  /// projection of a person into a shift's attendee list and a workshop's
  /// organising team, and neither of those carries a roster record — see
  /// `MockShiftRepository` and `MockWorkshopRepository`. Only
  /// [TeamRepository.create] can mint a roster member, and it requires both
  /// this and [personalNumber].
  final String department;

  /// The number the member picks for themselves. Kept as a string so a
  /// leading zero survives, and unique inside one detachment — see
  /// `MockTeamRepository`. Empty in the same projections as [department].
  final String personalNumber;

  final TeamRole role;
  final String detachmentId;
  final AttendanceState attendance;
  final String? phoneMasked;

  /// These timestamps belong to this member's projection inside a shift.
  /// Roster records leave them null; the shift repository hydrates the member
  /// identity while preserving the assignment-specific values.
  final DateTime? checkInAt;
  final DateTime? checkOutAt;

  /// First letter of the first two words. Arabic has no case, so this is the
  /// whole rule; a single-word name yields one letter rather than a padded
  /// two.
  static String initialsOf(String name) {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).map((w) => String.fromCharCode(w.runes.first)).join();
  }

  TeamMember copyWith({
    String? name,
    String? department,
    String? personalNumber,
    TeamRole? role,
    AttendanceState? attendance,
    DateTime? checkInAt,
    DateTime? checkOutAt,
    bool clearCheckIn = false,
    bool clearCheckOut = false,
  }) =>
      TeamMember(
        id: id,
        name: name == null ? this.name : normalizeMemberName(name),
        initials: name == null ? initials : initialsOf(name),
        department: department ?? this.department,
        personalNumber: personalNumber ?? this.personalNumber,
        role: role ?? this.role,
        detachmentId: detachmentId,
        attendance: attendance ?? this.attendance,
        phoneMasked: phoneMasked,
        checkInAt: clearCheckIn ? null : checkInAt ?? this.checkInAt,
        checkOutAt: clearCheckOut ? null : checkOutAt ?? this.checkOutAt,
      );

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        id: j['id'] as String,
        name: normalizeMemberName(j['name'] as String),
        initials: (j['initials'] as String?) ??
            initialsOf(normalizeMemberName(j['name'] as String)),
        department: (j['department'] as String?) ?? '',
        personalNumber: (j['personalNumber'] as String?) ?? '',
        role: teamRoleFromWire((j['role'] as String?) ?? 'member'),
        detachmentId: j['detachmentId'] as String,
        attendance: attendanceStateFromWire(
          (j['attendance'] as String?) ?? 'notCheckedIn',
        ),
        phoneMasked: j['phoneMasked'] as String?,
        checkInAt: j['checkInAt'] == null
            ? null
            : DateTime.parse(j['checkInAt'] as String),
        checkOutAt: j['checkOutAt'] == null
            ? null
            : DateTime.parse(j['checkOutAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'initials': initials,
        'department': department,
        'personalNumber': personalNumber,
        'role': role.name,
        'detachmentId': detachmentId,
        'attendance': attendance.name,
        if (phoneMasked != null) 'phoneMasked': phoneMasked,
        if (checkInAt != null) 'checkInAt': checkInAt!.toIso8601String(),
        if (checkOutAt != null) 'checkOutAt': checkOutAt!.toIso8601String(),
      };
}
