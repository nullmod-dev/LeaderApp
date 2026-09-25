import 'dart:ui' show Tristate;

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
import 'package:mtm/features/workshop/presentation/workshop_member_form_page.dart';
import 'package:mtm/features/workshop/presentation/widgets/workshop_people.dart';
import 'package:mtm/l10n/strings.dart';

import '../platform/platform_harness.dart';

/// Managing a workshop's people inside the real app: team members on
/// «الفريق وأدواره», volunteers on «المتطوعون والزوار», the «إضافة عضو» and
/// «إضافة متطوع» pages, the organisers left from before, and the gates that
/// decide whether any of it is offered. Nobody is picked from the roster.

/// A workshop repository whose writes never land, so the screen has to say so.
class _OfflineWrites extends MockWorkshopRepository {
  _OfflineWrites() : super(team: MockTeamRepository());

  @override
  Future<Result<WorkshopParticipant>> addTeamMember(
    String workshopId, {
    required String name,
    required WorkshopRole role,
    required bool paid,
  }) async =>
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
    String tab = 'team',
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
    router.go('/workshop/$workshopId/$tab');
    await settlePlatform(tester);
  }

  Finder onPage(Finder matching) => find.descendant(
        of: find.byType(WorkshopMemberFormPage),
        matching: matching,
      );

  /// The row a person's name sits in on the register.
  Finder rowOf(String name) => find.ancestor(
        of: find.text(name),
        matching: find.byType(WorkshopPersonRow),
      );

  Finder inRow(String name, Finder matching) =>
      find.descendant(of: rowOf(name), matching: matching);

  Future<void> openMemberPage(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, S.workshopAddMember));
    await settlePlatform(tester);
    expect(find.byType(WorkshopMemberFormPage), findsOneWidget);
  }

  testWidgets('a team member is added on its own page: name, role and paid',
      (tester) async {
    await openRegister(tester);
    expect(find.byType(WorkshopTeamTab), findsOneWidget);
    await openMemberPage(tester);
    expect(find.text(S.workshopMemberFormNew), findsOneWidget);
    // Nobody is picked from the roster any more: a typed form, no checkboxes.
    expect(find.byType(Checkbox), findsNothing);

    await tester.enterText(
        onPage(find.byKey(const Key('workshop-member-name'))), 'سارة الحسيني');
    // The role starts at «عضو»; choosing «مدرب» is what gets saved.
    expect(
      tester
          .getSemantics(onPage(find.text(S.workshopRoleMember)))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    await tester.tap(onPage(find.text(S.workshopRoleTrainer)));
    await tester.pump();
    await tester.tap(onPage(find.byKey(const Key('workshop-paid-switch'))));
    await tester.pump();
    await tester.tap(onPage(find.widgetWithText(FilledButton, S.save)));
    await settlePlatform(tester);

    expect(find.byType(WorkshopMemberFormPage), findsNothing);
    expect(find.text(S.workshopAdded), findsOneWidget);
    expect(find.text('سارة الحسيني'), findsOneWidget);
    expect(inRow('سارة الحسيني', find.text(S.workshopRoleTrainer)),
        findsOneWidget);
    expect(inRow('سارة الحسيني', find.text(S.paymentPaid)), findsOneWidget);
    expect(inRow('سارة الحسيني', find.text(S.notCheckedIn)), findsOneWidget);
  });

  testWidgets('an unpaid team member shows the red chip; a name is required',
      (tester) async {
    await openRegister(tester);
    await openMemberPage(tester);

    // Saving with no name says so and stays on the page.
    await tester.tap(onPage(find.widgetWithText(FilledButton, S.save)));
    await settlePlatform(tester);
    expect(find.text(S.required), findsOneWidget);
    expect(find.byType(WorkshopMemberFormPage), findsOneWidget);

    await tester.enterText(
        onPage(find.byKey(const Key('workshop-member-name'))), 'باسم الدعم');
    await tester.tap(onPage(find.text(S.workshopRoleSupport)));
    await tester.pump();
    await tester.tap(onPage(find.widgetWithText(FilledButton, S.save)));
    await settlePlatform(tester);

    expect(
        inRow('باسم الدعم', find.text(S.workshopRoleSupport)), findsOneWidget);
    expect(inRow('باسم الدعم', find.text(S.paymentUnpaid)), findsOneWidget);
  });

  testWidgets('a team member is edited from their sheet', (tester) async {
    await openRegister(tester);
    await tester.tap(find.text('رنا سعيد')); // p3, a plain member
    await settlePlatform(tester);
    await tester.tap(find.text(S.workshopEditMember));
    await settlePlatform(tester);

    expect(find.text(S.workshopMemberFormEdit), findsOneWidget);
    // Seeded once from the stored line.
    expect(onPage(find.text('رنا سعيد')), findsOneWidget);
    await tester.tap(onPage(find.text(S.workshopRoleManagement)));
    await tester.pump();
    await tester.tap(onPage(find.widgetWithText(FilledButton, S.save)));
    await settlePlatform(tester);

    expect(find.byType(WorkshopMemberFormPage), findsNothing);
    expect(find.text(S.savedOk), findsOneWidget);
    expect(
        inRow('رنا سعيد', find.text(S.workshopRoleManagement)), findsOneWidget);
  });

  testWidgets('the edit page for a line that is not a team member says so',
      (tester) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(mainAdmin);
    final router = await bootPlatform(tester, container, height: 1200);
    // p4 is a visitor, not a team member.
    router.go('/workshop/$workshop/members/p4/edit');
    await settlePlatform(tester);
    expect(find.byType(WorkshopMemberFormPage), findsOneWidget);
    expect(find.byKey(const Key('workshop-member-form-not-found')),
        findsOneWidget);
  });

  testWidgets('without workshop.people.manage the page is not reachable',
      (tester) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(noPeopleAdmin);
    final router = await bootPlatform(tester, container, height: 1200);
    router.go('/workshop/$workshop/members/new');
    await settlePlatform(tester);
    expect(find.byType(WorkshopMemberFormPage), findsNothing);
    expect(locationOf(router), isNot('/workshop/$workshop/members/new'));
  });

  testWidgets('team members and volunteers live on separate tabs',
      (tester) async {
    await openRegister(tester);
    expect(find.text('أحمد كنعان'), findsOneWidget);
    expect(find.text('زيد الحلبي'), findsNothing);
    expect(find.byKey(const Key('workshop-add-member')), findsOneWidget);
    expect(find.byKey(const Key('workshop-add-volunteer')), findsNothing);

    await tester.tap(find.text(S.workshopMembers));
    await settlePlatform(tester);
    expect(find.byType(WorkshopMembersTab), findsOneWidget);
    expect(find.text('زيد الحلبي'), findsOneWidget);
    expect(find.text('أحمد كنعان'), findsNothing);
    expect(inRow('زيد الحلبي', find.text(S.kindGuest)), findsOneWidget);
    expect(find.byKey(const Key('workshop-add-volunteer')), findsOneWidget);
    expect(find.byKey(const Key('workshop-add-member')), findsNothing);
  });

  testWidgets('a volunteer is added on its own page: name and paid, no role',
      (tester) async {
    await openRegister(tester, tab: 'members');
    await tester.tap(find.widgetWithText(FilledButton, S.workshopAddVolunteer));
    await settlePlatform(tester);

    expect(find.byType(WorkshopMemberFormPage), findsOneWidget);
    expect(onPage(find.text(S.workshopAddVolunteer)), findsOneWidget);
    expect(onPage(find.text(S.workshopMemberRole)), findsNothing);
    expect(
        onPage(find.byKey(const Key('workshop-paid-switch'))), findsOneWidget);
    await tester.enterText(
        onPage(find.byKey(const Key('workshop-member-name'))), 'متطوع جديد');
    await tester.tap(onPage(find.widgetWithText(FilledButton, S.save)));
    await settlePlatform(tester);

    expect(find.byType(WorkshopMemberFormPage), findsNothing);
    expect(find.text(S.workshopAdded), findsOneWidget);
    expect(inRow('متطوع جديد', find.text(S.paymentUnpaid)), findsOneWidget);
    expect(inRow('متطوع جديد', find.text(S.kindGuest)), findsOneWidget);
  });

  testWidgets(
      'without workshop.people.manage the volunteer page is not reachable',
      (tester) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(noPeopleAdmin);
    final router = await bootPlatform(tester, container, height: 1200);
    router.go('/workshop/$workshop/volunteers/new');
    await settlePlatform(tester);
    expect(find.byType(WorkshopMemberFormPage), findsNothing);
    expect(locationOf(router), isNot('/workshop/$workshop/volunteers/new'));
  });

  testWidgets('the unpaid filter narrows the part and carries its count',
      (tester) async {
    await openRegister(tester, tab: 'members');
    // w1's visitors: two paid, one unpaid (خالد عساف).
    final unpaid = find.byKey(const Key('workshop-filter-unpaid'));
    expect(
      find.descendant(
          of: unpaid, matching: find.textContaining(S.paymentUnpaid)),
      findsOneWidget,
    );
    expect(find.descendant(of: unpaid, matching: find.textContaining('١')),
        findsOneWidget);
    await tester.tap(unpaid);
    await settlePlatform(tester);
    expect(find.text('خالد عساف'), findsOneWidget);
    expect(find.text('زيد الحلبي'), findsNothing);
  });

  testWidgets('a free workshop shows no payment at all', (tester) async {
    await openRegister(tester, workshopId: 'w4'); // fee 0
    expect(find.text('غادة الحموي'), findsOneWidget);
    expect(find.byKey(const Key('workshop-filter-unpaid')), findsNothing);
    expect(inRow('غادة الحموي', find.text(S.paymentUnpaid)), findsNothing);
  });

  testWidgets('the add page hides the paid switch on a free workshop',
      (tester) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(mainAdmin);
    final router = await bootPlatform(tester, container, height: 1200);
    router.go('/workshop/w6/members/new'); // empty register, fee 10000
    await settlePlatform(tester);
    expect(
        onPage(find.byKey(const Key('workshop-paid-switch'))), findsOneWidget);

    router.go('/workshop/w4/members/new'); // fee 0
    await settlePlatform(tester);
    expect(find.byType(WorkshopMemberFormPage), findsOneWidget);
    expect(onPage(find.byKey(const Key('workshop-paid-switch'))), findsNothing);
  });

  testWidgets('a full workshop refuses on the page and keeps the input',
      (tester) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(mainAdmin);
    final router = await bootPlatform(tester, container, height: 1200);
    router.go('/workshop/w4/members/new'); // 3 seats, 3 taken
    await settlePlatform(tester);
    await tester.enterText(
        onPage(find.byKey(const Key('workshop-member-name'))), 'لا مقعد له');
    await tester.tap(onPage(find.widgetWithText(FilledButton, S.save)));
    await settlePlatform(tester);

    expect(find.text('الورشة ممتلئة.'), findsOneWidget);
    expect(find.byType(WorkshopMemberFormPage), findsOneWidget);
    expect(onPage(find.text('لا مقعد له')), findsOneWidget);
  });

  testWidgets('a register sheet offers came / not coming and paid / unpaid',
      (tester) async {
    await openRegister(tester);
    await tester.tap(find.text('نور الحسن'));
    await settlePlatform(tester);
    final sheet = find.byType(WorkshopPersonActions);
    Finder inSheet(String text) =>
        find.descendant(of: sheet, matching: find.text(text));
    expect(inSheet(S.checkedIn), findsOneWidget);
    expect(inSheet(S.workshopNotComing), findsOneWidget);
    expect(inSheet(S.checkedOut), findsNothing);
    expect(inSheet(S.notCheckedIn), findsNothing);
    expect(inSheet(S.paymentPaid), findsOneWidget);
    expect(inSheet(S.paymentUnpaid), findsOneWidget);
    expect(inSheet(S.paymentUnspecified), findsNothing);

    await tester.tap(inSheet(S.workshopNotComing));
    await settlePlatform(tester);
    expect(inRow('نور الحسن', find.text(S.workshopNotComing)), findsOneWidget);
  });

  testWidgets('an organiser sheet still offers all four attendance choices',
      (tester) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(mainAdmin);
    final router = await bootPlatform(tester, container, height: 1200);
    router.go('/workshop/$workshop/team');
    await settlePlatform(tester);
    // Organisers from before the typed register sit under the team members.
    expect(find.text(S.workshopOrganizersSection), findsOneWidget);
    await tester.ensureVisible(find.text('ليلى ياسين'));
    await settlePlatform(tester);
    await tester.tap(find.text('ليلى ياسين')); // m2, organising w1
    await settlePlatform(tester);
    final sheet = find.byType(WorkshopPersonActions);
    Finder inSheet(String text) =>
        find.descendant(of: sheet, matching: find.text(text));
    expect(inSheet(S.checkedIn), findsOneWidget);
    expect(inSheet(S.checkedOut), findsOneWidget);
    expect(inSheet(S.absent), findsOneWidget);
    expect(inSheet(S.notCheckedIn), findsOneWidget);
    expect(inSheet(S.workshopEditMember), findsNothing);
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
    expect(find.byType(WorkshopTeamTab), findsOneWidget);
    expect(find.text(S.workshopAddMember), findsNothing);

    // Attendance is a different key, and this account still holds it.
    await tester.tap(find.text('نور الحسن'));
    await settlePlatform(tester);
    expect(find.text(S.checkedIn), findsWidgets);
    expect(find.text(S.workshopRemoveParticipant), findsNothing);
  });

  testWidgets('without workshop.people.manage no volunteer can be added',
      (tester) async {
    await openRegister(tester, user: noPeopleAdmin, tab: 'members');
    expect(find.byType(WorkshopMembersTab), findsOneWidget);
    expect(find.text(S.workshopAddVolunteer), findsNothing);
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

    await openMemberPage(tester);
    await tester.enterText(
        onPage(find.byKey(const Key('workshop-member-name'))), candidate);
    await tester.tap(onPage(find.widgetWithText(FilledButton, S.save)));
    await settlePlatform(tester);

    expect(find.text(S.offlineTitle), findsOneWidget);
    // The page stays, with the input kept, and the register is unchanged.
    expect(find.byType(WorkshopMemberFormPage), findsOneWidget);
    expect(onPage(find.text(candidate)), findsOneWidget);
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
    expect(find.text(S.workshopAddVolunteer), findsOneWidget);

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
    expect(find.text(S.workshopAddVolunteer), findsNothing);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.unarchive_outlined));
    await settlePlatform(tester);
    expect(find.text(S.workshopArchivedBanner), findsNothing);
    expect(find.text(S.workshopAddVolunteer), findsOneWidget);
  });

  testWidgets('both tabs and the page hold at 320dp and 1.6x', (tester) async {
    await openRegister(tester, width: 320, textScale: 1.6, tab: 'members');
    expect(find.byType(WorkshopMembersTab), findsOneWidget);
    expect(find.text('خالد عساف'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text(S.workshopTeam));
    await tester.tap(find.text(S.workshopTeam));
    await settlePlatform(tester);
    expect(find.byType(WorkshopTeamTab), findsOneWidget);
    expect(tester.takeException(), isNull);
    await openMemberPage(tester);
    expect(onPage(find.text(S.workshopRoleManagement)), findsOneWidget);
    expect(tester.takeException(), isNull);
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
