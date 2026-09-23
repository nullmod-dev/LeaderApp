import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/brand/brand_mark.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/startup/intro_gate.dart';
import 'package:mtm/core/startup/startup_destination.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/presentation/entry_glass.dart';
import 'package:mtm/features/auth/presentation/leader_intro.dart';
import 'package:mtm/features/auth/presentation/login_page.dart';
import 'package:mtm/features/auth/presentation/startup_page.dart';
import 'package:mtm/features/home/presentation/home_page.dart';
import 'package:mtm/l10n/strings.dart';

/// The Leader cold-launch intro: when it plays, how long it holds the app,
/// and — the half that matters more — every way it is not allowed to get in
/// the way.
///
/// Nothing here asserts a pixel or a frame of the animation. What is pinned
/// is behaviour: a cold launch shows it, a warm one does not, it cannot hold
/// the app open-endedly, it never precedes a flash of another screen, and a
/// reduce-motion device gets none of it.
void main() {
  setUp(IntroGate.resetForTest);
  tearDown(IntroGate.resetForTest);

  String at(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  group('the gate', () {
    test('is idle in a process that never armed it', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(introGateProvider), IntroPhase.idle);
    });

    test('holds exactly one launch, and nothing re-arms it', () {
      IntroGate.armColdLaunch();
      final first = ProviderContainer();
      addTearDown(first.dispose);
      expect(first.read(introGateProvider), IntroPhase.holding);

      // A second container is a second read, not a second launch.
      final second = ProviderContainer();
      addTearDown(second.dispose);
      expect(second.read(introGateProvider), IntroPhase.idle);

      first.read(introGateProvider.notifier).finish();
      expect(first.read(introGateProvider), IntroPhase.done);
      // `finish` is idempotent and can never re-open the hold.
      first.read(introGateProvider.notifier).finish();
      expect(first.read(introGateProvider), IntroPhase.done);
    });

    testWidgets('releases itself if nothing ever finishes it', (tester) async {
      IntroGate.armColdLaunch();
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(introGateProvider), IntroPhase.holding);

      await tester.pump(IntroGate.ceiling + const Duration(milliseconds: 50));
      expect(c.read(introGateProvider), IntroPhase.done,
          reason: 'a never-mounted intro must not strand the app');
    });

    test('only ever produces the surface a launch already sits on', () {
      // Whatever else it is handed, the hold resolves to `restoring` — it
      // delays an answer, it never becomes one.
      for (final blocked in [true, false]) {
        expect(
          resolveStartup(StartupInputs(
            introHolding: true,
            upgradeBlocks: blocked,
            gate: AuthGate.signedOut,
            now: DateTime.utc(2026, 9, 22),
          )),
          StartupDestination.restoring,
        );
      }
      // And with the hold released, the same inputs answer normally.
      expect(
        resolveStartup(StartupInputs(
          gate: AuthGate.signedOut,
          now: DateTime.utc(2026, 9, 22),
        )),
        StartupDestination.signedOut,
      );
      expect(
        resolveStartup(StartupInputs(
          upgradeBlocks: true,
          gate: AuthGate.signedOut,
          now: DateTime.utc(2026, 9, 22),
        )),
        StartupDestination.forcedUpgrade,
      );
    });
  });

  group('a cold launch', () {
    testWidgets('opens on the intro and holds while it plays', (tester) async {
      IntroGate.armColdLaunch();
      final container = _container(const Success<AuthUser?>(null));
      final router = await _boot(tester, container);

      // The session answered immediately — signed out — and the app is still
      // on the launch surface, because the intro is running.
      expect(at(router), StartupPage.location);
      expect(find.byType(LeaderIntro), findsOneWidget);
      expect(find.byKey(BrandMark.widgetKey), findsOneWidget);
      expect(find.text(S.productNameAr), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
      expect(container.read(introGateProvider), IntroPhase.holding);

      // Nothing says "please wait" while the sequence is still its own
      // moment.
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );

      await _settle(tester);
      expect(at(router), '/login');
      expect(find.byType(LoginPage), findsOneWidget);
      expect(container.read(introGateProvider), IntroPhase.done);
    });

    testWidgets('keeps the full-motion composition visible for 2.5 seconds',
        (tester) async {
      IntroGate.armColdLaunch();
      final container = _container(const Success<AuthUser?>(null));
      await _boot(tester, container);

      await tester.pump(const Duration(milliseconds: 2400));
      expect(container.read(introGateProvider), IntroPhase.holding);
      expect(find.byType(LeaderIntro), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 99));
      expect(container.read(introGateProvider), IntroPhase.holding);

      await tester.pump(const Duration(milliseconds: 2));
      expect(container.read(introGateProvider), IntroPhase.done);
    });

    testWidgets('never shows another screen before it is over', (tester) async {
      IntroGate.armColdLaunch();
      final container = _container(const Success<AuthUser?>(_mainAdmin));
      final router = await _boot(tester, container);

      // Frame by frame through the whole sequence: nothing but the intro.
      for (var i = 0; i < 16; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (at(router) != StartupPage.location) break;
        expect(find.byType(LoginPage), findsNothing);
        expect(find.byType(HomePage), findsNothing);
      }
      await _settle(tester);
      expect(at(router), '/home');
    });

    testWidgets('says so in words when boot is genuinely slow', (tester) async {
      IntroGate.armColdLaunch();
      // A session read that never lands — the launch held still.
      final container = _container(_never());
      final router = await _boot(tester, container);

      await _settle(tester);
      // The gate opened; the classifier is still restoring, so the screen
      // stays — and now explains itself.
      expect(container.read(introGateProvider), IntroPhase.done);
      expect(at(router), StartupPage.location);
      expect(find.text(S.startupRestoring), findsOneWidget);
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
    });

    testWidgets('runs the same ambient pulse the sign-in screen does',
        (tester) async {
      IntroGate.armColdLaunch();
      final container = _container(_never());
      await _boot(tester, container);
      expect(find.byType(EntryPulse), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);

      // It keeps running after the entrance is over and the screen is merely
      // waiting — that is the point of it being ambience rather than part of
      // the sequence.
      await _settle(tester);
      expect(find.byType(EntryPulse), findsOneWidget);
      expect(tester.hasRunningAnimations, isTrue);
    });
  });

  group('it does not replay', () {
    testWidgets('once a launch has used it, the gate stays open',
        (tester) async {
      IntroGate.armColdLaunch();
      final answer = _Answer(const Success<AuthUser?>(_mainAdmin));
      final container = _container(null, answer: answer);
      final router = await _boot(tester, container);
      await _settle(tester);
      expect(at(router), '/home');
      expect(container.read(introGateProvider), IntroPhase.done);

      // Sign out from deep inside the app. The session changing is the one
      // thing that moves the whole app back to a pre-session screen, and it
      // does not re-arm the hold: the sign-in form appears immediately, with
      // no second 2.5-second brand moment in front of it.
      answer.value = const Success<AuthUser?>(null);
      container.invalidate(currentUserResultProvider);
      await _settle(tester);
      expect(at(router), '/login');
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(LeaderIntro), findsNothing);
      expect(container.read(introGateProvider), IntroPhase.done,
          reason: 'the gate never re-arms');
    });

    testWidgets('and landing back on the launch surface plays no entrance',
        (tester) async {
      // The screen itself, with the gate already spent: it draws its resolved
      // composition on the first frame and says what it is waiting for
      // straight away — nobody sits through a second 2.5-second sequence
      // because their session went stale.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(introGateProvider), IntroPhase.idle);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.medical),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: MotionScope(
              level: MotionLevel.high,
              child: LeaderIntro(),
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(BrandMark.widgetKey), findsOneWidget);
      expect(find.text(S.productNameAr), findsOneWidget);
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
        reason: 'the caption is up immediately, not after a hold',
      );
      expect(container.read(introGateProvider), IntroPhase.idle);
    });

    testWidgets('and a launch that never armed it holds nothing at all',
        (tester) async {
      final container = _container(const Success<AuthUser?>(null));
      final router = await _boot(tester, container);

      // No arming: the very first settled frame is already past the launch
      // surface, exactly as before the intro existed.
      await _settle(tester);
      expect(at(router), '/login');
      expect(container.read(introGateProvider), IntroPhase.idle);
    });
  });

  group('reduced motion', () {
    testWidgets('plays no entrance and holds nothing', (tester) async {
      IntroGate.armColdLaunch();
      final container = _container(const Success<AuthUser?>(null));
      final router = await _boot(tester, container, reduceMotion: true);

      // One frame past mount the gate is already open: the sequence is not
      // shortened, it is not run.
      await tester.pump();
      await tester.pump();
      expect(container.read(introGateProvider), IntroPhase.done);
      expect(tester.hasRunningAnimations, isFalse);

      await _settle(tester);
      expect(at(router), '/login');
    });

    testWidgets('and the screen is still composed while it is up',
        (tester) async {
      IntroGate.armColdLaunch();
      final container = _container(_never());
      await _boot(tester, container, reduceMotion: true);
      await tester.pump();

      expect(find.byKey(BrandMark.widgetKey), findsOneWidget);
      expect(find.text(S.productNameAr), findsOneWidget);
      expect(find.byType(EntryPulse), findsOneWidget,
          reason: 'it still draws one still frame — it just does not move');
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the intro fits a 320dp phone at 1.6x text', (tester) async {
    IntroGate.armColdLaunch();
    final container = _container(_never());
    await _boot(tester, container, width: 320, height: 640, textScale: 1.6);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text(S.productNameAr), findsOneWidget);
  });
}

// -----------------------------------------------------------------------------

const _mainAdmin = AuthUser(
  id: 'u_main',
  name: 'مشرف',
  email: 'admin@mtm.org',
  role: AuthRole.mainAdmin,
  saasTenantId: 'saas_test',
  capabilities: Capabilities(global: Cap.all),
  orgName: 'MTM',
);

Future<Result<AuthUser?>> _never() => Completer<Result<AuthUser?>>().future;

class _Answer {
  _Answer(this.value);
  Result<AuthUser?>? value;
}

ProviderContainer _container(Object? fixed, {_Answer? answer}) {
  final container = ProviderContainer(overrides: [
    currentUserResultProvider.overrideWith((ref) async {
      if (answer != null) {
        final value = answer.value;
        if (value == null) return _never();
        return value;
      }
      if (fixed is Future<Result<AuthUser?>>) return fixed;
      return fixed! as Result<AuthUser?>;
    }),
    sessionsProvider.overrideWith(
      (ref) async => const Success<List<Session>>([]),
    ),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<GoRouter> _boot(
  WidgetTester tester,
  ProviderContainer container, {
  double width = 390,
  double height = 844,
  double textScale = 1,
  bool reduceMotion = false,
}) async {
  // The real screens boot behind the router and complain about their own
  // pre-existing overflows at some sizes; those are not what this file is
  // about.
  final inherited = FlutterError.onError;
  FlutterError.onError = (details) {
    final report = details.toString();
    if (report.contains('overflowed') &&
        (report.contains('glass_bottom_nav.dart') ||
            report.contains('login_page.dart'))) {
      return;
    }
    if (report.contains('ListTile background color or ink splashes')) return;
    inherited?.call(details);
  };
  addTearDown(() => FlutterError.onError = inherited);

  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final router = container.read(appRouterProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(PaletteId.medical),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: MotionScope(
              level: reduceMotion ? MotionLevel.performance : MotionLevel.high,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return router;
}

/// Bounded pumps: the entry surface loops a pulse for as long as it is on
/// screen, so `pumpAndSettle` would never return.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
}
