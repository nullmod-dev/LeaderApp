import '../../team/domain/team_models.dart';

enum WorkshopStatus { scheduled, ongoing, done }

/// Whether a person has paid the workshop's registration fee.
///
/// Payment is binary on the register: somebody has paid, or has not. The type
/// stays nullable on the wire because old records may carry no value; the
/// register and the statistics read a missing value as unpaid
/// ([WorkshopParticipant.isPaid]).
enum PaymentStatus { paid, unpaid }

class Workshop {
  const Workshop({
    required this.id,
    required this.name,
    required this.at,
    required this.location,
    required this.capacity,
    required this.registered,
    required this.guests,
    required this.status,
    required this.organizingTeam,
    this.registrationFee = 0,
    this.archived = false,
  });

  final String id;
  final String name;
  final DateTime at;
  final String location;
  final int capacity;

  /// Seats taken — every person on the register, members and guests alike.
  /// Derived by the repository from the participant register, never typed by
  /// hand, so the list card, the capacity check and the statistics can never
  /// disagree about how full a workshop is.
  final int registered;

  /// The guests among [registered]. Derived the same way.
  final int guests;
  final WorkshopStatus status;
  final List<TeamMember> organizingTeam;

  /// What one seat costs. `0` means the workshop is free, and the statistics
  /// screen says so instead of printing a zero total.
  final double registrationFee;

  /// An archived workshop is finished business: it stays readable and
  /// exportable, and nothing on it can be changed until it is restored
  /// (`workshop.archive`). A flag rather than a fourth [WorkshopStatus]: the
  /// status says how the workshop went, the archive says whether it is still
  /// being worked on, and a done workshop can be either.
  final bool archived;

  bool get isFull => registered >= capacity;

  Workshop copyWith({
    String? name,
    DateTime? at,
    String? location,
    int? capacity,
    int? registered,
    int? guests,
    WorkshopStatus? status,
    List<TeamMember>? organizingTeam,
    double? registrationFee,
    bool? archived,
  }) =>
      Workshop(
        id: id,
        name: name ?? this.name,
        at: at ?? this.at,
        location: location ?? this.location,
        capacity: capacity ?? this.capacity,
        registered: registered ?? this.registered,
        guests: guests ?? this.guests,
        status: status ?? this.status,
        organizingTeam: organizingTeam ?? this.organizingTeam,
        registrationFee: registrationFee ?? this.registrationFee,
        archived: archived ?? this.archived,
      );

  factory Workshop.fromJson(Map<String, dynamic> j) => Workshop(
        id: j['id'] as String,
        name: j['name'] as String,
        at: DateTime.parse(j['at'] as String),
        location: j['location'] as String,
        capacity: j['capacity'] as int,
        registered: j['registered'] as int,
        guests: j['guests'] as int,
        status: WorkshopStatus.values.firstWhere((s) => s.name == j['status']),
        organizingTeam: (j['organizingTeam'] as List)
            .map((e) => TeamMember.fromJson(e as Map<String, dynamic>))
            .toList(),
        registrationFee: (j['registrationFee'] as num?)?.toDouble() ?? 0,
        archived: (j['archived'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'at': at.toIso8601String(),
        'location': location,
        'capacity': capacity,
        'registered': registered,
        'guests': guests,
        'status': status.name,
        'organizingTeam': organizingTeam.map((t) => t.toJson()).toList(),
        'registrationFee': registrationFee,
        'archived': archived,
      };
}

/// The two parts of a workshop's register.
///
/// A member is one of the workshop's own team members: a name typed in by
/// hand, with a [WorkshopRole]. A guest is a volunteer or a visitor — not a
/// team member, known only by name. The value keeps its wire name `guest`.
enum ParticipantKind { member, guest }

/// What a team member does on this workshop. Workshop-only, and separate from
/// the roster's `TeamRole`: nobody on a workshop is picked from the roster.
/// Stored on the wire by `.name`.
enum WorkshopRole { leader, trainer, support, management, member }

/// One line of a workshop's register.
///
/// Every workshop owns its own people: a line is never shared with another
/// workshop, and removing it touches nothing else. [memberId] survives only
/// on old records that were once linked to a roster member.
class WorkshopParticipant {
  const WorkshopParticipant({
    required this.id,
    required this.workshopId,
    required this.name,
    required this.initials,
    required this.kind,
    required this.attendance,
    this.memberId,
    this.paymentStatus,
    this.role,
  });

  final String id;
  final String workshopId;
  final String name;
  final String initials;
  final ParticipantKind kind;
  final AttendanceState attendance;

  /// Kept only for old records that were linked to a roster member. New
  /// lines never set it — a team member is a typed name with a [role].
  final String? memberId;

  /// `null` only on old records. The register and the statistics read
  /// [isPaid], so a missing record shows and counts as unpaid; new lines are
  /// always written as paid or unpaid.
  final PaymentStatus? paymentStatus;

  /// Set for [ParticipantKind.member], `null` for a guest.
  final WorkshopRole? role;

  /// The one payment reading the UI uses: anything but `paid` is unpaid.
  bool get isPaid => paymentStatus == PaymentStatus.paid;

  /// [clearPayment] returns the record to "not recorded" — the one value a
  /// plain nullable argument cannot express.
  WorkshopParticipant copyWith({
    String? name,
    String? initials,
    WorkshopRole? role,
    AttendanceState? attendance,
    PaymentStatus? paymentStatus,
    bool clearPayment = false,
  }) =>
      WorkshopParticipant(
        id: id,
        workshopId: workshopId,
        name: name ?? this.name,
        initials: initials ?? this.initials,
        kind: kind,
        memberId: memberId,
        role: role ?? this.role,
        attendance: attendance ?? this.attendance,
        paymentStatus:
            clearPayment ? null : paymentStatus ?? this.paymentStatus,
      );

  factory WorkshopParticipant.fromJson(Map<String, dynamic> j) {
    final kind = ParticipantKind.values.firstWhere((k) => k.name == j['kind']);
    return WorkshopParticipant(
      id: j['id'] as String,
      workshopId: j['workshopId'] as String,
      name: j['name'] as String,
      initials: j['initials'] as String,
      kind: kind,
      memberId: j['memberId'] as String?,
      // An old member line has no role; an unknown one is read as a plain
      // member rather than refused.
      role: kind == ParticipantKind.guest
          ? null
          : WorkshopRole.values.firstWhere(
              (r) => r.name == j['role'],
              orElse: () => WorkshopRole.member,
            ),
      attendance: attendanceStateFromWire(
        (j['attendance'] as String?) ?? 'notCheckedIn',
      ),
      paymentStatus: switch (j['paymentStatus'] as String?) {
        'paid' => PaymentStatus.paid,
        'unpaid' => PaymentStatus.unpaid,
        _ => null,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'workshopId': workshopId,
        'name': name,
        'initials': initials,
        'kind': kind.name,
        if (memberId != null) 'memberId': memberId,
        if (role != null) 'role': role!.name,
        'attendance': attendance.name,
        if (paymentStatus != null) 'paymentStatus': paymentStatus!.name,
      };
}
