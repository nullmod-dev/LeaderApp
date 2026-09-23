import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/display/frame_rate.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/storage/local_store.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/theme_controller.dart';
import 'package:mtm/features/settings/data/settings_providers.dart';
import 'package:mtm/features/settings/data/mock_settings_repository.dart';
import 'package:mtm/features/settings/domain/settings_models.dart';
import 'package:mtm/features/settings/domain/settings_repository.dart';

/// The theme picker used to be a plain in-memory `Notifier`: every choice was
/// forgotten the moment the app was killed. These tests pin the seam that
/// fixed it — the controller must read the stored value on build and write
/// every change back through [SettingsRepository].
void main() {
  group('theme persistence', () {
    test('an untouched install opens on the default theme', () async {
      final repo = _FakeSettingsRepository();
      final container = _containerWith(repo);

      final state = await container.read(themeControllerProvider.future);

      expect(state, const ThemeState.initial());
      expect(state.palette, PaletteId.medical);
      expect(state.mode, ThemeMode.light);
      expect(state.eyeProtect, isFalse);
    });

    test('each setter writes through to the repository', () async {
      final repo = _FakeSettingsRepository();
      final container = _containerWith(repo);
      await container.read(themeControllerProvider.future);
      final controller = container.read(themeControllerProvider.notifier);

      await controller.setPalette(PaletteId.copper);
      await controller.setMode(ThemeMode.dark);
      await controller.setEyeProtect(true);

      expect(repo.stored?.palette, PaletteId.copper);
      expect(repo.stored?.mode, ThemeMode.dark);
      expect(repo.stored?.eyeProtect, isTrue);
      expect(repo.writes, 3, reason: 'one write per change, no extras');
    });

    test('a relaunch restores what was stored', () async {
      final repo = _FakeSettingsRepository();

      final first = _containerWith(repo);
      await first.read(themeControllerProvider.future);
      await first
          .read(themeControllerProvider.notifier)
          .setPalette(PaletteId.indigo);
      await first.read(themeControllerProvider.notifier).setEyeProtect(true);
      first.dispose();

      // A second container is a fresh app launch against the same store.
      final second = _containerWith(repo);
      final restored = await second.read(themeControllerProvider.future);

      expect(restored.palette, PaletteId.indigo);
      expect(restored.eyeProtect, isTrue);
    });

    test('re-picking the current value does not write again', () async {
      final repo = _FakeSettingsRepository();
      final container = _containerWith(repo);
      await container.read(themeControllerProvider.future);
      final controller = container.read(themeControllerProvider.notifier);

      await controller.setPalette(PaletteId.medical); // already the default
      expect(repo.writes, 0);

      await controller.setPalette(PaletteId.clay);
      await controller.setPalette(PaletteId.clay);
      expect(repo.writes, 1);
    });

    test('a failed read still yields a usable theme', () async {
      final repo = _FakeSettingsRepository(failReads: true);
      final container = _containerWith(repo);

      expect(
        await container.read(themeControllerProvider.future),
        const ThemeState.initial(),
      );
    });

    test('themeStateProvider serves the default before the read lands',
        () async {
      final repo = _FakeSettingsRepository();
      repo.stored = const ThemeState(
        palette: PaletteId.copper,
        mode: ThemeMode.dark,
      );
      final container = _containerWith(repo);

      // Nothing has been awaited yet, so the app is still painting frames.
      expect(container.read(themeStateProvider), const ThemeState.initial());

      await container.read(themeControllerProvider.future);
      expect(container.read(themeStateProvider).palette, PaletteId.copper);
    });
  });

  group('ThemeState', () {
    test('survives a json round-trip', () {
      const original = ThemeState(
        palette: PaletteId.indigo,
        mode: ThemeMode.system,
        eyeProtect: true,
      );
      expect(ThemeState.fromJson(original.toJson()), original);
    });

    test('falls back rather than throwing on a value it does not know', () {
      // A palette removed in a later build must not brick the app on launch.
      final state = ThemeState.fromJson(const {
        'palette': 'chartreuse',
        'mode': 'sepia',
        'eyeProtect': null,
      });
      expect(state, const ThemeState.initial());
    });

    test('is compared by value', () {
      expect(
        const ThemeState(palette: PaletteId.teal, mode: ThemeMode.dark),
        const ThemeState(palette: PaletteId.teal, mode: ThemeMode.dark),
      );
      expect(
        const ThemeState(palette: PaletteId.teal, mode: ThemeMode.dark),
        isNot(const ThemeState(palette: PaletteId.teal, mode: ThemeMode.light)),
      );
    });
  });

  group('device persistence', () {
    test('a new repository restores palette, appearance and Eye Protection',
        () async {
      final store = InMemoryLocalStore();
      final first = MockSettingsRepository(localStore: store);
      const selected = ThemeState(
        palette: PaletteId.clay,
        mode: ThemeMode.system,
        eyeProtect: true,
      );
      await first.updateThemePrefs(selected);

      final relaunched = MockSettingsRepository(localStore: store);
      final result = await relaunched.themePrefs();
      expect((result as Success<ThemeState?>).data, selected);
    });

    test('corrupt and unknown stored values fall back without wiping storage',
        () async {
      for (final raw in [
        'not-json',
        '{"palette":"removed","mode":"future","eyeProtect":true}',
      ]) {
        final store = InMemoryLocalStore({
          MockSettingsRepository.themePrefsKey: raw,
          'unrelated': 'keep-me',
        });
        final result =
            await MockSettingsRepository(localStore: store).themePrefs();
        final value = (result as Success<ThemeState?>).data;
        if (raw == 'not-json') {
          expect(value, isNull);
        } else {
          expect(value!.palette, PaletteId.medical);
          expect(value.mode, ThemeMode.light);
          expect(value.eyeProtect, isTrue,
              reason: 'a valid independent comfort setting is preserved');
        }
        expect(store.values['unrelated'], 'keep-me');
      }
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

/// Latency-free stand-in for [SettingsRepository] that keeps only what these
/// tests read. The shipped mock sleeps 400–800 ms per call, which would make
/// a round-trip test slow for no added confidence.
class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({this.failReads = false});

  final bool failReads;
  ThemeState? stored;
  int writes = 0;

  @override
  Future<Result<ThemeState?>> themePrefs() async =>
      failReads ? const Failure('boom') : Success(stored);

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
