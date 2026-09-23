import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/detachment/domain/report_models.dart';
import 'package:mtm/features/team/domain/team_models.dart';
import 'package:mtm/features/workshop/data/workshop_providers.dart';
import 'package:mtm/features/workshop/data/workshop_stats_providers.dart';
import 'package:mtm/features/workshop/data/workshop_stats_report.dart';
import 'package:mtm/features/workshop/domain/workshop_models.dart';
import 'package:mtm/features/workshop/domain/workshop_stats.dart';
import 'package:mtm/features/workshop/presentation/tabs/workshop_stats_tab.dart';
import 'package:mtm/features/workshop/presentation/widgets/workshop_stats_export.dart';
import 'package:mtm/l10n/strings.dart';

/// Workshop → Statistics, copied across from the medical-team app's
/// dashboard → detail → export flow and rebuilt on this app's models.
///
/// The contract worth testing is the honesty of the numbers: attendance
/// counted per group rather than pooled, "not recorded" kept distinct from
/// "unpaid", money that only ever counts what was actually taken, and one
/// report object behind both export formats so a file can never disagree
/// with the screen that produced it.

T _ok<T>(Result<T> r) => r.when(
      success: (data, {stale = false}) => data,
      failure: (m, c) => fail('$m ($c)'),
      offline: (_) => fail('offline'),
    );

Workshop _workshop({
  double fee = 1000,
  int capacity = 10,
  List<TeamMember> team = const [],
}) =>
    Workshop(
      id: 'w-test',
      name: 'ورشة الاختبار',
      at: DateTime(2026, 9, 3, 10),
      location: 'قاعة الاختبار',
      capacity: capacity,
      registered: 4,
      guests: 1,
      status: WorkshopStatus.done,
      organizingTeam: team,
      registrationFee: fee,
    );

WorkshopParticipant _p(
  String id, {
  required AttendanceState attendance,
  PaymentStatus? payment,
  ParticipantKind kind = ParticipantKind.member,
}) =>
    WorkshopParticipant(
      id: id,
      workshopId: 'w-test',
      name: 'مشارك $id',
      initials: 'مش',
      kind: kind,
      attendance: attendance,
      paymentStatus: payment,
    );

TeamMember _member(String id, AttendanceState attendance) => TeamMember(
      id: id,
      name: 'منظم $id',
      initials: 'من',
      role: TeamRole.shiftSupervisor,
      detachmentId: 'd_dam_central',
      attendance: attendance,
    );

void main() {
  group('the counts', () {
    test('a person who checked out was present', () {
      // A finished workshop leaves everybody checked *out*. Counting only
      // `checkedIn` reported those as 0% attended, which is the one number a
      // post-workshop report must not get wrong.
      final stats = WorkshopStats.of(_workshop(), [
        _p('1', attendance: AttendanceState.checkedOut),
        _p('2', attendance: AttendanceState.checkedIn),
        _p('3', attendance: AttendanceState.absent),
        _p('4', attendance: AttendanceState.notCheckedIn),
      ]);
      expect(stats.participantStats.present, 2);
      expect(stats.participantStats.absent, 2);
      expect(stats.participantStats.percent, 50);
    });

    test('the two groups are counted apart, never pooled', () {
      final stats = WorkshopStats.of(
        _workshop(team: [
          _member('t1', AttendanceState.checkedIn),
          _member('t2', AttendanceState.checkedIn),
        ]),
        [
          _p('1', attendance: AttendanceState.absent),
          _p('2', attendance: AttendanceState.absent),
        ],
      );
      expect(stats.participantStats.percent, 0);
      expect(stats.teamStats.percent, 100);
      expect(stats.participants, hasLength(2));
      expect(stats.teamMembers, hasLength(2));
    });

    test('an empty group is 0%, not a division by zero', () {
      final stats = WorkshopStats.of(_workshop(), const []);
      expect(stats.participantStats.total, 0);
      expect(stats.participantStats.percent, 0);
      expect(stats.teamStats.percent, 0);
    });

    test('"not recorded" is its own column, never folded into unpaid', () {
      final stats = WorkshopStats.of(_workshop(), [
        _p('1',
            attendance: AttendanceState.checkedIn, payment: PaymentStatus.paid),
        _p('2',
            attendance: AttendanceState.checkedIn,
            payment: PaymentStatus.unpaid),
        _p('3', attendance: AttendanceState.checkedIn),
      ]);
      expect(stats.participantStats.paid, 1);
      expect(stats.participantStats.unpaid, 1);
      expect(stats.participantStats.unspecified, 1);
      expect(null.label, S.paymentUnspecified);
    });

    test('the organising team has no payment record, so it lands unspecified',
        () {
      final stats = WorkshopStats.of(
        _workshop(team: [_member('t1', AttendanceState.checkedIn)]),
        const [],
      );
      expect(stats.teamStats.unspecified, 1);
      expect(stats.teamStats.paid, 0);
    });
  });

  group('the money', () {
    test('only counts what was actually taken', () {
      final stats = WorkshopStats.of(_workshop(fee: 2500), [
        _p('1',
            attendance: AttendanceState.checkedIn, payment: PaymentStatus.paid),
        _p('2',
            attendance: AttendanceState.checkedIn, payment: PaymentStatus.paid),
        // Neither of these adds a pound to the total: one has not paid, and
        // the other simply has not been recorded.
        _p('3',
            attendance: AttendanceState.checkedIn,
            payment: PaymentStatus.unpaid),
        _p('4', attendance: AttendanceState.checkedIn),
      ]);
      expect(stats.paidCount, 2);
      expect(stats.totalPaidAmount, 5000);
      expect(stats.unpaidCount, 1);
      expect(stats.unspecifiedCount, 1);
    });

    test('a free workshop says so instead of printing zeros', () {
      final stats = WorkshopStats.of(_workshop(fee: 0), const []);
      expect(stats.isFree, isTrue);
      expect(stats.totalPaidAmount, 0);
    });

    test('an amount drops its decimals when it has none', () {
      // Arabic-Indic digits, the unit appended, and no trailing "٫٠٠" on a
      // round figure.
      expect(formatWorkshopAmount(25000), '٢٥٠٠٠ ${S.currencyUnit}');
      expect(formatWorkshopAmount(25000.5), startsWith('٢٥٠٠٠.٥٠'));
    });
  });

  group('the exported report', () {
    WorkshopStats sample() => WorkshopStats.of(
          _workshop(team: [_member('t1', AttendanceState.checkedIn)]),
          [
            _p('1',
                attendance: AttendanceState.checkedIn,
                payment: PaymentStatus.paid),
            _p('2',
                attendance: AttendanceState.absent,
                payment: PaymentStatus.unpaid,
                kind: ParticipantKind.guest),
          ],
        );

    test('carries the workshop in the header, not a date window', () {
      final doc = buildWorkshopStatsReport(
        sample(),
        generatedAt: DateTime.utc(2026, 9, 21),
      );
      expect(doc.detachmentName, 'ورشة الاختبار');
      expect(doc.detachmentGroupName, 'قاعة الاختبار');
      // The document model needs a range; the header must not print one.
      expect(doc.scopeLabel, isNot(ReportRange.week.label));
      expect(doc.scopeLabel, contains(S.workshopStatsTitle));
    });

    test('every section is included by default and each is selectable', () {
      final all = buildWorkshopStatsReport(
        sample(),
        generatedAt: DateTime.utc(2026, 9, 21),
      );
      expect(all.blocks, hasLength(4)); // summary table + finance facts + 2

      final summaryOnly = buildWorkshopStatsReport(
        sample(),
        sections: const {WorkshopReportSection.summary},
        generatedAt: DateTime.utc(2026, 9, 21),
      );
      expect(summaryOnly.blocks, hasLength(2));

      final teamOnly = buildWorkshopStatsReport(
        sample(),
        sections: const {WorkshopReportSection.team},
        generatedAt: DateTime.utc(2026, 9, 21),
      );
      expect(teamOnly.blocks, hasLength(1));
      expect(teamOnly.blocks.single.title, contains(S.statsSecTeam));
    });

    test('nothing selected produces an empty document, not a blank file', () {
      final none = buildWorkshopStatsReport(
        sample(),
        sections: const {},
        generatedAt: DateTime.utc(2026, 9, 21),
      );
      expect(none.isEmpty, isTrue);
    });

    test('the CSV carries the same rows the PDF would lay out', () {
      final doc = buildWorkshopStatsReport(
        sample(),
        generatedAt: DateTime.utc(2026, 9, 21),
      );
      final csv = doc.toCsv();
      expect(csv, contains('ورشة الاختبار'));
      expect(csv, contains(S.statsGroupParticipants));
      expect(csv, contains('مشارك 1'));
      expect(csv, contains(S.paymentPaid));
      // The guest's role reaches the file, not just the screen.
      expect(csv, contains(S.participantGuest));
    });

    test('a person row is numbered from one in Arabic-Indic digits', () {
      final doc = buildWorkshopStatsReport(
        sample(),
        sections: const {WorkshopReportSection.participants},
        generatedAt: DateTime.utc(2026, 9, 21),
      );
      final table = doc.blocks.single as ReportTable;
      expect(table.data.first.first, '١');
      expect(table.data.last.first, '٢');
    });
  });

  group('copying names', () {
    test('numbers the paid people from one', () {
      final stats = WorkshopStats.of(_workshop(), [
        _p('1',
            attendance: AttendanceState.checkedIn, payment: PaymentStatus.paid),
        _p('2',
            attendance: AttendanceState.checkedIn, payment: PaymentStatus.paid),
      ]);
      expect(formatPaidNames(stats.paidPeople), '١ - مشارك 1\n٢ - مشارك 2');
    });

    test('paidPeople spans both groups but excludes everyone else', () {
      final stats = WorkshopStats.of(
        _workshop(team: [_member('t1', AttendanceState.checkedIn)]),
        [
          _p('1',
              attendance: AttendanceState.checkedIn,
              payment: PaymentStatus.paid),
          _p('2',
              attendance: AttendanceState.checkedIn,
              payment: PaymentStatus.unpaid),
          _p('3', attendance: AttendanceState.checkedIn),
        ],
      );
      expect(stats.paidPeople.map((p) => p.id), ['1']);
    });
  });

  /// Mounts the tab against a fixed [WorkshopStats].
  ///
  /// The provider is overridden rather than driven: the seeded repository
  /// answers on a timer and `workshopStatsProvider` is `autoDispose`, so a
  /// live read would put the tab in its loading skeleton — whose shimmer is a
  /// looping animation `pumpAndSettle` can never settle. The provider itself
  /// is covered by its own test below; this one is about the screen.
  Future<void> mount(WidgetTester tester, WorkshopStats stats) async {
    tester.view.physicalSize = const Size(450, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workshopStatsProvider(stats.id)
              .overrideWith((ref) async => Success<WorkshopStats>(stats)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.slate),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: MotionScope(
              level: MotionLevel.performance,
              child: Scaffold(body: WorkshopStatsTab(workshopId: stats.id)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the dashboard renders the whole flow', () {
    testWidgets('dashboard, detail table and both export surfaces',
        (tester) async {
      // A workshop with participants, a team, a fee, and all three payment
      // states present.
      await mount(
        tester,
        WorkshopStats.of(
          _workshop(team: [_member('t1', AttendanceState.checkedIn)]),
          [
            _p('1',
                attendance: AttendanceState.checkedIn,
                payment: PaymentStatus.paid),
            _p('2',
                attendance: AttendanceState.absent,
                payment: PaymentStatus.unpaid),
            _p('3', attendance: AttendanceState.notCheckedIn),
          ],
        ),
      );

      // Dashboard.
      expect(find.text(S.statsAttendanceSection), findsOneWidget);
      expect(find.text(S.statsFinanceSection), findsOneWidget);
      // Detail — the same six columns the exported summary uses.
      expect(find.text(S.statsDetailSection), findsOneWidget);
      expect(find.text(S.statsColPresent), findsOneWidget);
      expect(find.text(S.paymentUnspecified), findsWidgets);
      // Both ways out of the app.
      expect(find.text(S.statsCopyTitle), findsOneWidget);
      expect(find.text(S.statsExportTitle), findsOneWidget);
      expect(find.text(S.exportPdf), findsOneWidget);
      expect(find.text(S.exportExcel), findsOneWidget);

      // The custom export sheet offers exactly the three sections.
      await tester.tap(find.text(S.statsExportCustom));
      await tester.pumpAndSettle();
      expect(find.text(S.statsSecSummary), findsOneWidget);
      expect(find.text(S.statsSecParticipants), findsOneWidget);
      expect(find.text(S.statsSecTeam), findsOneWidget);
      // All three start selected, so the default export is the full report.
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
    });

    testWidgets('a free workshop shows the free line instead of a fee',
        (tester) async {
      await mount(tester, WorkshopStats.of(_workshop(fee: 0), const []));
      expect(find.text(S.statsFreeWorkshop), findsOneWidget);
      expect(find.text(S.statsPayers), findsNothing);
    });
  });

  group('the seeded data reaches the statistics', () {
    test('the seeded schedule is derived from the injected clock', () async {
      final fixed = DateTime.utc(2031, 2, 3, 7, 30);
      final container = ProviderContainer(
        overrides: [clockProvider.overrideWithValue(() => fixed)],
      );
      addTearDown(container.dispose);

      final all = _ok(await container.read(workshopListProvider.future));
      final first = all.singleWhere((workshop) => workshop.id == 'w1');
      expect(first.at, fixed.add(const Duration(days: 4, hours: 3)));
    });

    test('every payment state appears somewhere in the seed', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final all = _ok(await container.read(workshopListProvider.future));
      final states = <String>{};
      for (final w in all) {
        final parts = _ok(
            await container.read(workshopParticipantsProvider(w.id).future));
        for (final p in parts) {
          states.add(p.paymentStatus?.name ?? 'unspecified');
        }
      }
      expect(states, containsAll(['paid', 'unpaid', 'unspecified']));
    });

    test('workshopStatsProvider composes the workshop with its participants',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final stats =
          _ok(await container.read(workshopStatsProvider('w1').future));
      final participants =
          _ok(await container.read(workshopParticipantsProvider('w1').future));
      final workshop =
          _ok(await container.read(workshopByIdProvider('w1').future));

      expect(stats.id, 'w1');
      expect(stats.participants, hasLength(participants.length));
      expect(stats.teamMembers, hasLength(workshop.organizingTeam.length));
      expect(stats.registrationFee, workshop.registrationFee);
      expect(stats.totalPaidAmount, workshop.registrationFee * stats.paidCount);
    });
  });
}
