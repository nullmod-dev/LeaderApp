import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/display/frame_rate.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/theme_controller.dart';
import 'package:mtm/features/settings/data/settings_providers.dart';
import 'package:mtm/features/settings/domain/settings_models.dart';
import 'package:mtm/features/settings/domain/settings_repository.dart';

/// The product exposes all six historical palettes in both brightnesses.
/// These tests pin the one-to-one catalogue and the independence of reading
/// comfort and appearance.
void main() {
  group('the six product palettes', () {
    test('each maps one-to-one to the palette engine', () {
      expect(AppThemeChoice.values, hasLength(6));
      expect(
        AppThemeChoice.values.map((choice) => choice.palette).toSet(),
        PaletteId.values.toSet(),
      );
    });

    test('appearance is available for every palette', () {
      for (final choice in AppThemeChoice.values) {
        expect(choice.hasModeChoice, isTrue, reason: choice.name);
      }
    });

    test('the default install uses the historical medical light pair', () {
      expect(const ThemeState.initial().choice, AppThemeChoice.medical);
      expect(const ThemeState.initial().mode, ThemeMode.light);
      expect(const ThemeState.initial().eyeProtect, isFalse);
    });

    test('every palette resolves to its own offered choice', () {
      for (final palette in PaletteId.values) {
        expect(AppThemeChoice.ofPalette(palette).palette, palette);
      }
    });

    test('switching palette leaves appearance and comfort alone', () {
      const start = ThemeState(
        palette: PaletteId.medical,
        mode: ThemeMode.system,
        eyeProtect: true,
      );

      final teal = start.withChoice(AppThemeChoice.teal);
      expect(teal.palette, PaletteId.teal);
      expect(teal.mode, ThemeMode.system);
      expect(teal.eyeProtect, isTrue, reason: 'comfort is not a palette');

      // Re-picking the theme already in use changes nothing — a light-theme
      // user on dark mode does not lose it by tapping their own card.
      expect(start.withChoice(AppThemeChoice.light), start);
    });

    test('every historical palette/mode pair remains valid', () {
      const legacy = ThemeState(palette: PaletteId.teal, mode: ThemeMode.light);
      final fixed = legacy.normalizedForChoice();
      expect(fixed, legacy);
      expect(fixed.choice, AppThemeChoice.teal);
    });

    test('an unreadable stored theme falls back to the default', () {
      final state = ThemeState.fromJson(const {
        'palette': 'chartreuse',
        'mode': 'sepia',
        'eyeProtect': null,
      });
      expect(state, const ThemeState.initial());
      expect(state.choice, AppThemeChoice.medical);
    });
  });

  group('reading comfort is independent of the theme', () {
    test('all four theme/comfort combinations resolve, and differ', () {
      final combinations = <String, ThemeData>{
        'light off': AppTheme.light(PaletteId.medical),
        'light on': AppTheme.light(PaletteId.medical, eyeProtect: true),
        'dark off': AppTheme.dark(PaletteId.teal),
        'dark on': AppTheme.dark(PaletteId.teal, eyeProtect: true),
      };
      final grounds =
          combinations.values.map((t) => t.scaffoldBackgroundColor).toSet();
      expect(grounds.length, 4, reason: 'each combination is its own ground');
    });

    test('comfort warms the ground and leaves meaning alone', () {
      for (final palette in [PaletteId.teal, PaletteId.indigo]) {
        for (final brightness in Brightness.values) {
          final plain = AppColors.resolve(palette, brightness);
          final warm = plain.warmed();

          expect(warm.bg, isNot(plain.bg), reason: '${palette.name} ground');
          // The colours that carry meaning are byte-identical: a warning
          // under comfort mode is the same warning.
          expect(warm.ok, plain.ok);
          expect(warm.warn, plain.warn);
          expect(warm.crit, plain.crit);
          expect(warm.info, plain.info);
          expect(warm.primary, plain.primary);
          expect(warm.ink, plain.ink);
        }
      }
    });

    test('comfort does not move the theme identity', () {
      const state = ThemeState(palette: PaletteId.teal, mode: ThemeMode.dark);
      final on = state.copyWith(eyeProtect: true);
      expect(on.choice, state.choice);
      expect(on.palette, state.palette);
      expect(on.mode, state.mode);
    });
  });

  group('the controller', () {
    test('picking a theme writes palette and mode as one change', () async {
      final repo = _FakeSettingsRepository();
      final container = _containerWith(repo);
      await container.read(themeControllerProvider.future);
      final controller = container.read(themeControllerProvider.notifier);

      await controller.setThemeChoice(AppThemeChoice.indigo);

      expect(repo.stored?.palette, PaletteId.indigo);
      expect(repo.stored?.mode, ThemeMode.light);
      expect(repo.writes, 1, reason: 'one change, one write');
    });

    test('turning comfort on does not disturb the stored theme', () async {
      final repo = _FakeSettingsRepository();
      final container = _containerWith(repo);
      await container.read(themeControllerProvider.future);
      final controller = container.read(themeControllerProvider.notifier);

      await controller.setThemeChoice(AppThemeChoice.indigo);
      await controller.setEyeProtect(true);
      await controller.setThemeChoice(AppThemeChoice.clay);

      // The theme moved; comfort stayed on across the switch.
      expect(repo.stored?.eyeProtect, isTrue);
      expect(repo.stored?.palette, PaletteId.clay);
    });

    test('a historical stored pair is preserved on hydration', () async {
      final repo = _FakeSettingsRepository()
        ..stored = const ThemeState(
          palette: PaletteId.indigo,
          mode: ThemeMode.light,
        );
      final container = _containerWith(repo);

      final state = await container.read(themeControllerProvider.future);
      expect(state.choice, AppThemeChoice.indigo);
      expect(state.mode, ThemeMode.light);
      expect(repo.writes, 0, reason: 'a repair costs no write');
    });

    test('a write that throws never rolls the applied theme back', () async {
      final repo = _FakeSettingsRepository(failWrites: true);
      final container = _containerWith(repo);
      await container.read(themeControllerProvider.future);
      final controller = container.read(themeControllerProvider.notifier);

      await controller.setThemeChoice(AppThemeChoice.clay);
      await controller.setEyeProtect(true);

      final state = container.read(themeStateProvider);
      expect(state.choice, AppThemeChoice.clay);
      expect(state.eyeProtect, isTrue);
      expect(repo.stored, isNull, reason: 'the store really did refuse');
    });
  });
}

ProviderContainer _containerWith(SettingsRepository repo) {
  final container = ProviderContainer(
    overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  return container;
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({this.failWrites = false});

  final bool failWrites;
  ThemeState? stored;
  int writes = 0;

  @override
  Future<Result<ThemeState?>> themePrefs() async => Success(stored);

  @override
  Future<Result<ThemeState>> updateThemePrefs(ThemeState prefs) async {
    writes++;
    if (failWrites) throw StateError('storage unavailable');
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
