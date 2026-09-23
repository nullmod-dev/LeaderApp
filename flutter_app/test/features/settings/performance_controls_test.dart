import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/display/display_refresh.dart';
import 'package:mtm/core/display/frame_rate.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/theme_state.dart';
import 'package:mtm/features/settings/data/frame_rate_provider.dart';
import 'package:mtm/features/settings/data/motion_level_provider.dart';
import 'package:mtm/features/settings/data/settings_providers.dart';
import 'package:mtm/features/settings/domain/settings_models.dart';
import 'package:mtm/features/settings/domain/settings_repository.dart';
import 'package:mtm/features/settings/presentation/themes_and_performance_page.dart';
import 'package:mtm/l10n/strings.dart';

/// The performance half of the canonical Themes & Performance screen
/// (`/more/themes`): performance level and frame rate. Same providers, same
/// definitions, same OS reduce-motion and lowest-level behaviour as when
/// these lived on their own screen — only the surface they sit on changed.
class _FakeSettingsRepository implements SettingsRepository {
  MotionLevel? motion;
  FrameRatePreference? rate;
  int motionWrites = 0;
  int rateWrites = 0;

  @override
  Future<Result<MotionLevel?>> motionLevel() async => Success(motion);
  @override
  Future<Result<MotionLevel>> updateMotionLevel(MotionLevel level) async {
    motionWrites++;
    motion = level;
    return Success(level);
  }

  @override
  Future<Result<FrameRatePreference?>> frameRate() async => Success(rate);
  @override
  Future<Result<FrameRatePreference>> updateFrameRate(
      FrameRatePreference p) async {
    rateWrites++;
    rate = p;
    return Success(p);
  }

  @override
  Future<Result<ThemeState?>> themePrefs() async =>
      const Success(ThemeState.initial());
  @override
  Future<Result<ThemeState>> updateThemePrefs(ThemeState prefs) async =>
      Success(prefs);
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

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _FakeSettingsRepository repo,
  List<double> displayRates = const [60],
}) async {
  final container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(repo),
      displayCapabilitiesProvider.overrideWith(
        (ref) async => DisplayCapabilities(
          supportedRates: displayRates,
          activeRate: displayRates.first,
          canSelectMode: displayRates.length > 1,
          supportsFrameRateHint: false,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  // A phone-tall surface: the canonical screen carries the theme cards
  // above these controls, and the default 800x600 test window puts the
  // frame-rate pills past its bottom edge.
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: ThemesAndPerformancePage(),
        ),
      ),
    ),
  );
  // Not `pumpAndSettle`: both pickers show a `CircularProgressIndicator`
  // while their stored preference loads, an indeterminate animation that
  // never lets `pumpAndSettle` conclude. Bounded pumps clear the mock
  // repository's simulated latency.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return container;
}

/// Builds and scrolls a control into view before interacting with it. The
/// performance controls follow the complete six-palette catalogue, so a
/// `ListView` does not build them until the test scrolls toward them.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

Future<void> _tapPill(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  // `FrameRateController.build()`/`.set()` call the real
  // `displayRefreshProvider` (not overridden by `displayCapabilitiesProvider`
  // above, which only feeds the picker's own display), which otherwise hits
  // the real `mtm/display` platform channel — no handler here, matching
  // `frame_rate_test.dart`'s own established pattern for this channel.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(DisplayRefresh.channelName),
      (call) async => null,
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel(DisplayRefresh.channelName), null);
  });

  testWidgets('shows every existing motion-quality and frame-rate choice',
      (tester) async {
    await _pump(
      tester,
      repo: _FakeSettingsRepository(),
      displayRates: const [60, 90, 120],
    );

    expect(find.text(S.sectionThemesPerformance), findsOneWidget);
    for (final label in [
      S.settingsMotionPerformance,
      S.settingsMotionLow,
      S.settingsMotionBalanced,
      S.settingsMotionHigh,
      S.settingsMotionMaximum,
    ]) {
      await _reveal(tester, find.text(label));
      expect(find.text(label), findsOneWidget, reason: label);
    }
    for (final label in [
      S.settingsFrameRateAuto,
      S.settingsFrameRate60,
      S.settingsFrameRate90,
      S.settingsFrameRate120,
    ]) {
      await _reveal(tester, find.text(label));
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('picking a motion level persists through the existing provider',
      (tester) async {
    final repo = _FakeSettingsRepository();
    final container = await _pump(tester, repo: repo);
    await container.read(motionLevelProvider.future);

    await _tapPill(tester, find.text(S.settingsMotionHigh));

    expect(container.read(motionLevelProvider).valueOrNull, MotionLevel.high);
    expect(repo.motion, MotionLevel.high);
    expect(repo.motionWrites, 1);
  });

  testWidgets('picking a frame rate persists through the existing provider',
      (tester) async {
    final repo = _FakeSettingsRepository();
    final container = await _pump(
      tester,
      repo: repo,
      displayRates: const [60, 90, 120],
    );
    await container.read(frameRateProvider.future);

    await _tapPill(tester, find.text(S.settingsFrameRate90));

    expect(
      container.read(frameRateProvider).valueOrNull,
      FrameRatePreference.fps90,
    );
    expect(repo.rate, FrameRatePreference.fps90);
    expect(repo.rateWrites, 1);
  });

  testWidgets(
      'an OS reduce-motion request is shown as overriding the chosen level',
      (tester) async {
    final repo = _FakeSettingsRepository();
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        displayCapabilitiesProvider.overrideWith(
          (ref) async => const DisplayCapabilities(
            supportedRates: [60],
            activeRate: 60,
            canSelectMode: false,
            supportsFrameRateHint: false,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.medical),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: true, accessibleNavigation: true),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: child!,
            ),
          ),
          home: const ThemesAndPerformancePage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await _reveal(tester, find.text(S.settingsMotionOsNotice));
    expect(find.text(S.settingsMotionOsNotice), findsOneWidget);
  });
}
