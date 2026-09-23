import '../../../core/format/app_number.dart';
import '../../../core/format/app_time.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../l10n/strings.dart';
import '../../detachment/domain/report_models.dart';
import '../domain/workshop_stats.dart';

/// Which parts of the workshop report to include.
///
/// The same three switches drive the on-screen sections, the PDF and the
/// spreadsheet, so "what I chose" and "what I got" can never diverge.
enum WorkshopReportSection { summary, participants, team }

extension WorkshopReportSectionLabels on WorkshopReportSection {
  String get title => switch (this) {
        WorkshopReportSection.summary => S.statsSecSummary,
        WorkshopReportSection.participants => S.statsSecParticipants,
        WorkshopReportSection.team => S.statsSecTeam,
      };

  String get subtitle => switch (this) {
        WorkshopReportSection.summary => S.statsSecSummarySub,
        WorkshopReportSection.participants => S.statsSecParticipantsSub,
        WorkshopReportSection.team => S.statsSecTeamSub,
      };
}

/// Builds the workshop statistics as the app's own [ReportDocument].
///
/// Reusing that model is what gets both export formats for one implementation:
/// `AttendancePdfBuilder` already lays a document out as a paginated RTL PDF,
/// and `ReportDocument.toCsv()` already flattens the same blocks into a grid a
/// spreadsheet opens. Nothing about workshops needed a second report pipeline
/// — only a second set of blocks.
///
/// The document's title slots carry the workshop instead of a detachment:
/// name on the first line, place on the second, and the workshop's own date
/// as the header note (see [ReportDocument.headerNote]) — a workshop happens
/// on a day, not across a window.
ReportDocument buildWorkshopStatsReport(
  WorkshopStats stats, {
  Set<WorkshopReportSection> sections = const {
    WorkshopReportSection.summary,
    WorkshopReportSection.participants,
    WorkshopReportSection.team,
  },
  required DateTime generatedAt,
}) {
  final blocks = <ReportBlock>[
    if (sections.contains(WorkshopReportSection.summary)) ...[
      ReportTable(
        S.statsSecSummary,
        const [
          S.statsColCategory,
          S.statsColPresent,
          S.statsColAbsent,
          S.paymentPaid,
          S.paymentUnpaid,
          S.paymentUnspecified,
        ],
        [
          _summaryRow(S.statsGroupParticipants, stats.participantStats),
          _summaryRow(S.statsGroupTeam, stats.teamStats),
        ],
      ),
      ReportFacts(S.statsFinanceSection, [
        (S.statsRegistrationFee, formatWorkshopAmount(stats.registrationFee)),
        (S.statsPayers, AppNumber.count(stats.paidCount)),
        (
          S.statsFinancialTotalLine,
          formatWorkshopAmount(stats.totalPaidAmount)
        ),
      ]),
    ],
    if (sections.contains(WorkshopReportSection.participants))
      ReportTable(
        '${S.statsSecParticipants} '
        '(${AppNumber.count(stats.participants.length)})',
        const [
          '#',
          S.statsColName,
          S.statsColRole,
          S.statsColAttendance,
          S.statsColPayment,
        ],
        _peopleRows(stats.participants),
      ),
    if (sections.contains(WorkshopReportSection.team))
      ReportTable(
        '${S.statsSecTeam} '
        '(${AppNumber.count(stats.teamMembers.length)})',
        const [
          '#',
          S.statsColName,
          S.statsColRole,
          S.statsColAttendance,
          S.statsColPayment,
        ],
        _peopleRows(stats.teamMembers),
      ),
  ];

  return ReportDocument(
    detachmentName: stats.name,
    detachmentGroupName: stats.location,
    generatedAt: generatedAt,
    // Present only because the model requires it; `headerNote` is what the
    // header actually prints for this document.
    range: ReportRange.week,
    headerNote: '${S.workshopStatsTitle} — ${AppTime.day(stats.at)}',
    blocks: blocks,
  );
}

List<String> _summaryRow(String label, WorkshopGroupStats group) => [
      label,
      AppNumber.count(group.present),
      AppNumber.count(group.absent),
      AppNumber.count(group.paid),
      AppNumber.count(group.unpaid),
      AppNumber.count(group.unspecified),
    ];

List<List<String>> _peopleRows(List<WorkshopStatsPerson> people) => [
      for (var i = 0; i < people.length; i++)
        [
          AppNumber.count(i + 1),
          people[i].name,
          people[i].roleLabel,
          people[i].attendance.statsLabel,
          people[i].paymentStatus.label,
        ],
    ];

/// An amount with its unit, in Arabic-Indic digits, with the decimals dropped
/// when there are none — "٢٥٠٠٠ ل.س", not "٢٥٠٠٠٫٠٠ ل.س".
String formatWorkshopAmount(double amount) {
  final text = amount.truncateToDouble() == amount
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  return '${toArabicIndic(text)} ${S.currencyUnit}';
}
