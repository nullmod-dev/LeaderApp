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
import 'package:mtm/core/theme/theme_controller.dart';
import 'package:mtm/features/settings/data/frame_rate_provider.dart';
import 'package:mtm/features/settings/data/settings_providers.dart';
import 'package:mtm/features/settings/domain/settings_models.dart';
import 'package:mtm/features/settings/domain/settings_repository.dart';
import 'package:mtm/features/settings/presentation/themes_and_performance_page.dart';
import 'package:mtm/features/settings/presentation/widgets/settings_widgets.dart';
import 'package:mtm/features/settings/presentation/widgets/theme_choice_card.dart';
import 'package:mtm/l10n/strings.dart';

/// The theme half of the one canonical Themes & Performance screen.
///
/// Pins the restored six-palette catalogue and the independent
/// Eye-Protection/appearance controls on the canonical screen.
class _FakeSettingsRepository implements SettingsRepository {
  ThemeState? stored;
  int writes = 0;

  @override
  Future<Result<ThemeState?>> themePrefs() async => Success(stored);

  @override
  Future<Result<ThemeState>> updateThemePrefs(ThemeState prefs) async {
    writes++;
    stored = prefs;
    return Success(prefs);
  }

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

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required _FakeSettingsRepository repo,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: ThemesAndPerformancePage(),
        ),
      ),
    ),
  );
  // Not `pumpAndSettle`: the performance pickers below show an indeterminate
  // spinner until their stored preference lands, which never settles.
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return container;
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // `FrameRateController` talks to the real display channel on build.
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

  testWidgets('offers all six palettes before comfort and appearance',
      (tester) async {
    await _pump(tester, repo: _FakeSettingsRepository());

    expect(find.text(S.sectionThemesPerformance), findsOneWidget); // AppBar
    expect(themeChoices, hasLength(6));
    expect(find.byType(ThemeChoiceCard), findsNWidgets(6));
    for (final label in [
      S.settingsPaletteMedical,
      S.settingsPaletteSlate,
      S.settingsPaletteCopper,
      S.settingsPaletteClay,
      S.settingsPaletteIndigo,
      S.settingsPaletteTeal,
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // Palette → Eye Protection → appearance → performance.
    expect(
      tester.getTopLeft(find.byType(ThemeChoiceCard).first).dy,
      lessThan(
          tester.getTopLeft(find.byKey(const Key('themes-eye-protection'))).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('themes-eye-protection'))).dy,
      lessThan(
          tester.getTopLeft(find.byKey(const Key('themes-appearance'))).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('themes-appearance'))).dy,
      lessThan(tester.getTopLeft(find.text(S.settingsQuality)).dy),
    );
  });

  testWidgets('an untouched install opens on Medical Light', (tester) async {
    final container = await _pump(tester, repo: _FakeSettingsRepository());
    await container.read(themeControllerProvider.future);

    expect(container.read(themeStateProvider).choice, AppThemeChoice.medical);
    expect(container.read(themeStateProvider).mode, ThemeMode.light);
  });

  testWidgets('picking a theme applies and persists it', (tester) async {
    final repo = _FakeSettingsRepository();
    final container = await _pump(tester, repo: repo);
    await container.read(themeControllerProvider.future);

    await tester.tap(find.text(S.settingsPaletteIndigo));
    await tester.pump();

    final state = container.read(themeStateProvider);
    expect(state.choice, AppThemeChoice.indigo);
    expect(state.palette, PaletteId.indigo);
    expect(state.mode, ThemeMode.light);
    expect(repo.stored?.palette, PaletteId.indigo);
    expect(repo.writes, 1);
  });

  testWidgets('Light Dark and System apply to every palette', (tester) async {
    final repo = _FakeSettingsRepository();
    final container = await _pump(tester, repo: repo);
    await container.read(themeControllerProvider.future);

    expect(find.text(S.settingsLightMode), findsOneWidget);
    await tester.tap(find.text(S.settingsModeDark));
    await tester.pump();
    final state = container.read(themeStateProvider);
    expect(state.mode, ThemeMode.dark);
    expect(state.choice, AppThemeChoice.medical);
    expect(state.palette, PaletteId.medical);
    expect(repo.stored?.mode, ThemeMode.dark);

    await tester.tap(find.text(S.settingsPaletteTeal));
    await tester.pump();
    expect(container.read(themeStateProvider).mode, ThemeMode.dark,
        reason: 'changing palette does not change appearance');
    await tester.tap(find.text(S.settingsModeSystem));
    await tester.pump();
    expect(container.read(themeStateProvider).mode, ThemeMode.system);
  });

  testWidgets('re-tapping the selected theme does not reset its mode',
      (tester) async {
    final repo = _FakeSettingsRepository();
    final container = await _pump(tester, repo: repo);
    await container.read(themeControllerProvider.future);

    await tester.tap(find.text(S.settingsPaletteMedical));
    await tester.pump();
    await tester.tap(find.text(S.settingsModeSystem));
    await tester.pump();
    await tester.tap(find.text(S.settingsPaletteMedical));
    await tester.pump();

    expect(container.read(themeStateProvider).mode, ThemeMode.system);
  });

  testWidgets('a narrow phone at a large text size does not break the cards',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
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
                .copyWith(textScaler: const TextScaler.linear(1.6)),
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

    expect(tester.takeException(), isNull);
  });

  testWidgets('a relaunch restores the theme chosen here', (tester) async {
    final repo = _FakeSettingsRepository();
    final first = await _pump(tester, repo: repo);
    await first.read(themeControllerProvider.future);
    await tester.tap(find.text(S.settingsPaletteClay));
    await tester.pump();
    first.dispose();

    // A second container against the same store is a fresh launch.
    final second = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(second.dispose);
    final restored = await second.read(themeControllerProvider.future);
    expect(restored.choice, AppThemeChoice.clay);
    expect(restored.palette, PaletteId.clay);
  });

  testWidgets('Eye Protection toggles without changing palette or appearance',
      (tester) async {
    final repo = _FakeSettingsRepository();
    final container = await _pump(tester, repo: repo);
    await container.read(themeControllerProvider.future);
    await tester.tap(find.text(S.settingsPaletteCopper));
    await tester.tap(find.text(S.settingsModeDark));
    await tester.tap(find.text(S.settingsEyeProtectOn));
    await tester.pump();

    final state = container.read(themeStateProvider);
    expect(state.palette, PaletteId.copper);
    expect(state.mode, ThemeMode.dark);
    expect(state.eyeProtect, isTrue);
  });
}
