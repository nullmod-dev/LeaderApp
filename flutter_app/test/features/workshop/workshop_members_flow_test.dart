import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/team/data/mock_team_repository.dart';
import 'package:mtm/features/tenant_feature/data/tenant_feature_providers.dart';
import 'package:mtm/features/tenant_feature/domain/tenant_feature_models.dart';
import 'package:mtm/features/tenant_feature/presentation/feature_disabled_page.dart';
import 'package:mtm/features/workshop/data/mock_workshop_repository.dart';
import 'package:mtm/features/workshop/data/workshop_providers.dart';
import 'package:mtm/features/workshop/domain/workshop_models.dart';
import 'package:mtm/features/workshop/presentation/tabs/workshop_members_tab.dart';
import 'package:mtm/features/workshop/presentation/tabs/workshop_team_tab.dart';
import 'package:mtm/features/workshop/presentation/workshop_edit_page.dart';
import 'package:mtm/features/workshop/presentation/widgets/workshop_people.dart';
import 'package:mtm/l10n/strings.dart';

import '../platform/platform_harness.dart';

/// Managing a workshop's people inside the real app: the register tab, the
/// roster picker, and the two gates that decide whether any of it is offered.

/// A workshop repository whose writes never land, so the screen has to say so.
class _OfflineWrites extends MockWorkshopRepository {
  _OfflineWrites() : super(team: MockTeamRepository());

  @override
  Future<Result<List<WorkshopParticipant>>> addMemberParticipants(
    String workshopId,
    List<String> memberIds,
  ) async =>
      const Offline();
}

void main() {
  const workshop = 'w1';
  const route = '/workshop/$workshop/members';
  const candidate = 'علي منصور'; // m9 — on the roster, not on this workshop

  /// Every tenant key except people management, so the *only* reason the
  /// controls are missing is the capability the screen checks.
  final noPeopleAdmin = AuthUser(
    id: 'u_no_people',
    name: 'مشرف',
    email: 'admin@mtm.org',
    role: AuthRole.mainAdmin,
    saasTenantId: mainAdmin.saasTenantId,
    capabilities: Capabilities(
      global: Cap.all.where((k) => k != Cap.workshopPeopleManage).toSet(),
    ),
    orgName: 'ليدر',
  );

  Future<void> openRegister(
    WidgetTester tester, {
    String workshopId = workshop,
    AuthUser? user,
    List<Override> overrides = const [],
    double width = 400,
    double textScale = 1,
  }) async {
    ignoreKnownTenantComplaints();
    final container =
        platformContainer(user ?? mainAdmin, overrides: overrides);
    final router = await bootPlatform(
      tester,
      container,
      width: width,
      height: 1200,
      textScale: textScale,
    );
    router.go('/workshop/$workshopId/members');
    await settlePlatform(tester);
  }

  Future<void> pickCandidate(WidgetTester tester, String name) async {
    await tester.tap(find.widgetWithText(FilledButton, S.workshopAddMember));
    await settlePlatform(tester);
    expect(find.byType(WorkshopMemberPicker), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(WorkshopMemberPicker),
        matching: find.byType(TextField),
      ),
      name,
    );
    await settlePlatform(tester);
    // The search narrowed the roster to this one person, so the single
    // remaining checkbox is theirs.
    expect(
      find.descendant(
        of: find.byType(WorkshopMemberPicker),
        matching: find.text(name),
      ),
      findsWidgets,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(WorkshopMemberPicker),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(WorkshopMemberPicker),
        matching: find.byType(FilledButton),
      ),
    );
    await settlePlatform(tester);
  }

  testWidgets('a roster member is added to the register from the workshop',
      (tester) async {
    await openRegister(tester);
    expect(find.byType(WorkshopMembersTab), findsOneWidget);
    expect(find.text(candidate), findsNothing);

    await pickCandidate(tester, candidate);

    expect(find.byType(WorkshopMemberPicker), findsNothing);
    // The register, the seat count and the workshop record all moved together.
    expect(find.text(candidate), findsOneWidget);
    expect(find.textContaining(S.workshopSeatsTaken), findsOneWidget);
  });

  testWidgets('somebody already registered is offered but cannot be picked',
      (tester) async {
    await openRegister(tester);
    await tester.tap(find.widgetWithText(FilledButton, S.workshopAddMember));
    await settlePlatform(tester);

    await tester.enterText(
      find.descendant(
        of: find.byType(WorkshopMemberPicker),
        matching: find.byType(TextField),
      ),
      'أحمد كنعان', // m1 — already on w1's register
    );
    await settlePlatform(tester);

    expect(find.text(S.workshopPickAlreadyParticipant), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WorkshopMemberPicker),
        matching: find.byType(Checkbox),
      ),
      findsNothing,
    );
  });

  testWidgets('removing a participant takes them off this workshop only',
      (tester) async {
    await openRegister(tester);
    await tester.tap(find.text('نور الحسن')); // m4, on w1's register
    await settlePlatform(tester);

    expect(find.text(S.workshopRemoveParticipant), findsOneWidget);
    await tester.tap(find.text(S.workshopRemoveParticipant));
    await settlePlatform(tester);

    // The confirmation says plainly that the roster is not touched.
    expect(find.textContaining(S.workshopRemoveMemberBody), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, S.workshopRemove));
    await settlePlatform(tester);

    expect(find.text('نور الحسن'), findsNothing);
    expect(find.text(S.workshopRemoved), findsOneWidget);
  });

  testWidgets('without workshop.people.manage nothing on the register mutates',
      (tester) async {
    await openRegister(tester, user: noPeopleAdmin);
    expect(find.byType(WorkshopMembersTab), findsOneWidget);
    expect(find.text(S.workshopAddMember), findsNothing);
    expect(find.text(S.workshopAddGuest), findsNothing);

    // Attendance is a different key, and this account still holds it.
    await tester.tap(find.text('نور الحسن'));
    await settlePlatform(tester);
    expect(find.text(S.checkedIn), findsWidgets);
    expect(find.text(S.workshopRemoveParticipant), findsNothing);
  });

  testWidgets('with the workshops feature off the register is unreachable',
      (tester) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(mainAdmin);
    container.read(platformTenantStoreProvider).updateFeature(
        mainAdmin.saasTenantId!, TenantFeatureKey.workshops, false);
    container.read(tenantFeatureRevisionProvider.notifier).changed();
    final router = await bootPlatform(tester, container, height: 1200);

    router.go(route);
    await settlePlatform(tester);
    expect(find.byType(WorkshopMembersTab), findsNothing);
    expect(find.byType(FeatureDisabledPage), findsOneWidget);
  });

  testWidgets(
      'a write that cannot reach the server says so and changes nothing',
      (tester) async {
    await openRegister(tester, overrides: [
      workshopRepositoryProvider.overrideWith((ref) => _OfflineWrites()),
    ]);

    await pickCandidate(tester, candidate);

    expect(find.text(S.offlineTitle), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(WorkshopMembersTab),
        matching: find.text(candidate),
      ),
      findsNothing,
    );
  });

  testWidgets('an organiser is added to the workshop team', (tester) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(mainAdmin);
    final router = await bootPlatform(tester, container, height: 1200);
    router.go('/workshop/$workshop/team');
    await settlePlatform(tester);
    expect(find.byType(WorkshopTeamTab), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, S.workshopAddOrganizer));
    await settlePlatform(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(WorkshopMemberPicker),
        matching: find.byType(TextField),
      ),
      candidate,
    );
    await settlePlatform(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(WorkshopMemberPicker),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(WorkshopMemberPicker),
        matching: find.byType(FilledButton),
      ),
    );
    await settlePlatform(tester);

    expect(
      find.descendant(
        of: find.byType(WorkshopTeamTab),
        matching: find.text(candidate),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a workshop is created from the list and opens on its detail',
      (tester) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(mainAdmin);
    final router = await bootPlatform(tester, container, height: 1200);
    router.go('/workshop/new');
    await settlePlatform(tester);
    expect(find.byType(WorkshopEditPage), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, S.workshopNamePlaceholder),
        'ورشة الاختبار');
    await tester.enterText(
        find.widgetWithText(TextFormField, S.workshopLocationPlaceholder),
        'قاعة الاختبار');
    await tester.enterText(
        find.widgetWithText(TextFormField, S.workshopCapacityPlaceholder), '8');
    await tester.pump();

    // The date is mandatory: saving without one says so rather than guessing.
    await tester.tap(find.widgetWithText(FilledButton, S.save));
    await settlePlatform(tester);
    expect(find.text(S.workshopInvalidDate), findsOneWidget);

    await tester.tap(find.text(S.pickDate));
    await settlePlatform(tester);
    await tester.tap(find.text('OK').first);
    await settlePlatform(tester);
    await tester.tap(find.text('OK').first);
    await settlePlatform(tester);

    await tester.tap(find.widgetWithText(FilledButton, S.save));
    await settlePlatform(tester);

    expect(find.text(S.savedOk), findsOneWidget);

    router.go('/workshop');
    await settlePlatform(tester);
    await tester.tap(find.text(S.filterAll));
    await settlePlatform(tester);
    expect(find.text('ورشة الاختبار'), findsOneWidget);
  });

  testWidgets('archiving closes the workshop to changes until it is restored',
      (tester) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(mainAdmin);
    final router = await bootPlatform(tester, container, height: 1200);
    router.go(route);
    await settlePlatform(tester);
    expect(find.text(S.workshopAddMember), findsOneWidget);

    await tester.tap(find.byIcon(Icons.archive_outlined));
    await settlePlatform(tester);
    // The shared confirmation states what archiving changes and what it
    // leaves alone, and puts the confirm on a filled warning button rather
    // than a `TextButton` at the same weight as «إلغاء».
    expect(find.text(S.workshopArchiveChange), findsOneWidget);
    expect(find.text(S.workshopArchiveUnchanged), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, S.workshopArchive));
    await settlePlatform(tester);

    expect(find.text(S.workshopArchivedBanner), findsOneWidget);
    expect(find.text(S.workshopAddMember), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.unarchive_outlined));
    await settlePlatform(tester);
    expect(find.text(S.workshopArchivedBanner), findsNothing);
    expect(find.text(S.workshopAddMember), findsOneWidget);
  });

  testWidgets('the register and its picker hold at 320dp and 1.6x text',
      (tester) async {
    await openRegister(tester, width: 320, textScale: 1.6);
    expect(find.byType(WorkshopMembersTab), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, S.workshopAddMember));
    await settlePlatform(tester);
    expect(find.byType(WorkshopMemberPicker), findsOneWidget);
  });

  testWidgets('search scans participants and has a distinct no-results state',
      (tester) async {
    await openRegister(tester);
    final search = find.byKey(const Key('workshop-participants-search'));
    expect(search, findsOneWidget);

    await tester.enterText(search, 'نور');
    await settlePlatform(tester);
    expect(find.text('نور الحسن'), findsOneWidget);
    expect(find.text('أحمد كنعان'), findsNothing);

    await tester.enterText(search, 'اسم غير موجود');
    await settlePlatform(tester);
    expect(
      find.byKey(const Key('workshop-participants-no-results')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('workshop-participants-empty')), findsNothing);

    await tester.tap(find.text(S.clearWorkshopParticipantFilters));
    await settlePlatform(tester);
    expect(
      find.byKey(const Key('workshop-participants-no-results')),
      findsNothing,
    );
    expect(find.text('أحمد كنعان'), findsOneWidget);
  });

  testWidgets('a genuinely empty register is not described as no matches',
      (tester) async {
    await openRegister(tester, workshopId: 'w6');
    expect(
        find.byKey(const Key('workshop-participants-empty')), findsOneWidget);
    expect(
      find.byKey(const Key('workshop-participants-no-results')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('workshop-participants-search')),
      findsNothing,
    );
  });
}
