import '../../team/domain/team_models.dart';

enum WorkshopStatus { scheduled, ongoing, done }

/// Whether a person has paid the workshop's registration fee.
///
/// Deliberately used as a *nullable* type everywhere: `null` is a third,
/// meaningful state — "not recorded yet" — and it is the state most people
/// are in before the door opens. Collapsing it into `unpaid` would turn a
/// missing record into an accusation.
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

/// A member is a person on the tenant's roster, linked by
/// [WorkshopParticipant.memberId]; a guest is somebody from outside the team,
/// known only by the name typed at the door.
enum ParticipantKind { member, guest }

/// One line of a workshop's register.
///
/// A member participant is a *reference* to a roster [TeamMember] — the
/// [memberId] is the relationship, and [name]/[initials] are a display
/// snapshot taken when they were added. Removing the line never touches the
/// roster, and deleting the roster member later leaves the register readable
/// under the name it was recorded with.
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
  });

  final String id;
  final String workshopId;
  final String name;
  final String initials;
  final ParticipantKind kind;
  final AttendanceState attendance;

  /// The roster member this line refers to. Always set for
  /// [ParticipantKind.member] written by this client; `null` for a guest, and
  /// tolerated as `null` on an old member record that predates the link.
  final String? memberId;

  /// `null` until somebody records it — see [PaymentStatus].
  final PaymentStatus? paymentStatus;

  /// [clearPayment] returns the record to "not recorded" — the one value a
  /// plain nullable argument cannot express.
  WorkshopParticipant copyWith({
    AttendanceState? attendance,
    PaymentStatus? paymentStatus,
    bool clearPayment = false,
  }) =>
      WorkshopParticipant(
        id: id,
        workshopId: workshopId,
        name: name,
        initials: initials,
        kind: kind,
        memberId: memberId,
        attendance: attendance ?? this.attendance,
        paymentStatus:
            clearPayment ? null : paymentStatus ?? this.paymentStatus,
      );

  factory WorkshopParticipant.fromJson(Map<String, dynamic> j) =>
      WorkshopParticipant(
        id: j['id'] as String,
        workshopId: j['workshopId'] as String,
        name: j['name'] as String,
        initials: j['initials'] as String,
        kind: ParticipantKind.values.firstWhere((k) => k.name == j['kind']),
        memberId: j['memberId'] as String?,
        attendance: attendanceStateFromWire(
          (j['attendance'] as String?) ?? 'notCheckedIn',
        ),
        paymentStatus: switch (j['paymentStatus'] as String?) {
          'paid' => PaymentStatus.paid,
          'unpaid' => PaymentStatus.unpaid,
          _ => null,
        },
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'workshopId': workshopId,
        'name': name,
        'initials': initials,
        'kind': kind.name,
        if (memberId != null) 'memberId': memberId,
        'attendance': attendance.name,
        if (paymentStatus != null) 'paymentStatus': paymentStatus!.name,
      };
}
