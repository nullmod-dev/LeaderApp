import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/brand/brand_mark.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/theme_choice.dart';
import 'package:mtm/core/theme/theme_state.dart';
import 'package:mtm/core/widgets/status_screen.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/presentation/entry_glass.dart';
import 'package:mtm/features/auth/presentation/startup_page.dart';
import 'package:mtm/features/auth/presentation/status_pages.dart';
import 'package:mtm/l10n/strings.dart';

/// The screens Point 3's classifier can reach, checked where they are hardest
/// to get right: a narrow Arabic phone at a large text scale, in every theme
/// the product ships, with motion turned off.
///
/// Deliberately not golden tests. What matters about a status screen is that
/// it says the right sentence, fits, offers one live action and no dead one —
/// none of which a pixel comparison checks, and all of which it would make
/// brittle.
void main() {
  /// Every page the classifier routes to, with the sentence it must show.
  const pages = <(String, Widget, String)>[
    ('invalid session', SessionInvalidPage(), S.sessionInvalidTitle),
    ('no access assigned', AccessNotAssignedPage(), S.accessNotAssignedTitle),
    ('account suspended', AccountSuspendedPage(), S.accountSuspendedTitle),
    ('account revoked', AccountRevokedPage(), S.accountRevokedTitle),
    ('tenant suspended', TenantSuspendedPage(), S.tenantSuspendedTitle),
    (
      'tenant deletion pending',
      TenantDeletionPendingPage(),
      S.tenantDeletionPendingTitle
    ),
    ('tenant deleted', TenantDeletedPage(), S.tenantDeletedTitle),
    ('demo expired', DemoExpiredPage(), S.demoExpiredTitle),
  ];

  group('a small phone at a large text scale, in Arabic', () {
    for (final (label, page, title) in pages) {
      testWidgets('$label fits and says what it is', (tester) async {
        // 320 dp — the narrowest phone the app supports — at 1.6× text.
        await _pump(tester, page, width: 320, height: 640, textScale: 1.6);

        expect(find.text(title), findsOneWidget);
        // A render overflow at this size is reported as an exception, so this
        // one assertion covers "it fits" as well as "it built".
        expect(tester.takeException(), isNull);

        // Exactly one primary action, and it is live.
        final signOut = find.widgetWithText(FilledButton, S.signOut);
        expect(signOut, findsOneWidget, reason: '$label has no way out');
        expect(
          tester.widget<FilledButton>(signOut).onPressed,
          isNotNull,
          reason: 'a dead primary action is worse than none',
        );
      });
    }
  });

  group('every theme the product ships', () {
    for (final choice in AppThemeChoice.values) {
      testWidgets('${choice.name} renders every state', (tester) async {
        for (final (label, page, title) in pages) {
          await _pump(tester, page, choice: choice);
          expect(find.text(title), findsOneWidget, reason: '$label/$choice');
          expect(tester.takeException(), isNull);
        }
      });
    }

    testWidgets('and so does eye-protect', (tester) async {
      for (final (label, page, title) in pages) {
        await _pump(tester, page, eyeProtect: true);
        expect(find.text(title), findsOneWidget, reason: label);
      }
    });
  });

  group('what these screens must not show', () {
    testWidgets('a refused session shows no account identity', (tester) async {
      // The payload was refused, so nothing on it is trustworthy enough to
      // render — not even a name.
      await _pump(tester, const SessionInvalidPage());
      expect(find.byType(StatusIdentityCard), findsNothing);
    });

    testWidgets('a blocked customer shows no organisation detail',
        (tester) async {
      for (final page in const [
        TenantSuspendedPage(),
        TenantDeletionPendingPage(),
        TenantDeletedPage(),
      ]) {
        await _pump(tester, page);
        expect(find.byType(StatusIdentityCard), findsNothing);
        expect(find.text(_me.orgName), findsNothing);
        expect(find.textContaining('مراجعة إدارية موثقة'), findsNothing);
        expect(find.textContaining('طلب حذف موثق'), findsNothing);
      }
    });

    testWidgets('an account-scoped state does name the account',
        (tester) async {
      // The other half: where knowing *which* account is held explains the
      // screen, it is shown.
      await _pump(tester, const AccessNotAssignedPage());
      expect(find.text(_me.name), findsOneWidget);
      expect(find.text(S.roleMainAdmin), findsOneWidget);
      expect(find.text(_me.email), findsNothing, reason: 'never the address');
      expect(find.text(_me.orgName), findsNothing, reason: 'never the team');
    });
  });

  group('support', () {
    testWidgets('opens over the screen rather than navigating into the shell',
        (tester) async {
      await _pump(tester, const AccountRevokedPage());

      await tester.tap(find.widgetWithText(OutlinedButton, S.contactSupport));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('medical.team.auth@gmail.com'), findsOneWidget);
      // Still the same screen underneath — no route was pushed.
      expect(find.text(S.accountRevokedTitle), findsOneWidget);
    });
  });

  group('the startup surface', () {
    // It is the Leader launch experience now (`LeaderIntro`), reached here
    // directly rather than through a cold launch — the gate is unarmed, so
    // the screen draws its resolved composition with no entrance to play.
    testWidgets('is branded, neutral and mentions no network', (tester) async {
      await _pump(tester, const StartupPage());

      expect(find.byKey(BrandMark.widgetKey), findsOneWidget);
      expect(find.text(S.productNameAr), findsOneWidget);
      expect(find.text(S.startupRestoring), findsOneWidget);
      // It must not leak the previous session.
      expect(find.text(_me.name), findsNothing);
      expect(find.text(_me.orgName), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loops nothing at the lowest performance level',
        (tester) async {
      await _pump(tester, const StartupPage(), level: MotionLevel.performance);
      // The pulse is still composed — it draws one fixed frame — but no
      // controller is running behind it.
      expect(find.byType(EntryPulse), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byKey(BrandMark.widgetKey), findsOneWidget);
    });

    testWidgets('and nothing when the device asks for reduced motion',
        (tester) async {
      await _pump(tester, const StartupPage(), disableAnimations: true);
      expect(find.byType(EntryPulse), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byKey(BrandMark.widgetKey), findsOneWidget);
    });

    testWidgets('animates at the default level', (tester) async {
      // The other direction: the reduced form is a *response*, not the only
      // thing the screen can do.
      await _pump(tester, const StartupPage());
      expect(tester.hasRunningAnimations, isTrue);
    });
  });
}

const _me = AuthUser(
  id: 'u_1',
  name: 'ليلى ياسين',
  email: 'l.yaseen@mtm.org',
  role: AuthRole.mainAdmin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities.none,
  orgName: 'فريق الإسعاف التطوعي · دمشق',
);

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  double width = 390,
  double height = 844,
  double textScale = 1,
  AppThemeChoice choice = AppThemeChoice.darkCyber,
  bool eyeProtect = false,
  MotionLevel level = MotionLevel.balanced,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    currentUserResultProvider
        .overrideWith((ref) async => const Success<AuthUser?>(_me)),
    sessionsProvider
        .overrideWith((ref) async => const Success<List<Session>>([])),
  ]);
  addTearDown(container.dispose);

  // Through the same seam the Themes screen uses, so these render in the
  // exact palette/mode pair the product ships each theme as.
  final state = const ThemeState.initial()
      .withChoice(choice)
      .copyWith(eyeProtect: eyeProtect);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(state.palette, eyeProtect: eyeProtect),
      darkTheme: AppTheme.dark(state.palette, eyeProtect: eyeProtect),
      themeMode: state.mode,
      home: page,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: MotionScope(
            level: level,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}
