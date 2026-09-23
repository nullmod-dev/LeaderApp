import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/mock_auth_repository.dart';
import 'package:mtm/features/auth/data/mock_onboarding_repository.dart';
import 'package:mtm/features/auth/data/onboarding_controller.dart';
import 'package:mtm/features/auth/presentation/account_setup_page.dart';
import 'package:mtm/features/auth/presentation/email_verification_page.dart';
import 'package:mtm/features/auth/presentation/link_team_page.dart';
import 'package:mtm/features/auth/presentation/signup_page.dart';
import 'package:mtm/features/shell/main_shell.dart';
import 'package:mtm/features/auth/presentation/login_page.dart';
import 'package:mtm/l10n/strings.dart';

import '../../entry_settle.dart';

/// Point 17B — the production onboarding screens, exercised through the real
/// app router and real widgets (never the Point 17A holding pages, which this
/// point retired), against the **real, unoverridden**
/// `onboardingRepositoryProvider` — the same `OnboardingFixtures` and the same
/// `sessionIssued` bridge into `currentUser()` that `main.dart` runs.
///
/// The one override every test needs: `authRepositoryProvider` with
/// `demoAccountsEnabled: false`. Without it every container boots into the
/// development Main Admin persona (`PersistentDemoSessionStore`'s seed —
/// "what every screen, mock and existing test is written against"), which
/// short-circuits the classifier before it ever consults the onboarding
/// journey (`AuthGate.signedIn` outranks `entry`; see
/// `core/startup/startup_destination.dart`).
void main() {
  Future<(ProviderContainer, GoRouter)> boot(WidgetTester tester) async {
    final inherited = FlutterError.onError;
    FlutterError.onError = (details) {
      final report = details.toString();
      if (report.contains('overflowed')) return;
      inherited?.call(details);
    };
    addTearDown(() => FlutterError.onError = inherited);
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [
      authRepositoryProvider
          .overrideWithValue(MockAuthRepository(demoAccountsEnabled: false)),
    ]);
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(PaletteId.medical),
        builder: (context, child) => Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ));
    // Bounded: the app opens on the entry surface, whose ambient pulse loops
    // for as long as it is on screen.
    await settleEntry(tester);
    return (container, router);
  }

  String at(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  group('signup', () {
    testWidgets('is reachable from /login', (tester) async {
      final (_, router) = await boot(tester);
      expect(at(router), '/login');
      await tester.tap(find.text(S.createAccount));
      await tester.pumpAndSettle();
      // `LoginPage` reaches it with `context.push`, which layers a page onto
      // the stack without changing `currentConfiguration.uri` (that stays at
      // the base `go`-established location) — so the signal that it worked
      // is the pushed widget, not the reported location.
      expect(find.byType(SignupPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a small phone at a large text scale', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final (_, router) = await boot(tester);
      router.go('/signup');
      await tester.pumpAndSettle();
      expect(find.byType(SignupPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('collects only email and password — no tenant/role/Team Code',
        (tester) async {
      final (_, router) = await boot(tester);
      router.go('/signup');
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.textContaining('MTM-'), findsNothing);
    });
  });

  group('email/password → verify → link → setup, through the real forms', () {
    testWidgets('the initial Main Admin seat: Team Code is required and typed',
        (tester) async {
      final (container, router) = await boot(tester);

      router.go('/signup');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('signup-email')),
          OnboardingFixtures.nabdMainAdminEmail);
      await tester.enterText(
          find.byKey(const Key('signup-password')), 'a-good-password');
      await tester.tap(find.text(S.signUpAction));
      await tester.pumpAndSettle();
      expect(at(router), '/verify-email');
      expect(find.byType(EmailVerificationPage), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('verification-code')), kMockVerificationCode);
      await tester.tap(find.text(S.verifyEmailAction));
      await tester.pumpAndSettle();
      expect(at(router), '/link-team');
      expect(find.byType(LinkTeamPage), findsOneWidget);

      // Point 18B — verified and unlinked: the Team/Demo decision first.
      expect(find.byKey(const Key('team-code')), findsNothing);
      await tester.tap(find.byKey(const Key('onboarding-choice-team')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('team-code')), OnboardingFixtures.nabdCode);
      await tester.tap(find.text(S.linkTeamAction));
      await tester.pumpAndSettle();
      expect(at(router), '/account-setup');
      expect(find.byType(AccountSetupPage), findsOneWidget);
      // Prefilled from the seat authorization's suggested name.
      expect(find.text('هدى الشمري'), findsOneWidget);
      expect(find.text(S.roleMainAdmin), findsOneWidget);

      await tester.tap(find.text(S.completeSetupAction));
      await tester.pumpAndSettle();
      expect(at(router), '/home');
      expect(find.byType(MainShell), findsOneWidget);
      expect(container.read(capabilitiesProvider).canIn(null, Cap.adminManage),
          isTrue);
    });

    testWidgets('a Simple Admin invitation never shows the Team Code screen',
        (tester) async {
      final (container, router) = await boot(tester);

      router.go('/signup');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('signup-email')),
          OnboardingFixtures.hilalInviteeEmail);
      await tester.enterText(
          find.byKey(const Key('signup-password')), 'a-good-password');
      await tester.tap(find.text(S.signUpAction));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('verification-code')), kMockVerificationCode);
      await tester.tap(find.text(S.verifyEmailAction));
      await tester.pumpAndSettle();

      // Straight to setup: /link-team is never visited.
      expect(at(router), '/account-setup');
      expect(find.byType(LinkTeamPage), findsNothing);
      expect(find.text('فرق الهلال الطبية'), findsWidgets);
      expect(find.text(S.roleSimpleAdmin), findsOneWidget);

      await tester.tap(find.text(S.completeSetupAction));
      await tester.pumpAndSettle();
      expect(at(router), '/home');
      expect(container.read(capabilitiesProvider).canIn(null, Cap.memberInvite),
          isTrue);
      expect(container.read(capabilitiesProvider).canIn(null, Cap.adminManage),
          isFalse);
    });

    testWidgets(
        'Point 17C: an invitee stranded on /link-team checks its invitation '
        'instead of needing a Team Code', (tester) async {
      final (container, router) = await boot(tester);
      final onboarding = container.read(onboardingRepositoryProvider)
          as MockOnboardingRepository;
      // The invitation cannot link while its tenant is paused, so the verified
      // invitee lands on the Team Code screen it has no code for.
      onboarding.setTenantStatus(
          OnboardingFixtures.hilalTenantId, SaasTenantStatus.suspended);

      router.go('/signup');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('signup-email')),
          OnboardingFixtures.hilalInviteeEmail);
      await tester.enterText(
          find.byKey(const Key('signup-password')), 'a-good-password');
      await tester.tap(find.text(S.signUpAction));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('verification-code')), kMockVerificationCode);
      await tester.tap(find.text(S.verifyEmailAction));
      await tester.pumpAndSettle();
      expect(at(router), '/link-team');
      expect(find.text(S.teamLinkInvitationHint), findsOneWidget);

      await tester.tap(find.byKey(const Key('check-invitation')));
      await tester.pumpAndSettle();
      expect(at(router), '/link-team');
      expect(find.text(S.noInvitationYet), findsOneWidget);

      onboarding.setTenantStatus(
          OnboardingFixtures.hilalTenantId, SaasTenantStatus.active);
      await tester.tap(find.byKey(const Key('check-invitation')));
      await tester.pumpAndSettle();
      expect(at(router), '/account-setup');
      expect(find.text(S.roleSimpleAdmin), findsOneWidget);
    });
  });

  group('returning user', () {
    testWidgets('a finished account signs in straight to its surface, no steps',
        (tester) async {
      final (_, router) = await boot(tester);

      final email = find.byKey(LoginField.keyFor(S.emailLabel));
      await tester.enterText(email, OnboardingFixtures.readyEmail);
      final password = find.byKey(LoginField.keyFor(S.passwordLabel));
      await tester.enterText(password, kMockFixturePassword);
      await tester.ensureVisible(find.text(S.signIn));
      await settleEntry(tester);
      await tester.tap(find.text(S.signIn));
      await settleEntry(tester);

      // `readyEmail` is seeded with no capability grant at all — a valid
      // authorization outcome (`tenantNoAccess`), not a step of the journey.
      // The point this proves is what it does *not* show: no verification
      // code, no Team Code, no setup form.
      expect(at(router), '/access-not-assigned');
      expect(find.byType(SignupPage), findsNothing);
      expect(find.byType(EmailVerificationPage), findsNothing);
      expect(find.byType(LinkTeamPage), findsNothing);
      expect(find.byType(AccountSetupPage), findsNothing);
    });
  });

  group('320dp at 1.6× text — every step fits', () {
    testWidgets('verify-email, link-team and account-setup', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final (_, router) = await boot(tester);
      router.go('/signup');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('signup-email')),
          OnboardingFixtures.nabdMainAdminEmail);
      await tester.enterText(
          find.byKey(const Key('signup-password')), 'a-good-password');
      await tester.tap(find.text(S.signUpAction));
      await tester.pumpAndSettle();
      expect(find.byType(EmailVerificationPage), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.enterText(
          find.byKey(const Key('verification-code')), kMockVerificationCode);
      await tester.tap(find.text(S.verifyEmailAction));
      await tester.pumpAndSettle();
      expect(find.byType(LinkTeamPage), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('onboarding-choice-team')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(
          find.byKey(const Key('team-code')), OnboardingFixtures.nabdCode);
      await tester.tap(find.text(S.linkTeamAction));
      await tester.pumpAndSettle();
      expect(find.byType(AccountSetupPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
