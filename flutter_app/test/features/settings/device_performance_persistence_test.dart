import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/display/display_refresh.dart';
import 'package:mtm/core/display/frame_rate.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/startup/intro_gate.dart';
import 'package:mtm/core/storage/local_store.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/theme_controller.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/persistent_demo_session_store.dart';
import 'package:mtm/features/auth/presentation/entry_glass.dart';
import 'package:mtm/features/auth/presentation/leader_intro.dart';
import 'package:mtm/features/auth/presentation/login_page.dart';
import 'package:mtm/features/settings/data/device_settings_bootstrap.dart';
import 'package:mtm/features/settings/data/frame_rate_provider.dart';
import 'package:mtm/features/settings/data/mock_settings_repository.dart';
import 'package:mtm/features/settings/data/motion_level_provider.dart';
import 'package:mtm/features/settings/data/settings_providers.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(DisplayRefresh.channelName),
      (call) async {
        if (call.method == 'capabilities') {
          return {
            'supportedRates': [60.0, 90.0, 120.0],
            'activeRate': 60.0,
            'canSelectMode': true,
            'supportsFrameRateHint': false,
          };
        }
        return (call.arguments as Map<Object?, Object?>?)?['hz'];
      },
    );
    IntroGate.resetForTest();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(DisplayRefresh.channelName),
      null,
    );
    IntroGate.resetForTest();
  });

  ProviderContainer containerFor(InMemoryLocalStore store) => ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );

  test('motion and frame rate survive repository/controller recreation',
      () async {
    final store = InMemoryLocalStore();
    final first = containerFor(store);
    await first.read(motionLevelProvider.future);
    await first.read(frameRateProvider.future);
    await first.read(motionLevelProvider.notifier).set(MotionLevel.maximum);
    await first.read(frameRateProvider.notifier).set(FrameRatePreference.fps90);
    first.dispose();

    final relaunched = containerFor(store);
    addTearDown(relaunched.dispose);
    expect(
        await relaunched.read(motionLevelProvider.future), MotionLevel.maximum);
    expect(await relaunched.read(frameRateProvider.future),
        FrameRatePreference.fps90);
  });

  test('clearing the device login record does not erase performance', () async {
    final store = InMemoryLocalStore();
    final settings = MockSettingsRepository(localStore: store);
    await settings.updateMotionLevel(MotionLevel.low);
    await settings.updateFrameRate(FrameRatePreference.fps60);

    // Ordinary development sign-out clears this record through the same
    // LocalStore. It must remove only auth state, never device preferences.
    final session = PersistentDemoSessionStore(store, seed: null);
    await session.write('super_admin_demo');
    await session.clear();

    final afterLogout = MockSettingsRepository(localStore: store);
    expect(
      (await afterLogout.motionLevel() as Success<MotionLevel?>).data,
      MotionLevel.low,
    );
    expect(
      (await afterLogout.frameRate() as Success<FrameRatePreference?>).data,
      FrameRatePreference.fps60,
    );
  });

  test('startup snapshot restores appearance, motion and frame rate together',
      () async {
    final store = InMemoryLocalStore();
    final first = MockSettingsRepository(localStore: store);
    const selectedTheme = ThemeState(
      palette: PaletteId.teal,
      mode: ThemeMode.dark,
      eyeProtect: true,
    );
    await first.updateThemePrefs(selectedTheme);
    await first.updateMotionLevel(MotionLevel.high);
    await first.updateFrameRate(FrameRatePreference.fps120);

    final snapshot = await loadDeviceSettings(
      MockSettingsRepository(localStore: store),
      osDisablesAnimations: false,
    );

    expect(snapshot.theme, selectedTheme);
    expect(snapshot.motionLevel, MotionLevel.high);
    expect(snapshot.frameRate, FrameRatePreference.fps120);
  });

  test('legacy motion names are restored through the durable store', () async {
    final store = InMemoryLocalStore({
      MockSettingsRepository.motionLevelKey: 'full',
      MockSettingsRepository.frameRateKey: 'fps90',
    });
    final repository = MockSettingsRepository(localStore: store);

    expect(
      (await repository.motionLevel() as Success<MotionLevel?>).data,
      MotionLevel.high,
    );
    expect(
      (await repository.frameRate() as Success<FrameRatePreference?>).data,
      FrameRatePreference.fps90,
    );
  });

  testWidgets(
      'the preloaded performance setting reaches Intro and Login immediately',
      (tester) async {
    final store = InMemoryLocalStore();
    final repository = MockSettingsRepository(localStore: store);
    const selectedTheme = ThemeState(
      palette: PaletteId.teal,
      mode: ThemeMode.dark,
      eyeProtect: true,
    );
    await store.writeString(
      MockSettingsRepository.themePrefsKey,
      jsonEncode(selectedTheme.toJson()),
    );
    await repository.updateMotionLevel(MotionLevel.performance);
    final snapshot = await loadDeviceSettings(
      repository,
      osDisablesAnimations: false,
    );

    final container = ProviderContainer(overrides: [
      localStoreProvider.overrideWithValue(store),
      settingsRepositoryProvider.overrideWithValue(repository),
      deviceSettingsSnapshotProvider.overrideWithValue(snapshot),
    ]);
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    Widget host(Widget screen) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(PaletteId.teal, eyeProtect: true),
            darkTheme: AppTheme.dark(PaletteId.teal, eyeProtect: true),
            themeMode: ThemeMode.dark,
            builder: (context, child) => Consumer(
              builder: (context, ref, _) => Directionality(
                textDirection: TextDirection.rtl,
                child: MotionScope(
                  level: ref.watch(activeMotionLevelProvider),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
            home: screen,
          ),
        );

    await tester.pumpWidget(host(const LeaderIntro()));

    expect(find.byType(LeaderIntro), findsOneWidget);
    expect(tester.widget<MotionScope>(find.byType(MotionScope)).level,
        MotionLevel.performance);
    expect(container.read(themeStateProvider), selectedTheme);
    expect(tester.hasRunningAnimations, isFalse,
        reason: 'Intro must not start a temporary balanced animation');

    await tester.pumpWidget(host(const LoginPage()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(EntryPulse), findsOneWidget);
    expect(tester.widget<MotionScope>(find.byType(MotionScope)).level,
        MotionLevel.performance);
    expect(
      find.descendant(
        of: find.byType(EntryPulse),
        matching: find.byType(AnimatedBuilder),
      ),
      findsNothing,
      reason: 'Login receives the same stored performance profile and does '
          'not create the pulse controller',
    );
  });
}
