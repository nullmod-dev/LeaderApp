import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/customer_demo_controller.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/customer_demo.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/demo/domain/demo_seed.dart';
import 'package:mtm/features/shell/main_shell.dart';
import 'package:mtm/features/workshop/presentation/tabs/workshop_members_tab.dart';
import 'package:mtm/features/workshop/presentation/widgets/workshop_people.dart';
import 'package:mtm/l10n/strings.dart';

import '../platform/platform_harness.dart';

/// The Customer Demo as a person meets it: the real application, opened on
/// real screens, filled with the sample workspace — and the few places it is
/// deliberately not allowed to go.
void main() {
  Future<GoRouter> bootDemo(
    WidgetTester tester, {
    double width = 400,
    double textScale = 1,
  }) async {
    ignoreKnownTenantComplaints();
    final container = platformContainer(customerDemoUser, overrides: [
      sessionAccessOverrideProvider
          .overrideWith((ref) => const SessionAccess(demo: DemoMode.active)),
    ]);
    return bootPlatform(
      tester,
      container,
      width: width,
      height: 1200,
      textScale: textScale,
    );
  }

  testWidgets('the trial opens the real app shell, not a summary page',
      (tester) async {
    final router = await bootDemo(tester);

    expect(locationOf(router), '/home');
    expect(find.byType(MainShell), findsOneWidget);
    // And it says what it is, on every screen, with the exit beside it.
    expect(find.text(S.demoTrialNotice), findsOneWidget);
    expect(find.byKey(const Key('demo-exit')), findsOneWidget);
  });

  testWidgets('the operational modules open on the sample workspace',
      (tester) async {
    final router = await bootDemo(tester);

    router.go('/detachment');
    await settlePlatform(tester);
    expect(find.text('مفرزة المدينة'), findsOneWidget);
    expect(find.text('مفرزة الميدان'), findsOneWidget);

    // Exactly two workshops, and no tenant fixture among them.
    router.go('/workshop');
    await settlePlatform(tester);
    expect(find.text('الإسعاف الأولي للمتطوعين'), findsOneWidget);
    await tester.tap(find.text(S.filterAll));
    await settlePlatform(tester);
    expect(find.text('التعامل مع الإصابات الميدانية'), findsOneWidget);
    expect(find.text('الإسعاف الأولي المتقدم'), findsNothing);

    // Team, schedule, stock and statistics, all from the demo repositories.
    router.go('/detachment/${DemoSeed.cityDetachment}/team');
    await settlePlatform(tester);
    expect(find.text('سامر الحاج'), findsWidgets);

    router.go('/detachment/${DemoSeed.cityDetachment}/shifts');
    await settlePlatform(tester);
    expect(
        locationOf(router), '/detachment/${DemoSeed.cityDetachment}/shifts');
    expect(tester.takeException(), isNull);

    router.go('/detachment/${DemoSeed.cityDetachment}/storage');
    await settlePlatform(tester);
    expect(find.text('ضمادات معقمة'), findsWidgets);

    router.go('/detachment/${DemoSeed.cityDetachment}/stats');
    await settlePlatform(tester);
    expect(locationOf(router), '/detachment/${DemoSeed.cityDetachment}/stats');
  });

  testWidgets('workshop people can be managed inside the trial',
      (tester) async {
    final router = await bootDemo(tester);
    router.go('/workshop/dw1/members');
    await settlePlatform(tester);
    expect(find.byType(WorkshopMembersTab), findsOneWidget);
    expect(find.text('باسل نعمة'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, S.workshopAddMember));
    await settlePlatform(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(WorkshopMemberPicker),
        matching: find.byType(TextField),
      ),
      'باسل نعمة',
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

    expect(find.text('باسل نعمة'), findsOneWidget);
  });

  testWidgets('settings offers appearance but no real account or org screen',
      (tester) async {
    final router = await bootDemo(tester);
    router.go('/more');
    await settlePlatform(tester);

    expect(find.text(S.sectionThemesPerformance), findsOneWidget);
    expect(find.text(S.settingsNotifications), findsOneWidget);
    // Not a real account, and not an organisation.
    expect(find.text(S.settingsSecurity), findsNothing);
    expect(find.text(S.settingsOrg), findsNothing);
    expect(find.text(S.settingsPlan), findsNothing);
    expect(find.text(S.simpleAdminsTitle), findsNothing);
    // The trial is ended, not signed out of.
    expect(find.text(S.signOut), findsNothing);
    expect(find.text(S.customerDemoExit), findsWidgets);
  });

  testWidgets('ending the trial returns to sign-in', (tester) async {
    final router = await bootDemo(tester);

    await tester.tap(find.byKey(const Key('demo-exit')));
    await settlePlatform(tester);
    expect(find.text(S.demoExitConfirm), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, S.customerDemoExit));
    await settlePlatform(tester);

    expect(locationOf(router), '/login');
    expect(find.byType(MainShell), findsNothing);
  });

  testWidgets('the trial holds at 320dp and 1.6x text in RTL', (tester) async {
    final router = await bootDemo(tester, width: 320, textScale: 1.6);
    expect(find.byType(MainShell), findsOneWidget);
    expect(tester.takeException(), isNull);

    for (final location in ['/workshop', '/detachment', '/more']) {
      router.go(location);
      await settlePlatform(tester);
      expect(tester.takeException(), isNull, reason: location);
    }
  });

  test('a globally disabled demo starts no session at all', () async {
    final container = ProviderContainer(overrides: [
      customerDemoPolicyProvider
          .overrideWithValue(const CustomerDemoPolicy(available: false)),
    ]);
    addTearDown(container.dispose);

    final result =
        await container.read(customerDemoControllerProvider.notifier).start();
    expect(result, isA<Failure<AuthUser>>());
    expect((result as Failure<AuthUser>).code, 'demo_unavailable');
    // No demo envelope means no demo workspace and no demo surface.
    expect(container.read(sessionAccessProvider).isDemo, isFalse);
  });
}
