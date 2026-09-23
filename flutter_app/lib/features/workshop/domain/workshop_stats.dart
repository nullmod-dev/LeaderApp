import '../../../l10n/strings.dart';
import '../../team/domain/team_models.dart';
import 'workshop_models.dart';

/// The two kinds of person a workshop's statistics count separately.
///
/// They are separated because the questions asked about them differ: a
/// participant's attendance is the workshop's result, an organising team
/// member's attendance is its staffing. Averaging the two hides both.
enum WorkshopStatsGroup { participant, team }

extension WorkshopStatsGroupLabel on WorkshopStatsGroup {
  String get label => switch (this) {
        WorkshopStatsGroup.participant => S.statsGroupParticipants,
        WorkshopStatsGroup.team => S.statsGroupTeam,
      };
}

extension PaymentStatusLabel on PaymentStatus? {
  /// `null` reads as "not recorded", never as "unpaid".
  String get label => switch (this) {
        PaymentStatus.paid => S.paymentPaid,
        PaymentStatus.unpaid => S.paymentUnpaid,
        null => S.paymentUnspecified,
      };
}

extension AttendanceStateLabel on AttendanceState {
  String get statsLabel => switch (this) {
        AttendanceState.checkedIn => S.checkedIn,
        AttendanceState.checkedOut => S.checkedOut,
        AttendanceState.absent => S.absent,
        AttendanceState.notCheckedIn => S.notCheckedIn,
      };

  /// Whether this person was actually here.
  ///
  /// `checkedOut` counts: somebody who signed out had to have signed in
  /// first, and a workshop that has ended leaves everyone in that state. The
  /// older stats tile counted only `checkedIn`, which quietly reported a
  /// finished workshop as 0% attended.
  bool get wasPresent =>
      this == AttendanceState.checkedIn || this == AttendanceState.checkedOut;
}

/// One person in the statistics, flattened out of whichever list they came
/// from so both groups can be counted, listed and exported the same way.
class WorkshopStatsPerson {
  const WorkshopStatsPerson({
    required this.id,
    required this.name,
    required this.group,
    required this.roleLabel,
    required this.attendance,
    required this.paymentStatus,
  });

  final String id;
  final String name;
  final WorkshopStatsGroup group;

  /// What to print next to the name: the team member's role, or which kind
  /// of participant they are.
  final String roleLabel;

  final AttendanceState attendance;
  final PaymentStatus? paymentStatus;
}

/// One group's counts. Everything here is a count of people, so a reader can
/// add the columns up and get the total back.
class WorkshopGroupStats {
  const WorkshopGroupStats({
    required this.total,
    required this.present,
    required this.paid,
    required this.unpaid,
    required this.unspecified,
  });

  final int total;
  final int present;
  final int paid;
  final int unpaid;
  final int unspecified;

  int get absent => total - present;

  int get percent =>
      total == 0 ? 0 : ((present / total) * 100).round().clamp(0, 100);

  factory WorkshopGroupStats.of(List<WorkshopStatsPerson> people) =>
      WorkshopGroupStats(
        total: people.length,
        present: people.where((p) => p.attendance.wasPresent).length,
        paid: people.where((p) => p.paymentStatus == PaymentStatus.paid).length,
        unpaid:
            people.where((p) => p.paymentStatus == PaymentStatus.unpaid).length,
        unspecified: people.where((p) => p.paymentStatus == null).length,
      );
}

/// Everything the workshop statistics screen and its exports read.
///
/// Built once from the workshop and its participant list, so the dashboard,
/// the detailed tables and both export formats quote the same numbers — the
/// screen can never disagree with the file it produced.
class WorkshopStats {
  const WorkshopStats({
    required this.id,
    required this.name,
    required this.at,
    required this.location,
    required this.capacity,
    required this.guests,
    required this.registrationFee,
    required this.participantStats,
    required this.teamStats,
    required this.people,
  });

  final String id;
  final String name;
  final DateTime at;
  final String location;
  final int capacity;
  final int guests;
  final double registrationFee;
  final WorkshopGroupStats participantStats;
  final WorkshopGroupStats teamStats;
  final List<WorkshopStatsPerson> people;

  int get paidCount => participantStats.paid + teamStats.paid;
  int get unpaidCount => participantStats.unpaid + teamStats.unpaid;
  int get unspecifiedCount =>
      participantStats.unspecified + teamStats.unspecified;

  /// What has actually come in: the fee times the number of people recorded
  /// as having paid. Never an expectation — an unrecorded person is not a
  /// debt, and counting them would make the figure a forecast wearing a
  /// receipt's clothes.
  double get totalPaidAmount => registrationFee * paidCount;

  bool get isFree => registrationFee == 0;

  int get registeredCount => participantStats.total;

  int get capacityPercent => capacity == 0
      ? 0
      : ((registeredCount / capacity) * 100).round().clamp(0, 100);

  List<WorkshopStatsPerson> get participants =>
      people.where((p) => p.group == WorkshopStatsGroup.participant).toList();

  List<WorkshopStatsPerson> get teamMembers =>
      people.where((p) => p.group == WorkshopStatsGroup.team).toList();

  List<WorkshopStatsPerson> get paidPeople =>
      people.where((p) => p.paymentStatus == PaymentStatus.paid).toList();

  /// Flattens a workshop and its participants into the statistics.
  ///
  /// The organising team comes off the workshop record itself — it is a list
  /// of roster members, not of registrations, so nobody on it carries a
  /// payment record. They land in "not recorded", which is the truth: the
  /// team runs the workshop, it does not buy a seat at it.
  factory WorkshopStats.of(
    Workshop workshop,
    List<WorkshopParticipant> participants,
  ) {
    final people = <WorkshopStatsPerson>[
      for (final p in participants)
        WorkshopStatsPerson(
          id: p.id,
          name: p.name,
          group: WorkshopStatsGroup.participant,
          roleLabel: p.kind == ParticipantKind.guest
              ? S.participantGuest
              : S.participantMember,
          attendance: p.attendance,
          paymentStatus: p.paymentStatus,
        ),
      for (final m in workshop.organizingTeam)
        WorkshopStatsPerson(
          id: m.id,
          name: m.name,
          group: WorkshopStatsGroup.team,
          roleLabel: _roleLabel(m.role),
          attendance: m.attendance,
          paymentStatus: null,
        ),
    ];

    return WorkshopStats(
      id: workshop.id,
      name: workshop.name,
      at: workshop.at,
      location: workshop.location,
      capacity: workshop.capacity,
      guests: workshop.guests,
      registrationFee: workshop.registrationFee,
      participantStats: WorkshopGroupStats.of(
        people.where((p) => p.group == WorkshopStatsGroup.participant).toList(),
      ),
      teamStats: WorkshopGroupStats.of(
        people.where((p) => p.group == WorkshopStatsGroup.team).toList(),
      ),
      people: people,
    );
  }
}

/// The same four labels the team tabs print. Kept local rather than pushed
/// into `team_models.dart`: moving it would mean touching every existing
/// call site, which is a refactor this change did not ask for.
String _roleLabel(TeamRole role) => switch (role) {
      TeamRole.shiftSupervisor => S.roleShiftSupervisor,
      TeamRole.administrator => S.roleAdministrator,
      TeamRole.followUp => S.roleFollowUp,
      TeamRole.member => S.roleMember,
    };
