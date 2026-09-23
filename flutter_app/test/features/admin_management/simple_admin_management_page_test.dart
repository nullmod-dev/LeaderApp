import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/admin_management/data/simple_admin_providers.dart';
import 'package:mtm/features/admin_management/data/simple_admin_store.dart';
import 'package:mtm/features/admin_management/domain/simple_admin_models.dart';
import 'package:mtm/features/admin_management/presentation/simple_admin_management_page.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/mock_onboarding_repository.dart';
import 'package:mtm/features/auth/data/onboarding_controller.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/l10n/strings.dart';

void main() {
  // The seeded invitation expires seven days after this instant, so the
  // screen's "now" is pinned to it through `clockProvider`. Reading the real
  // clock here would make every assertion about a pending invitation expire
  // a week after the fixture was written.
  final now = DateTime.utc(2026, 9, 12, 12);

  testWidgets(
      'invite form selects capabilities and creates no password or account',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = SimpleAdminStore.seeded(now);
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) async => _mainAdmin),
      clockProvider.overrideWithValue(() => now),
      simpleAdminStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/manager/invite',
      routes: [
        GoRoute(
          path: '/manager',
          builder: (_, __) => const SimpleAdminManagementPage(),
          routes: [
            GoRoute(
              path: 'invite',
              builder: (_, __) => const SimpleAdminInvitePage(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(PaletteId.medical),
        routerConfig: router,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('simple-admin-invite-form')), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(
      tester.widgetList<TextField>(find.byType(TextField)).every(
            (field) => !field.obscureText,
          ),
      isTrue,
      reason: 'the issuer never chooses or sees a password',
    );
    expect(S.simpleAdminNoPasswordNote, contains('كلمة مرور'),
        reason: 'the form explains that onboarding owns password creation');
    expect(find.byKey(const Key('capability-admin.manage')), findsNothing);
    expect(find.byKey(const Key('capability-detachment.view')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('simple-admin-name')), 'مدير مدعو');
    await tester.enterText(
        find.byKey(const Key('simple-admin-email')), 'invited@example.org');
    final send = find.byKey(const Key('simple-admin-send-invitation'));
    await tester.scrollUntilVisible(
      send,
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(send);
    await tester.pumpAndSettle();

    final invitation = store.invitations.values
        .where((item) => item.email == 'invited@example.org')
        .single;
    expect(invitation.tenantId, 'saas_hilal');
    expect(invitation.capabilities.global, isNotEmpty);
    expect(store.accounts.values.map((account) => account.email),
        isNot(contains(invitation.email)));
    final onboarding = container.read(onboardingRepositoryProvider)
        as MockOnboardingRepository;
    final authorization = onboarding.additionalAuthorizations
        .where((item) => item.id == invitation.id)
        .single;
    expect(authorization.role, AuthRole.admin);
    expect(authorization.tenantId, invitation.tenantId);
    expect(authorization.email, invitation.email);
    expect(authorization.capabilities, invitation.capabilities);
  });

  testWidgets(
      'Point 18B: a Main Admin sees admins and invitations, edits a grant '
      'and cancels an invitation', (tester) async {
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = SimpleAdminStore.seeded(now);
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) async => _mainAdmin),
      clockProvider.overrideWithValue(() => now),
      simpleAdminStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: SimpleAdminManagementPage.routePath,
      routes: [
        GoRoute(
          path: SimpleAdminManagementPage.routePath,
          builder: (_, __) => const SimpleAdminManagementPage(),
          routes: [
            GoRoute(
              path: ':accountId/capabilities',
              builder: (_, state) => SimpleAdminCapabilitiesPage(
                  accountId: state.pathParameters['accountId']!),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark(PaletteId.medical),
        routerConfig: router,
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
    ));
    await tester.pumpAndSettle();

    // Account and invitation state, each in words — never colour alone.
    final seeded = store.accounts['u_demo_simple']!;
    expect(find.text(seeded.name), findsOneWidget);
    expect(find.text(S.simpleAdminActive), findsOneWidget);
    expect(
        find.text('${seeded.capabilities.global.length}'
            '${S.simpleAdminCapabilityCountSuffix}'),
        findsOneWidget);
    expect(find.text('noura@hilal-medical.org'), findsOneWidget);
    expect(find.text(S.simpleAdminInvitationPending), findsOneWidget);

    // Edit the grant: grouped, localized, no authority key on offer.
    await tester.tap(find.byTooltip(S.simpleAdminEditCapabilities));
    await tester.pumpAndSettle();
    expect(find.text(S.simpleAdminGroupTeam), findsOneWidget);
    expect(find.text(S.simpleAdminGroupShifts), findsOneWidget);
    expect(
        find.byKey(const Key('capability-${Cap.adminManage}')), findsNothing);
    expect(find.byKey(const Key('capability-${Cap.orgEdit}')), findsNothing);
    expect(find.text(Cap.memberContactView), findsNothing,
        reason: 'raw keys are never the user-facing label');
    await tester
        .tap(find.byKey(const Key('capability-${Cap.memberContactView}')));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('simple-admin-save-capabilities'));
    await tester.scrollUntilVisible(save, 400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(store.accounts['u_demo_simple']!.capabilities.global,
        isNot(contains(Cap.memberContactView)));
    expect(find.byType(SimpleAdminManagementPage), findsOneWidget);

    // Cancel the pending invitation, behind a confirmation.
    await tester.tap(find.byKey(const Key('cancel-invitation-az_hilal_admin')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(FilledButton, S.simpleAdminCancelInvitation));
    await tester.pumpAndSettle();
    expect(store.invitations['az_hilal_admin']!.status,
        SimpleAdminInvitationStatus.cancelled);
    expect(find.text(S.simpleAdminInvitationCancelledStatus), findsOneWidget);
    expect(find.byKey(const Key('cancel-invitation-az_hilal_admin')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320dp at 1.6x text stays scrollable without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = SimpleAdminStore.seeded(now);
    final container = ProviderContainer(overrides: [
      currentUserProvider.overrideWith((ref) async => _mainAdmin),
      clockProvider.overrideWithValue(() => now),
      simpleAdminStoreProvider.overrideWithValue(store),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child:
              Directionality(textDirection: TextDirection.rtl, child: child!),
        ),
        home: const SimpleAdminManagementPage(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('simple-admin-management')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Point 18B: the grouped capability editor fits 320dp at 1.6x text',
      (tester) async {
    await _pumpCapabilities320(tester, now);
    expect(find.text(S.simpleAdminGroupTeam), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('simple-admin-save-capabilities')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpCapabilities320(WidgetTester tester, DateTime now) async {
  tester.view.physicalSize = const Size(320, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    currentUserProvider.overrideWith((ref) async => _mainAdmin),
    clockProvider.overrideWithValue(() => now),
    simpleAdminStoreProvider.overrideWithValue(SimpleAdminStore.seeded(now)),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.light(PaletteId.medical, eyeProtect: true),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.6)),
        child: Directionality(textDirection: TextDirection.rtl, child: child!),
      ),
      home: const SimpleAdminCapabilitiesPage(accountId: 'u_demo_simple'),
    ),
  ));
  await tester.pumpAndSettle();
}

const _mainAdmin = AuthUser(
  id: 'u_main',
  name: 'مدير رئيسي',
  email: 'main@mtm.org',
  role: AuthRole.mainAdmin,
  saasTenantId: 'saas_hilal',
  capabilities: Capabilities(global: Cap.all),
  orgName: 'الهلال الطبي',
);
