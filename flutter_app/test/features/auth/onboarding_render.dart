@Tags(['render'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/startup/intro_gate.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/customer_demo_controller.dart';
import 'package:mtm/features/auth/data/google_identity_gateway.dart';
import 'package:mtm/features/auth/data/mock_auth_repository.dart';
import 'package:mtm/features/auth/data/mock_onboarding_repository.dart';
import 'package:mtm/features/auth/data/onboarding_controller.dart';
import 'package:mtm/features/auth/domain/customer_demo.dart';
import 'package:mtm/core/display/frame_rate.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/theme_controller.dart';
import 'package:mtm/features/auth/presentation/login_page.dart';
import 'package:mtm/features/settings/data/settings_providers.dart';
import 'package:mtm/features/settings/domain/settings_models.dart';
import 'package:mtm/features/settings/domain/settings_repository.dart';
import 'package:mtm/l10n/strings.dart';

/// Deliberate Point 17C visual-review harness. PNGs stay outside the
/// repository, and — unlike `onboarding_screens_test.dart`'s `boot` — no
/// overflow report is swallowed, so every shot is also a fit check.
///
/// MTM_RENDER_DIR=/tmp/mtm-onboarding flutter test
/// test/features/auth/onboarding_render.dart --tags render --update-goldens
void main() {
  final outDir = Platform.environment['MTM_RENDER_DIR'];
  const longEmail = 'abdulrahman.al-mutairi.volunteer@riyadh-emergency.org';

  setUpAll(() async {
    final arabic = FontLoader('IBMPlexSansArabic');
    for (final weight in ['Regular', 'Medium', 'SemiBold']) {
      arabic.addFont(
        File('assets/fonts/IBMPlexSansArabic-$weight.ttf')
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    }
    await arabic.load();
    var cache = File(Platform.resolvedExecutable).parent;
    while (!cache.path.endsWith('/cache') && cache.parent.path != cache.path) {
      cache = cache.parent;
    }
    await (FontLoader('MaterialIcons')
          ..addFont(
            File(
              '${cache.path}/artifacts/material_fonts/'
              'MaterialIcons-Regular.otf',
            ).readAsBytes().then(ByteData.sublistView),
          ))
        .load();
  });

  late DateTime now;
  late bool online;
  late MockOnboardingRepository onboarding;

  Future<GoRouter> boot(
    WidgetTester tester, {
    PaletteId palette = PaletteId.medical,
    ThemeMode mode = ThemeMode.light,
    double width = 390,
    double height = 844,
    double textScale = 1,
    double keyboard = 0,
    bool eyeProtect = false,
    bool reduceMotion = false,
    MotionLevel? motionLevel,
    GoogleSignInAttempt? google,
    bool pendingGoogle = false,
    bool demoAvailable = true,
    bool intro = false,
    Duration? holdAt,
  }) async {
    // Arming the gate before the container is read is what a cold process
    // launch does in `main()`; it is the only way to render the intro, since
    // the router leaves `/startup` the moment the classifier can answer.
    IntroGate.resetForTest();
    if (intro) IntroGate.armColdLaunch();
    addTearDown(IntroGate.resetForTest);
    now = DateTime.utc(2026, 9, 13, 9);
    online = true;
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size(width * 2, height * 2);
    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 2);
    addTearDown(tester.view.reset);

    final auth = MockAuthRepository(demoAccountsEnabled: false);
    final container = ProviderContainer(overrides: [
      authRepositoryProvider.overrideWithValue(auth),
      // The entry surface resolves its own light/dark and eye-protect from
      // the **stored theme**, not from `MaterialApp.themeMode` — so a shot
      // that only set `themeMode` was rendering light and calling it dark.
      // See FRONTEND-DESIGN-NOTES, "A render harness that cannot render the
      // mode is not covering it".
      settingsRepositoryProvider.overrideWithValue(_StoredTheme(ThemeState(
        palette: palette,
        mode: mode,
        eyeProtect: eyeProtect,
      ))),
      // Production appearance: no persona section, the real Google gateway.
      demoAccountsEnabledProvider.overrideWithValue(false),
      clockProvider.overrideWithValue(() => now),
      onboardingRepositoryProvider.overrideWith(
        (ref) => onboarding = MockOnboardingRepository(
          clock: () => now,
          online: () => online,
          sessionIssued: auth.installOnboardedSession,
        ),
      ),
      if (google != null)
        googleIdentityGatewayProvider.overrideWithValue(_Fixed(google)),
      if (pendingGoogle)
        googleIdentityGatewayProvider.overrideWithValue(const _Pending()),
      if (!demoAvailable)
        customerDemoPolicyProvider
            .overrideWithValue(const CustomerDemoPolicy(available: false)),
    ]);
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(palette, eyeProtect: eyeProtect),
        darkTheme: AppTheme.dark(palette, eyeProtect: eyeProtect),
        themeMode: mode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: MotionScope(
              level: motionLevel ??
                  (reduceMotion
                      ? MotionLevel.performance
                      : MotionLevel.balanced),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ));
    if (holdAt != null) {
      // An exact instant, for a frame of a sequence that is still running.
      await tester.pump();
      await tester.pump(holdAt);
      return router;
    }
    // Bounded, never `pumpAndSettle`: the entry surface loops its ambient
    // pulse for as long as it is on screen. This also drains the auth
    // restore's simulated latency.
    await _settle(tester);
    return router;
  }

  Future<void> shot(WidgetTester tester, String name) async {
    // Drain the mock repositories' simulated latency, bounded.
    await _settle(tester);
    expect(tester.takeException(), isNull, reason: '$name must fit');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$outDir/$name.png'),
    );
  }

  /// A frame exactly as it stands, with no further pumping. For the intro,
  /// whose sequence is the thing being looked at.
  Future<void> frame(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull, reason: '$name must fit');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$outDir/$name.png'),
    );
    // Drain what the held frame left running — the gate's own ceiling and
    // the caption's delay — so the tester's "no pending timer" invariant is
    // met after a shot taken mid-sequence.
    await tester.pump(IntroGate.ceiling + const Duration(seconds: 1));
    await _settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text).last;
    await tester.ensureVisible(target);
    await _settle(tester);
    await tester.tap(target);
    await _settle(tester);
  }

  Future<void> type(WidgetTester tester, Finder field, String value) async {
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await _settle(tester);
  }

  // `AuthScaffold` screens label through the decoration; Login labels above
  // the field and carries [LoginField.keyFor] instead.
  Finder labelled(String label) => find.byWidgetPredicate((w) =>
      w is TextField &&
      (w.decoration?.labelText == label || w.key == LoginField.keyFor(label)));

  Future<void> signUp(WidgetTester tester, GoRouter router, String email,
      {String password = 'a-good-password'}) async {
    router.go('/signup');
    await _settle(tester);
    await type(tester, find.byKey(const Key('signup-email')), email);
    await type(tester, find.byKey(const Key('signup-password')), password);
    await tapText(tester, S.signUpAction);
  }

  Future<void> verify(WidgetTester tester, String code) async {
    await type(tester, find.byKey(const Key('verification-code')), code);
    await tapText(tester, S.verifyEmailAction);
  }

  /// Point 18B — past the Team/Demo chooser onto the Team Code form.
  Future<void> chooseTeam(WidgetTester tester) async {
    final team = find.byKey(const Key('onboarding-choice-team'));
    await tester.ensureVisible(team);
    await _settle(tester);
    await tester.tap(team);
    await _settle(tester);
  }

  testWidgets('01 login 390 light', (tester) async {
    await boot(tester);
    await shot(tester, '01-login-390-light');
  }, skip: outDir == null);

  testWidgets('02 login 390 dark, long email', (tester) async {
    await boot(tester, mode: ThemeMode.dark);
    await type(tester, labelled(S.emailLabel), longEmail);
    await shot(tester, '02-login-390-dark');
  }, skip: outDir == null);

  testWidgets('19 signup 320 x1.6 field error', (tester) async {
    final router = await boot(tester, width: 320, height: 1100, textScale: 1.6);
    await signUp(tester, router, 'not-an-email');
    await shot(tester, '19-signup-320-1.6x-field-error');
  }, skip: outDir == null);

  testWidgets('03 signup 320 x1.6 validation', (tester) async {
    final router = await boot(tester, width: 320, height: 1100, textScale: 1.6);
    await signUp(tester, router, longEmail, password: 'short');
    await shot(tester, '03-signup-320-1.6x-long-email-short-password');
  }, skip: outDir == null);

  testWidgets('04 verify email 390', (tester) async {
    final router = await boot(tester);
    await signUp(tester, router, OnboardingFixtures.nabdMainAdminEmail);
    await shot(tester, '04-verify-390');
  }, skip: outDir == null);

  testWidgets('05 verify wrong code 320 x1.6', (tester) async {
    final router = await boot(tester, width: 320, height: 1300, textScale: 1.6);
    await signUp(tester, router, OnboardingFixtures.nabdMainAdminEmail);
    await verify(tester, '111111');
    await shot(tester, '05-verify-wrong-code-320-1.6x');
  }, skip: outDir == null);

  testWidgets('06 verify expired', (tester) async {
    final router = await boot(tester);
    await signUp(tester, router, OnboardingFixtures.nabdMainAdminEmail);
    now = now.add(const Duration(minutes: 11));
    await verify(tester, kMockVerificationCode);
    await shot(tester, '06-verify-expired');
  }, skip: outDir == null);

  testWidgets('07 verify keyboard open 320', (tester) async {
    final router = await boot(tester, width: 320, height: 640, keyboard: 280);
    await signUp(tester, router, OnboardingFixtures.nabdMainAdminEmail);
    await type(tester, find.byKey(const Key('verification-code')), '٢٤٦');
    await shot(tester, '07-verify-keyboard-320');
  }, skip: outDir == null);

  testWidgets('08 team link 390, code typed', (tester) async {
    final router = await boot(tester);
    await signUp(tester, router, OnboardingFixtures.nabdMainAdminEmail);
    await verify(tester, kMockVerificationCode);
    await chooseTeam(tester);
    await type(tester, find.byKey(const Key('team-code')),
        OnboardingFixtures.nabdCode);
    await shot(tester, '08-team-link-390');
  }, skip: outDir == null);

  testWidgets('09 team link refused 320 x1.6', (tester) async {
    final router = await boot(tester, width: 320, height: 1300, textScale: 1.6);
    await signUp(tester, router, OnboardingFixtures.nabdMainAdminEmail);
    await verify(tester, kMockVerificationCode);
    await chooseTeam(tester);
    await type(tester, find.byKey(const Key('team-code')),
        OnboardingFixtures.unknownCode);
    await tapText(tester, S.linkTeamAction);
    await shot(tester, '09-team-link-refused-320-1.6x');
  }, skip: outDir == null);

  testWidgets('10 invitation-bound Simple Admin setup 390', (tester) async {
    final router = await boot(tester);
    await signUp(tester, router, OnboardingFixtures.hilalInviteeEmail);
    await verify(tester, kMockVerificationCode);
    await shot(tester, '10-setup-simple-admin-invitation-390');
  }, skip: outDir == null);

  testWidgets('11 Main Admin setup 320 x1.6 copper dark', (tester) async {
    final router = await boot(tester,
        width: 320,
        height: 1300,
        textScale: 1.6,
        palette: PaletteId.copper,
        mode: ThemeMode.dark);
    await signUp(tester, router, OnboardingFixtures.nabdMainAdminEmail);
    await verify(tester, kMockVerificationCode);
    await chooseTeam(tester);
    await type(tester, find.byKey(const Key('team-code')),
        OnboardingFixtures.nabdCode);
    await tapText(tester, S.linkTeamAction);
    await shot(tester, '11-setup-main-admin-320-1.6x-copper-dark');
  }, skip: outDir == null);

  testWidgets('12 Google unavailable (configuration needed)', (tester) async {
    await boot(tester, google: const GoogleSignInUnavailable());
    await tester.ensureVisible(find.byKey(const Key('google-sign-in')));
    await tester.tap(find.byKey(const Key('google-sign-in')));
    await shot(tester, '12-login-google-unavailable');
  }, skip: outDir == null);

  testWidgets('13 Google provider failure, indigo dark', (tester) async {
    await boot(tester,
        google: const GoogleSignInFailed(),
        palette: PaletteId.indigo,
        mode: ThemeMode.dark);
    await tester.ensureVisible(find.byKey(const Key('google-sign-in')));
    await tester.tap(find.byKey(const Key('google-sign-in')));
    await shot(tester, '13-login-google-failed-indigo-dark');
  }, skip: outDir == null);

  testWidgets('14 offline onboarding', (tester) async {
    final router = await boot(tester);
    await signUp(tester, router, OnboardingFixtures.nabdMainAdminEmail);
    online = false;
    await verify(tester, kMockVerificationCode);
    await shot(tester, '14-verify-offline');
  }, skip: outDir == null);

  testWidgets('15 blocked account', (tester) async {
    await boot(tester);
    await type(
        tester, labelled(S.emailLabel), OnboardingFixtures.suspendedEmail);
    await type(tester, labelled(S.passwordLabel), kMockFixturePassword);
    await tapText(tester, S.signIn);
    await shot(tester, '15-blocked-account');
  }, skip: outDir == null);

  testWidgets('16 blocked tenant', (tester) async {
    final router = await boot(tester);
    await signUp(tester, router, OnboardingFixtures.hilalInviteeEmail);
    await verify(tester, kMockVerificationCode);
    onboarding.setTenantStatus(
        OnboardingFixtures.hilalTenantId, SaasTenantStatus.suspended);
    await tapText(tester, S.completeSetupAction);
    await shot(tester, '16-blocked-tenant');
  }, skip: outDir == null);

  testWidgets('17 signup eye protection, reduced motion', (tester) async {
    final router = await boot(tester, eyeProtect: true, reduceMotion: true);
    router.go('/signup');
    await _settle(tester);
    await shot(tester, '17-signup-eye-protect');
  }, skip: outDir == null);

  testWidgets('20 invitee stranded on team link 320 x1.6', (tester) async {
    final router = await boot(tester, width: 320, height: 1400, textScale: 1.6);
    await signUp(tester, router, OnboardingFixtures.hilalInviteeEmail);
    // Paused before verification, so the invitation cannot auto-link.
    onboarding.setTenantStatus(
        OnboardingFixtures.hilalTenantId, SaasTenantStatus.suspended);
    await verify(tester, kMockVerificationCode);
    await tapText(tester, S.checkInvitationAction);
    await shot(tester, '20-team-link-invitee-no-invitation-320-1.6x');
  }, skip: outDir == null);

  testWidgets('21 Team/Demo chooser 390 light', (tester) async {
    final router = await boot(tester);
    await signUp(tester, router, OnboardingFixtures.nabdMainAdminEmail);
    await verify(tester, kMockVerificationCode);
    await shot(tester, '21-choice-390-light');
  }, skip: outDir == null);

  testWidgets('22 chooser 320 x1.6 dark, long email', (tester) async {
    final router = await boot(tester,
        width: 320, height: 1500, textScale: 1.6, mode: ThemeMode.dark);
    await signUp(tester, router, longEmail);
    await verify(tester, kMockVerificationCode);
    await shot(tester, '22-choice-320-1.6x-dark-long-email');
  }, skip: outDir == null);

  testWidgets('23 chooser, demo closed, eye protection', (tester) async {
    final router =
        await boot(tester, eyeProtect: true, demoAvailable: false, width: 320);
    await signUp(tester, router, OnboardingFixtures.nabdMainAdminEmail);
    await verify(tester, kMockVerificationCode);
    await shot(tester, '23-choice-demo-closed-eye-protect-320');
  }, skip: outDir == null);

  testWidgets('24 Google in progress, 390 dark slate', (tester) async {
    await boot(tester,
        pendingGoogle: true, palette: PaletteId.slate, mode: ThemeMode.dark);
    await tester.ensureVisible(find.byKey(const Key('google-sign-in')));
    await tester.tap(find.byKey(const Key('google-sign-in')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('$outDir/24-login-google-in-progress-dark.png'));
  }, skip: outDir == null);

  testWidgets('18 login 320 x1.6 teal', (tester) async {
    await boot(tester,
        width: 320, height: 1400, textScale: 1.6, palette: PaletteId.teal);
    await shot(tester, '18-login-320-1.6x-teal');
  }, skip: outDir == null);

  // ---- The entry redesign ------------------------------------------------
  // Login on every ground it can be drawn on, and the launch sequence that
  // hands over to it.

  testWidgets('25 login 320 x1.6 light — the worst case', (tester) async {
    await boot(tester, width: 320, height: 1400, textScale: 1.6);
    await shot(tester, '25-login-320-1.6x-light');
  }, skip: outDir == null);

  testWidgets('26 login 600 tablet width', (tester) async {
    await boot(tester, width: 600, height: 900);
    await shot(tester, '26-login-600-light');
  }, skip: outDir == null);

  testWidgets('27 login eye protection, light', (tester) async {
    await boot(tester, eyeProtect: true);
    await shot(tester, '27-login-390-light-eye-protect');
  }, skip: outDir == null);

  testWidgets('28 login eye protection, dark', (tester) async {
    await boot(tester, mode: ThemeMode.dark, eyeProtect: true);
    await shot(tester, '28-login-390-dark-eye-protect');
  }, skip: outDir == null);

  testWidgets('29 login focused field + live CTA, dark', (tester) async {
    await boot(tester, mode: ThemeMode.dark);
    await type(tester, labelled(S.emailLabel), 'huda.alshammari@nabd.org');
    await type(tester, labelled(S.passwordLabel), 'a-good-password');
    await tester.tap(labelled(S.passwordLabel));
    await shot(tester, '29-login-390-dark-focused');
  }, skip: outDir == null);

  testWidgets('30 login refusal, light', (tester) async {
    await boot(tester);
    await type(tester, labelled(S.emailLabel), 'someone@nabd.org');
    await type(tester, labelled(S.passwordLabel), 'wrong-password');
    await tapText(tester, S.signIn);
    await shot(tester, '30-login-390-light-refused');
  }, skip: outDir == null);

  testWidgets('31 login keyboard open, 320', (tester) async {
    await boot(tester, width: 320, height: 640, keyboard: 280);
    await tester.tap(labelled(S.passwordLabel));
    await shot(tester, '31-login-keyboard-320');
  }, skip: outDir == null);

  testWidgets('32 login reduced motion, light', (tester) async {
    await boot(tester, reduceMotion: true);
    await shot(tester, '32-login-390-reduced-motion');
  }, skip: outDir == null);

  for (final (index, label, at) in const [
    (33, 'mark arriving', Duration(milliseconds: 260)),
    (34, 'wave leaving', Duration(milliseconds: 700)),
    (35, 'settled', Duration(milliseconds: 2500)),
  ]) {
    testWidgets('$index intro 390 dark — $label', (tester) async {
      await boot(tester,
          intro: true,
          holdAt: at,
          mode: ThemeMode.dark,
          motionLevel: MotionLevel.high);
      await frame(tester, '$index-intro-390-dark-${at.inMilliseconds}ms');
    }, skip: outDir == null);
  }

  testWidgets('36 intro 390 light, mid-wave', (tester) async {
    await boot(tester,
        intro: true,
        holdAt: const Duration(milliseconds: 820),
        motionLevel: MotionLevel.high);
    await frame(tester, '36-intro-390-light');
  }, skip: outDir == null);

  testWidgets('37 intro still waiting on a slow boot', (tester) async {
    // Past the sequence and past the caption delay: the one state where the
    // launch screen says anything at all.
    await boot(tester,
        intro: true,
        holdAt: const Duration(milliseconds: 3200),
        mode: ThemeMode.dark,
        motionLevel: MotionLevel.high);
    await frame(tester, '37-intro-390-dark-waiting');
  }, skip: outDir == null);

  testWidgets('38 intro 320 x1.6 eye protection', (tester) async {
    await boot(tester,
        intro: true,
        holdAt: const Duration(milliseconds: 1200),
        width: 320,
        height: 640,
        textScale: 1.6,
        eyeProtect: true,
        motionLevel: MotionLevel.high);
    await frame(tester, '38-intro-320-1.6x-eye-protect');
  }, skip: outDir == null);
}

/// Bounded pumps: the entry surface's ambient pulse never lets
/// `pumpAndSettle` return.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Serves one fixed appearance, instantly. The real `MockSettingsRepository`
/// answers after a simulated delay, which is the wrong fixture for a shot.
class _StoredTheme implements SettingsRepository {
  _StoredTheme(this.theme);

  final ThemeState theme;

  @override
  Future<Result<ThemeState?>> themePrefs() async => Success(theme);
  @override
  Future<Result<ThemeState>> updateThemePrefs(ThemeState prefs) async =>
      Success(prefs);
  @override
  Future<Result<MotionLevel?>> motionLevel() async => const Success(null);
  @override
  Future<Result<MotionLevel>> updateMotionLevel(MotionLevel level) async =>
      Success(level);
  @override
  Future<Result<FrameRatePreference?>> frameRate() async => const Success(null);
  @override
  Future<Result<FrameRatePreference>> updateFrameRate(
          FrameRatePreference p) async =>
      Success(p);
  @override
  Future<Result<NotificationPrefs>> notificationPrefs() async =>
      throw UnimplementedError();
  @override
  Future<Result<NotificationPrefs>> updateNotificationPrefs(
          NotificationPrefs p) async =>
      throw UnimplementedError();
  @override
  Future<Result<OrgInfo>> orgInfo() async => throw UnimplementedError();
}

class _Fixed implements GoogleIdentityGateway {
  const _Fixed(this.attempt);
  final GoogleSignInAttempt attempt;

  @override
  Future<GoogleSignInAttempt> signIn() async => attempt;
}

/// A Google sheet that never answers — the in-progress state, held.
class _Pending implements GoogleIdentityGateway {
  const _Pending();

  @override
  Future<GoogleSignInAttempt> signIn() =>
      Completer<GoogleSignInAttempt>().future;
}
