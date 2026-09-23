import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/detachment/data/detachment_providers.dart';
import 'package:mtm/features/detachment/domain/detachment_models.dart';
import 'package:mtm/features/detachment/presentation/detachment_member_status_page.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/features/shift/domain/shift_repository.dart';
import 'package:mtm/features/shift/data/shift_providers.dart';
import 'package:mtm/features/team/data/team_providers.dart';
import 'package:mtm/features/team/domain/team_models.dart';
import 'package:mtm/features/team/domain/team_repository.dart';
import 'package:mtm/l10n/strings.dart';

/// The member page's conditional states: contact withheld by grant, contact
/// simply absent from the record, no assignment today, and a member deleted
/// while their page is open.

const _det = 'd1';

/// The detachment this member belongs to.
///
/// Stubbed like the roster and the schedule are. Since Point 13 the page's
/// controls resolve through `DetachmentAccess`, which asks the detachment
/// whether it is still running — so the states below say which detachment
/// this is rather than leaving the real repository to answer for an id it has
/// never heard of.
const _detachment = Detachment(
  id: _det,
  detachmentGroupId: 't1',
  name: 'مفرزة الاختبار',
  region: 'دمشق',
  mainCenter: 'مركز الاختبار',
  memberCount: 1,
  weeklyShiftCount: 1,
  coveragePercent: 0,
  status: DetachmentStatus.active,
);
const _memberId = 'm1';

TeamMember _member({String? phone}) => TeamMember(
      id: _memberId,
      name: 'أحمد كنعان',
      initials: 'أك',
      department: 'الإسعاف',
      personalNumber: '101',
      role: TeamRole.shiftSupervisor,
      detachmentId: _det,
      attendance: AttendanceState.checkedIn,
      phoneMasked: phone,
    );

class _StubTeamRepository implements TeamRepository {
  _StubTeamRepository(this.member);

  final Result<TeamMember> member;

  @override
  Future<Result<TeamMember>> byId(String memberId) async => member;

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _StubShiftRepository implements ShiftRepository {
  _StubShiftRepository(this.todays);

  final List<Shift> todays;

  @override
  Future<Result<List<Shift>>> listForDetachmentToday(String id) async =>
      Success(todays);

  @override
  Future<Result<List<Shift>>> listForRange(
          String id, DateTime from, DateTime to) async =>
      Success(todays);

  @override
  noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _pump(
  WidgetTester tester, {
  Result<TeamMember>? member,
  List<Shift> todays = const [],
  Capabilities capabilities = const Capabilities(global: Cap.all),
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        capabilitiesProvider.overrideWithValue(capabilities),
        teamRepositoryProvider.overrideWithValue(
            _StubTeamRepository(member ?? Success(_member()))),
        shiftRepositoryProvider.overrideWithValue(_StubShiftRepository(todays)),
        detachmentByIdProvider(_det).overrideWith(
          (ref) async => const Success<Detachment>(_detachment),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: DetachmentMemberStatusPage(
            detachmentId: _det,
            memberId: _memberId,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets(
      'a session without the contact grant is told the data is '
      'withheld, not shown a blank card', (tester) async {
    await _pump(
      tester,
      member: Success(_member(phone: '+963 9xx xx xx 12')),
      capabilities: const Capabilities(
        scoped: {
          _det: {Cap.detachmentView, Cap.memberView}
        },
      ),
    );

    expect(find.text(S.memberContactHidden), findsOneWidget);
    expect(find.textContaining('963'), findsNothing);
  });

  testWidgets('with the grant, the number on file is shown', (tester) async {
    await _pump(tester, member: Success(_member(phone: '+963 9xx xx xx 12')));

    expect(find.text('+963 9xx xx xx 12'), findsOneWidget);
    expect(find.text(S.memberContactHidden), findsNothing);
  });

  testWidgets(
      'a record with no number says so rather than showing an empty '
      'contact card', (tester) async {
    await _pump(tester, member: Success(_member()));

    expect(find.text(S.memberNoPhone), findsOneWidget);
    expect(find.text(S.memberContactHidden), findsNothing);
  });

  testWidgets('a member with nothing on the schedule today says so',
      (tester) async {
    await _pump(tester);
    expect(find.text(S.memberNoAssignmentToday), findsOneWidget);
  });

  testWidgets('a member on a running shift gets the shift, not a blank line',
      (tester) async {
    final now = DateTime.now();
    final start = now.subtract(const Duration(hours: 1));
    final end = now.add(const Duration(hours: 2));

    await _pump(tester, todays: [
      Shift(
        id: 'sh1',
        detachmentId: _det,
        date: dateOnly(start),
        centerName: 'مركز الشعلان',
        startMinutes: start.hour * 60 + start.minute,
        endMinutes: end.hour * 60 + end.minute,
        needed: 2,
        attendees: [_member()],
      ),
    ]);

    // The centre also appears in the attendance history below, so this only
    // asserts the assignment section resolved to a real shift.
    expect(find.text('مركز الشعلان'), findsWidgets);
    expect(find.text(S.memberNoAssignmentToday), findsNothing);
    // Shift management stays the Shifts module's job — this is only the way in.
    expect(find.byKey(const Key('member-open-shift')), findsOneWidget);
  });

  testWidgets(
      'a member deleted while the page is open gets its own state '
      'with a way back', (tester) async {
    await _pump(
      tester,
      member: const Failure('لم يُعثر على العضو.', code: 'not_found'),
    );

    expect(find.byKey(const Key('member-removed')), findsOneWidget);
    expect(find.text(S.memberRemovedTitle), findsOneWidget);
    expect(find.text(S.memberBackToRoster), findsOneWidget);
    // Not offered as a retry — the record is gone, retrying would fail again.
    expect(find.text(S.retry), findsNothing);
  });
}
