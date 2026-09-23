import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/widgets/offline_banner.dart';
import 'package:mtm/features/detachment/data/detachment_providers.dart';
import 'package:mtm/features/detachment/domain/detachment_models.dart';
import 'package:mtm/features/detachment/presentation/tabs/detachment_team_tab.dart';
import 'package:mtm/features/team/data/team_providers.dart';
import 'package:mtm/features/team/domain/team_models.dart';
import 'package:mtm/features/team/domain/team_repository.dart';
import 'package:mtm/l10n/strings.dart';

/// Roster states that are awkward to reach by hand: a search that matches
/// nobody, a filter narrowing the list, a failed load, an offline device
/// serving a cached roster, and a session without the grant to add anyone.
///
/// The empty-roster state is already covered by
/// `test/features/detachment/empty_team_action_test.dart` and is not
/// duplicated here.

const _det = 'd1';

/// The detachment the roster belongs to.
///
/// Stubbed like the roster is. Since Point 13 the tab's controls resolve
/// through `DetachmentAccess`, which asks the detachment whether it is still
/// running — so the states below have to say which detachment this is rather
/// than leaving the real repository to answer for an id it has never heard of.
const _detachment = Detachment(
  id: _det,
  detachmentGroupId: 't1',
  name: 'مفرزة الاختبار',
  region: 'دمشق',
  mainCenter: 'مركز الاختبار',
  memberCount: 3,
  weeklyShiftCount: 0,
  coveragePercent: 0,
  status: DetachmentStatus.active,
);

TeamMember _member(
  String id,
  String name, {
  String department = 'الإسعاف',
  TeamRole role = TeamRole.member,
}) =>
    TeamMember(
      id: id,
      name: name,
      initials: TeamMember.initialsOf(name),
      department: department,
      personalNumber: id.replaceAll('m', '10'),
      role: role,
      detachmentId: _det,
      attendance: AttendanceState.notCheckedIn,
    );

final _roster = [
  _member('m1', 'أحمد كنعان', role: TeamRole.shiftSupervisor),
  _member('m2', 'ليلى ياسين', role: TeamRole.administrator),
  _member('m3', 'نور الحسن', department: 'الإسناد اللوجستي'),
];

/// Serves one canned answer — enough for the states this file is about.
class _StubTeamRepository implements TeamRepository {
  _StubTeamRepository(this.answer);

  final Result<List<TeamMember>> answer;

  @override
  Future<Result<List<TeamMember>>> listForDetachment(
          String detachmentId) async =>
      answer;

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester, {
  Result<List<TeamMember>>? roster,
  Capabilities capabilities = const Capabilities(global: Cap.all),
}) async {
  tester.view.physicalSize = const Size(1080, 2000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        capabilitiesProvider.overrideWithValue(capabilities),
        teamRepositoryProvider.overrideWithValue(
          _StubTeamRepository(roster ?? Success(_roster)),
        ),
        detachmentByIdProvider(_det).overrideWith(
          (ref) async => const Success<Detachment>(_detachment),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: DetachmentTeamTab(detachmentId: _det)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a search that matches nobody says so and offers a way back',
      (tester) async {
    await _pump(tester);
    expect(find.text('أحمد كنعان'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('members-search')), 'زياد');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('members-no-results')), findsOneWidget);
    expect(find.text(S.noMatchingMembers), findsOneWidget);
    expect(find.text('أحمد كنعان'), findsNothing);

    // The way out restores the whole roster rather than leaving a dead end.
    await tester.tap(find.text(S.membersClearFilters));
    await tester.pumpAndSettle();
    expect(find.text('أحمد كنعان'), findsOneWidget);
  });

  testWidgets(
      'an unvocalised query still finds the member, and the header '
      'says how much of the roster is showing', (tester) async {
    await _pump(tester);

    await tester.enterText(find.byKey(const Key('members-search')), 'احمد');
    await tester.pumpAndSettle();

    expect(find.text('أحمد كنعان'), findsOneWidget);
    expect(find.text('ليلى ياسين'), findsNothing);
    expect(
      find.text(S.membersShowingCount
          .replaceFirst('%d', '١')
          .replaceFirst('%d', '٣')),
      findsOneWidget,
    );
  });

  testWidgets('a role filter narrows the list and can be removed again',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('members-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('members-filter-administrator')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('members-filters-apply')));
    await tester.pumpAndSettle();

    expect(find.text('ليلى ياسين'), findsOneWidget);
    expect(find.text('أحمد كنعان'), findsNothing);

    // The active filter is visible and removable without reopening the sheet.
    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('أحمد كنعان'), findsOneWidget);
  });

  testWidgets('a failed roster load offers a retry, not an empty roster',
      (tester) async {
    await _pump(tester, roster: const Failure('boom', code: 'server_error'));

    expect(find.text(S.retry), findsOneWidget);
    expect(find.byKey(const Key('members-search')), findsNothing);
  });

  testWidgets('an offline device serves the cached roster, marked stale',
      (tester) async {
    await _pump(tester, roster: Offline(cached: _roster));

    expect(find.text('أحمد كنعان'), findsOneWidget);
    expect(find.byType(StaleBadge), findsOneWidget);
  });

  testWidgets('without the invite grant there is no add affordance at all',
      (tester) async {
    await _pump(
      tester,
      capabilities: const Capabilities(
        scoped: {
          _det: {Cap.detachmentView, Cap.memberView}
        },
      ),
    );

    expect(find.text('أحمد كنعان'), findsOneWidget);
    expect(find.text(S.addMember), findsNothing);
  });
}
