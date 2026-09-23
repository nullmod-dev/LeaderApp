import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/customer_demo_controller.dart';
import 'package:mtm/features/auth/data/google_identity_gateway.dart';
import 'package:mtm/features/auth/data/mock_auth_repository.dart';
import 'package:mtm/features/auth/data/mock_onboarding_repository.dart';
import 'package:mtm/features/auth/data/onboarding_controller.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/customer_demo.dart';
import 'package:mtm/features/auth/domain/onboarding_models.dart';
import 'package:mtm/features/auth/presentation/account_setup_page.dart';
import 'package:mtm/features/demo/domain/demo_capabilities.dart';
import 'package:mtm/features/shell/main_shell.dart';
import 'package:mtm/features/auth/presentation/email_verification_page.dart';
import 'package:mtm/features/auth/presentation/google_sign_in_button.dart';
import 'package:mtm/l10n/strings.dart';

import '../../entry_settle.dart';

/// Point 18B — the final login/onboarding UX adjustments:
///
/// - `/login` names its field for what it accepts (email only) and presents
///   Google as a full-width, first-class alternative below the password form;
/// - a **new, verified, unlinked** identity makes one decision — join a team
///   (Team Code) or try MTM (isolated Customer Demo) — reached after the code
///   for a password sign-up and directly for a Google-verified address;
/// - a valid Simple Admin invitation outranks that decision entirely.
///
/// Real router, real screens, the real (unoverridden) onboarding repository;
/// unlike `onboarding_screens_test.dart`'s `boot`, no overflow report is
/// swallowed here, so every step is also a fit check.
void main() {
  const newEmail = 'new.person@example.org';

  Future<(ProviderContainer, GoRouter)> boot(
    WidgetTester tester, {
    double width = 390,
    double height = 1400,
    double textScale = 1,
    ThemeMode mode = ThemeMode.light,
    bool eyeProtect = false,
    double keyboard = 0,
    CustomerDemoPolicy? demoPolicy,
  }) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3;
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      authRepositoryProvider
          .overrideWithValue(MockAuthRepository(demoAccountsEnabled: false)),
      // The development chooser stands in for the platform's own Google
      // account picker, which a widget test has no way to open. It is off by
      // default on a phone platform — see `googleDevelopmentChooserProvider`
      // — so a test that drives a Google identity asks for it by name.
      googleDevelopmentChooserProvider.overrideWithValue(true),
      if (demoPolicy != null)
        customerDemoPolicyProvider.overrideWithValue(demoPolicy),
    ]);
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light(PaletteId.medical, eyeProtect: eyeProtect),
        darkTheme: AppTheme.dark(PaletteId.medical, eyeProtect: eyeProtect),
        themeMode: mode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    ));
    await settleEntry(tester);
    return (container, router);
  }

  String at(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  final choiceTeam = find.byKey(const Key('onboarding-choice-team'));
  final choiceDemo = find.byKey(const Key('onboarding-choice-demo'));
  final teamCode = find.byKey(const Key('team-code'));

  Future<void> tapVisible(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await settleEntry(tester);
    await tester.tap(target);
    await settleEntry(tester);
  }

  Future<void> signUpAndVerify(
      WidgetTester tester, GoRouter router, String email) async {
    router.go('/signup');
    await settleEntry(tester);
    await tester.enterText(find.byKey(const Key('signup-email')), email);
    await tester.enterText(
        find.byKey(const Key('signup-password')), 'a-good-password');
    await tapVisible(tester, find.text(S.signUpAction));
    expect(find.byType(EmailVerificationPage), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('verification-code')), kMockVerificationCode);
    await tapVisible(tester, find.text(S.verifyEmailAction));
  }

  /// `/login`'s Google surface, through the development chooser — the path a
  /// debug build takes (`google_sign_in_button.dart`).
  Future<void> googleSignIn(WidgetTester tester, String email) async {
    await tapVisible(tester, find.byKey(const Key('google-sign-in')));
    await tester.enterText(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)),
      email,
    );
    await tester.tap(find.text(S.confirm));
    await settleEntry(tester);
  }

  group('login presentation', () {
    testWidgets('the identity field says email only — no username promise',
        (tester) async {
      await boot(tester);
      expect(S.emailLabel, 'البريد الإلكتروني');
      expect(find.text(S.emailLabel), findsOneWidget);
      expect(find.textContaining('اسم المستخدم'), findsNothing);
    });

    testWidgets(
        'Google is a full-width, first-class surface below the password form',
        (tester) async {
      await boot(tester);
      final google = find.byKey(const Key('google-sign-in'));
      final signIn = find.widgetWithText(FilledButton, S.signIn);
      expect(google, findsOneWidget);
      expect(find.text(S.continueWithGoogle), findsOneWidget);
      expect(find.byType(GoogleGMark), findsOneWidget,
          reason: 'the Google mark, not a generic account icon');
      expect(find.text(S.authMethodsDivider), findsOneWidget);

      final googleRect = tester.getRect(google);
      final signInRect = tester.getRect(signIn);
      expect(googleRect.height, greaterThanOrEqualTo(48));
      expect(googleRect.width, moreOrLessEquals(signInRect.width, epsilon: 1),
          reason: 'as wide as the primary action — not a secondary link');
      expect(googleRect.top, greaterThan(signInRect.bottom),
          reason: 'its own band below the email/password controls');
      // Only the normal authentication surface remains.
      expect(find.text(S.forgotPassword), findsOneWidget);
      expect(find.text(S.createAccount), findsOneWidget);
      expect(find.byKey(const Key('customer-demo-entry')), findsNothing);
      expect(find.text(S.customerDemoAction), findsNothing);
      expect(find.text(S.demoAccountsTitle), findsNothing);
      expect(find.text(S.demoSuperAdmin), findsNothing);
      expect(find.text(S.demoMainAdmin), findsNothing);
      expect(find.text(S.demoSimpleAdmin), findsNothing);
      expect(find.textContaining('رمز تحقق ثنائي'), findsNothing);
    });

    testWidgets('the local Google G resolves visibly in all four colours',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(child: GoogleGMark(size: 24)),
        ),
      );
      await settleEntry(tester);

      final imageWidget = tester.widget<Image>(find.byType(Image));
      final provider = imageWidget.image as MemoryImage;
      expect(tester.getSize(find.byType(GoogleGMark)), const Size.square(24));
      expect(provider.bytes.length, greaterThan(1000));

      var red = 0;
      var yellow = 0;
      var green = 0;
      var blue = 0;
      await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(provider.bytes);
        final frame = await codec.getNextFrame();
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final pixels = data!.buffer.asUint8List();
        for (var i = 0; i < pixels.length; i += 4) {
          final r = pixels[i];
          final g = pixels[i + 1];
          final b = pixels[i + 2];
          final a = pixels[i + 3];
          if (a < 80) continue;
          if (r > 180 && r > g + 45 && r > b + 45) red++;
          if (r > 170 && g > 110 && b < 100) yellow++;
          if (g > 100 && g > r + 20 && g > b + 10) green++;
          if (b > 130 && b > r + 20 && b > g + 10) blue++;
        }
        frame.image.dispose();
        codec.dispose();
      });
      expect(red, greaterThan(4));
      expect(yellow, greaterThan(4));
      expect(green, greaterThan(4));
      expect(blue, greaterThan(4));
    });

    testWidgets('fits 320dp at 1.6× text, dark and eye protection',
        (tester) async {
      await boot(tester,
          width: 320, textScale: 1.6, mode: ThemeMode.dark, eyeProtect: true);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(const Key('google-sign-in'))).height,
          greaterThanOrEqualTo(48));
      expect(find.text(S.continueWithGoogle), findsOneWidget);
      expect(find.text(S.createAccount), findsOneWidget);
    });

    testWidgets('keyboard-open Login remains scrollable at 320dp and 1.6×',
        (tester) async {
      await boot(
        tester,
        width: 320,
        height: 640,
        textScale: 1.6,
        keyboard: 280,
      );
      await tester.ensureVisible(find.text(S.createAccount));
      await settleEntry(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(S.createAccount), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('google-sign-in'))).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('the button runs the production gateway once, showing progress',
        (tester) async {
      final gateway = _ControlledGateway();
      final attempts = <GoogleSignInAttempt>[];
      await tester.pumpWidget(ProviderScope(
        overrides: [
          demoAccountsEnabledProvider.overrideWithValue(false),
          googleIdentityGatewayProvider.overrideWithValue(gateway),
        ],
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.medical),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: GoogleSignInButton(onAttempt: attempts.add),
            ),
          ),
        ),
      ));

      await tester.tap(find.byKey(const Key('google-sign-in')));
      await tester.pump();
      expect(gateway.calls, 1);
      expect(find.text(S.continuingWithGoogle), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byKey(const Key('google-sign-in')));
      await tester.pump();
      expect(gateway.calls, 1, reason: 'a second tap starts no second sheet');

      gateway.complete(const GoogleSignInCancelled());
      await settleEntry(tester);
      expect(attempts, [isA<GoogleSignInCancelled>()]);
      expect(find.text(S.continueWithGoogle), findsOneWidget);
    });
  });

  group('new verified, unlinked identity: Team or Demo', () {
    testWidgets(
        'email/password: the code first, then the choice — never a bare '
        'Team Code form', (tester) async {
      final (_, router) = await boot(tester);
      await signUpAndVerify(tester, router, newEmail);

      expect(at(router), '/link-team');
      expect(find.text(S.onboardingChoiceTitle), findsOneWidget);
      expect(choiceTeam, findsOneWidget);
      expect(choiceDemo, findsOneWidget);
      expect(find.text(S.onboardingChoiceTeamSub), findsOneWidget);
      expect(find.text(S.onboardingChoiceDemoSub), findsOneWidget);
      expect(teamCode, findsNothing);
      // Point 17C's invitation re-check stays reachable from the choice.
      expect(find.byKey(const Key('check-invitation')), findsOneWidget);
      expect(tester.getSize(choiceTeam).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(choiceDemo).height, greaterThanOrEqualTo(48));
    });

    testWidgets('Team option opens the Team Code flow, and can come back',
        (tester) async {
      final (_, router) = await boot(tester);
      await signUpAndVerify(tester, router, newEmail);

      await tapVisible(tester, choiceTeam);
      expect(at(router), '/link-team');
      expect(teamCode, findsOneWidget);
      expect(find.text(S.linkTeamAction), findsOneWidget);

      await tapVisible(tester, find.byKey(const Key('onboarding-choice-back')));
      expect(teamCode, findsNothing);
      expect(choiceTeam, findsOneWidget);
    });

    testWidgets(
        'Google-verified: straight to the choice, no redundant MTM code',
        (tester) async {
      final (_, router) = await boot(tester);
      await googleSignIn(tester, 'g.fresh@gmail.com');

      expect(find.byType(EmailVerificationPage), findsNothing);
      expect(at(router), '/link-team');
      expect(choiceTeam, findsOneWidget);
      expect(choiceDemo, findsOneWidget);
    });

    testWidgets(
        'a valid Simple Admin invitation outranks the choice (Google path)',
        (tester) async {
      final (_, router) = await boot(tester);
      await googleSignIn(tester, OnboardingFixtures.hilalInviteeEmail);

      expect(at(router), '/account-setup');
      expect(find.byType(AccountSetupPage), findsOneWidget);
      expect(find.text(S.roleSimpleAdmin), findsOneWidget);
      expect(choiceTeam, findsNothing);
      expect(choiceDemo, findsNothing);
      expect(teamCode, findsNothing);
    });

    testWidgets('Demo starts the isolated Customer Demo and links nothing',
        (tester) async {
      final (container, router) = await boot(tester);
      await signUpAndVerify(tester, router, newEmail);

      await tapVisible(tester, choiceDemo);
      await tester.pump(const Duration(seconds: 1));
      await settleEntry(tester);

      // The trial is the real application, entered at its home.
      expect(at(router), '/home');
      expect(find.byType(MainShell), findsOneWidget);
      expect(find.text(S.demoTrialNotice), findsOneWidget);
      final user = container.read(currentUserProvider).valueOrNull;
      expect(user?.role, AuthRole.customerDemo);
      expect(user?.saasTenantId, isNull,
          reason: 'a demo is never a tenant member');
      expect(user?.capabilities, demoCapabilities);
      expect(user?.capabilities.global.contains(Cap.adminManage), isFalse);
      expect(user?.capabilities.global.contains(Cap.orgEdit), isFalse);
      expect(user?.capabilities.scoped, isEmpty);
      expect(user?.email, isNot(newEmail),
          reason: 'the demo never carries the signup account');
      expect(container.read(authEntryStateProvider), isA<EntryNone>(),
          reason: 'the restricted onboarding session was discarded');

      // Nothing was linked on the server: signing in again returns the same
      // verified, unlinked identity to the same choice.
      final pending = container
          .read(onboardingControllerProvider.notifier)
          .signInWithPassword(email: newEmail, password: 'a-good-password');
      // Drain the mock's simulated latency inside the fake clock.
      await tester.pump(const Duration(seconds: 1));
      final again = await pending;
      await settleEntry(tester);
      final outcome = again.when(
        success: (data, {stale = false}) => data,
        failure: (_, __) => null,
        offline: (_) => null,
      );
      expect(outcome, isA<EntryContinueOnboarding>());
      final snapshot = (outcome! as EntryContinueOnboarding).snapshot;
      expect(snapshot.link, TenantLinkStatus.unlinked);
      expect(snapshot.tenant, isNull);
    });

    testWidgets(
        'Demo closed by the platform: stated in words, cannot start, '
        'never falls back into a tenant', (tester) async {
      final (container, router) = await boot(tester,
          demoPolicy: const CustomerDemoPolicy(available: false));
      await signUpAndVerify(tester, router, newEmail);

      expect(find.text(S.customerDemoUnavailable), findsOneWidget);
      await tapVisible(tester, choiceDemo);
      await tester.pump(const Duration(seconds: 1));
      await settleEntry(tester);

      expect(at(router), '/link-team');
      expect(container.read(currentUserProvider).valueOrNull, isNull);
      expect(container.read(authEntryStateProvider), isA<EntryOnboarding>());
    });

    testWidgets('the choice fits 320dp at 1.6× text with a long address',
        (tester) async {
      final (_, router) = await boot(tester,
          width: 320, height: 1800, textScale: 1.6, mode: ThemeMode.dark);
      await signUpAndVerify(tester, router,
          'abdulrahman.al-mutairi.volunteer@riyadh-emergency.org');
      expect(choiceTeam, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapVisible(tester, choiceTeam);
      expect(tester.takeException(), isNull);
    });
  });
}

class _ControlledGateway implements GoogleIdentityGateway {
  final _answer = Completer<GoogleSignInAttempt>();
  int calls = 0;

  void complete(GoogleSignInAttempt attempt) => _answer.complete(attempt);

  @override
  Future<GoogleSignInAttempt> signIn() {
    calls++;
    return _answer.future;
  }
}
