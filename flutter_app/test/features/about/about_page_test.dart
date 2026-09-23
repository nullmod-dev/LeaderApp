import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/app_info.dart';
import 'package:mtm/core/platform/external_links.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/about/domain/support_contacts.dart';
import 'package:mtm/features/about/presentation/about_page.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/l10n/strings.dart';

/// About & support, opened the way a user reaches it, in RTL at a phone width.
///
/// The layout is Ahmed's to inspect. What is asserted here is what a look at
/// the screen cannot tell you: which URI each button actually hands to the
/// platform, what a failed handoff says, that the Telegram fallback is a real
/// second attempt, that copying puts the exact approved value on the clipboard
/// — and that no Privacy or Terms destination exists to be tapped.

const _admin = AuthUser(
  id: 'u',
  name: 'أحمد عبد الكريم',
  email: 'admin@mtm.org',
  role: AuthRole.mainAdmin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities(global: Cap.all),
  orgName: 'MTM',
);

/// Records what was asked for and answers whatever the test wants.
class _FakeLauncher extends ExternalLinkLauncher {
  _FakeLauncher([this.answers = const [ExternalLinkOutcome.opened]]);

  final List<ExternalLinkOutcome> answers;
  final List<Uri> asked = [];

  @override
  Future<ExternalLinkOutcome> open(Uri uri) async {
    asked.add(uri);
    return answers[
        asked.length <= answers.length ? asked.length - 1 : answers.length - 1];
  }
}

void main() {
  testWidgets('Settings has one About row and it opens the About screen',
      (tester) async {
    final (:router, launcher: _) = await _boot(tester);
    router.go('/more');
    await _settle(tester);

    expect(find.byKey(const Key('settings-about-row')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-about-row')));
    await _settle(tester);

    expect(find.byType(AboutPage), findsOneWidget);
  });

  testWidgets('the real installed version and build number are shown',
      (tester) async {
    await _open(tester);
    // From `AppInfo`, which the drift test holds to `pubspec.yaml` — not a
    // literal typed into the page.
    expect(find.text(AppInfo.version), findsOneWidget);
    expect(find.text(AppInfo.buildNumber), findsOneWidget);
  });

  testWidgets('uses the canonical Arabic and English product names',
      (tester) async {
    await _open(tester);

    expect(find.text(S.aboutAppName), findsOneWidget);
    expect(find.text(S.aboutAppFullName), findsOneWidget);
    expect(find.textContaining('MTM'), findsNothing);
    expect(
      Directionality.of(tester.element(find.text(S.aboutAppName))),
      TextDirection.rtl,
    );
    expect(
      Directionality.of(tester.element(find.text(S.aboutAppFullName))),
      TextDirection.ltr,
    );
  });

  testWidgets('the approved contacts are displayed exactly', (tester) async {
    await _open(tester);
    expect(find.text('medical.team.auth@gmail.com'), findsOneWidget);
    expect(find.text('@jjkkkj'), findsOneWidget);
  });

  testWidgets('no Privacy or Terms destination exists', (tester) async {
    final (:router, launcher: _) = await _boot(tester);
    // Not on the About screen…
    router.go(AboutPage.routePath);
    await _settle(tester);
    expect(find.textContaining('الخصوصية'), findsNothing);
    expect(find.textContaining('الشروط'), findsNothing);
    // …and not as routes: an unknown path falls through to the router's own
    // handling rather than rendering a page nobody wrote.
    router.go('/more/privacy');
    await _settle(tester);
    expect(find.byType(AboutPage), findsNothing);
  });

  testWidgets('the email button opens a mailto for the approved address',
      (tester) async {
    final launcher = await _open(tester);
    await tester.tap(find.byKey(const Key('about-open-email')));
    await _settle(tester);

    expect(launcher.asked.single, emailUri());
    expect(launcher.asked.single.path, 'medical.team.auth@gmail.com');
    // Nothing is claimed on success — the user is in their mail app.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a device with no mail client is told to copy instead',
      (tester) async {
    final launcher =
        await _open(tester, answers: [ExternalLinkOutcome.unsupported]);
    await tester.tap(find.byKey(const Key('about-open-email')));
    await _settle(tester);

    expect(launcher.asked, hasLength(1));
    expect(find.text(S.aboutEmailUnsupported), findsOneWidget);
  });

  testWidgets('a failed handoff says so and never shows a raw exception',
      (tester) async {
    await _open(tester, answers: [ExternalLinkOutcome.failed]);
    await tester.tap(find.byKey(const Key('about-open-email')));
    await _settle(tester);

    expect(find.text(S.aboutLaunchFailed), findsOneWidget);
  });

  testWidgets('Telegram tries the app, then falls back to t.me',
      (tester) async {
    final launcher = await _open(
      tester,
      answers: [ExternalLinkOutcome.unsupported, ExternalLinkOutcome.opened],
    );
    // Telegram is the last card on a page that now also carries the
    // capability list and the «صنع بفخر في العراق» sign-off, so on a test
    // viewport it starts below the fold.
    await tester.ensureVisible(find.byKey(const Key('about-open-telegram')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('about-open-telegram')));
    await _settle(tester);

    expect(launcher.asked, [telegramAppUri(), telegramWebUri()]);
    expect(launcher.asked.last.toString(), 'https://t.me/jjkkkj');
    // The fallback worked, so nothing is reported.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('the app link alone is enough when Telegram is installed',
      (tester) async {
    final launcher = await _open(tester);
    // Telegram is the last card on a page that now also carries the
    // capability list and the «صنع بفخر في العراق» sign-off, so on a test
    // viewport it starts below the fold.
    await tester.ensureVisible(find.byKey(const Key('about-open-telegram')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('about-open-telegram')));
    await _settle(tester);

    expect(launcher.asked, [telegramAppUri()]);
  });

  testWidgets('both fallbacks failing leaves the copy advice on screen',
      (tester) async {
    final launcher = await _open(
      tester,
      answers: [
        ExternalLinkOutcome.unsupported,
        ExternalLinkOutcome.unsupported
      ],
    );
    // Telegram is the last card on a page that now also carries the
    // capability list and the «صنع بفخر في العراق» sign-off, so on a test
    // viewport it starts below the fold.
    await tester.ensureVisible(find.byKey(const Key('about-open-telegram')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('about-open-telegram')));
    await _settle(tester);

    expect(launcher.asked, hasLength(2));
    expect(find.text(S.aboutTelegramUnsupported), findsOneWidget);
    // And the value is still there to copy.
    expect(find.byKey(const Key('about-copy-telegram')), findsOneWidget);
  });

  testWidgets('copy puts the exact displayed value on the clipboard',
      (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await _open(tester);

    await tester.tap(find.byKey(const Key('about-copy-email')));
    await _settle(tester);
    expect(copied.last, 'medical.team.auth@gmail.com');
    expect(find.text(S.aboutEmailCopied), findsOneWidget);

    // Let the confirmation go and bring the second contact clear of the
    // floating bottom nav: both sit over the bottom of the screen, which is
    // where this button otherwise lands.
    await tester.pump(const Duration(seconds: 5));
    await tester.scrollUntilVisible(
      find.byKey(const Key('about-copy-telegram')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('about-copy-telegram')));
    await _settle(tester);
    // The `@` is kept: what is copied is what is on screen.
    expect(copied.last, '@jjkkkj');
  });

  testWidgets('the screen fits a 320dp phone at a large text scale',
      (tester) async {
    // The narrow-and-large case is where an Arabic label beside a Latin
    // address stops fitting. An overflow here fails the test.
    await _open(tester, size: const Size(320 * 2, 640 * 2), textScale: 1.6);
    expect(find.byType(AboutPage), findsOneWidget);

    // Everything is reachable by scrolling — the support block is below the
    // fold on a screen this small, which is fine; being clipped is not.
    await tester.scrollUntilVisible(
      find.byKey(const Key('about-copy-telegram')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('@jjkkkj'), findsOneWidget);
    expect(find.text('medical.team.auth@gmail.com'), findsOneWidget);
  });
}

// -----------------------------------------------------------------------------

Future<_FakeLauncher> _open(
  WidgetTester tester, {
  List<ExternalLinkOutcome> answers = const [ExternalLinkOutcome.opened],
  Size size = const Size(1080, 2400),
  double textScale = 1,
}) async {
  final (:router, :launcher) = await _boot(
    tester,
    answers: answers,
    size: size,
    textScale: textScale,
  );
  router.go(AboutPage.routePath);
  await _settle(tester);
  return launcher;
}

Future<({GoRouter router, _FakeLauncher launcher})> _boot(
  WidgetTester tester, {
  List<ExternalLinkOutcome> answers = const [ExternalLinkOutcome.opened],
  Size size = const Size(1080, 2400),
  double textScale = 1,
}) async {
  // The two pre-existing debug complaints the router suites already tolerate
  // for this layout. Anything else — including an overflow on the About
  // screen — still fails the test.
  final inherited = FlutterError.onError;
  FlutterError.onError = (details) {
    final report = details.toString();
    if (report.contains('overflowed') &&
        report.contains('glass_bottom_nav.dart')) {
      return;
    }
    if (report.contains('ListTile background color or ink splashes')) return;
    inherited?.call(details);
  };
  addTearDown(() => FlutterError.onError = inherited);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final launcher = _FakeLauncher(answers);
  final container = ProviderContainer(overrides: [
    currentUserResultProvider
        .overrideWith((ref) async => const Success<AuthUser?>(_admin)),
    sessionsProvider
        .overrideWith((ref) async => const Success<List<Session>>([])),
    externalLinkLauncherProvider.overrideWithValue(launcher),
  ]);
  addTearDown(container.dispose);

  final router = container.read(appRouterProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(PaletteId.teal),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
  return (router: router, launcher: launcher);
}

/// Bounded pumps: the mock repositories answer after a simulated delay and the
/// dashboard schedules a promotion timer `pumpAndSettle` would wait an hour on.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
}
