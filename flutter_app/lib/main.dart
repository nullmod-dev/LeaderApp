import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/display/display_refresh.dart';
import 'core/motion/motion_level.dart';
import 'core/router/app_router.dart';
import 'core/startup/intro_gate.dart';
import 'core/storage/local_store.dart';
import 'core/sync/sync_scheduler.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/auth/data/auth_providers.dart' show localStoreProvider;
import 'features/auth/data/onboarding_controller.dart';
import 'features/conflict/data/conflict_review_recording.dart';
import 'features/settings/data/device_settings_bootstrap.dart';
import 'features/settings/data/frame_rate_provider.dart';
import 'features/settings/data/mock_settings_repository.dart';
import 'features/settings/data/motion_level_provider.dart';
import 'features/settings/data/settings_providers.dart';
import 'features/shift/data/shift_conflict_review.dart';
import 'l10n/strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  // Appearance, animation quality and refresh rate belong to the device, not
  // to an authenticated account. Hydrate them while the native launch window
  // is still up so Intro/Login never paint a temporary profile and switch a
  // frame later. The same store and repository are then injected below; this
  // is a preload of the existing architecture, not a second settings store.
  final localStore = SharedPreferencesLocalStore();
  final settingsRepository = MockSettingsRepository(localStore: localStore);
  final deviceSettings = await loadDeviceSettings(
    settingsRepository,
    osDisablesAnimations: WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations,
  );
  final displayRefresh = DisplayRefresh();
  await displayRefresh.apply(deviceSettings.frameRate);
  // This is a cold process launch, and the only place that is ever true — so
  // it is the only place the Leader intro is armed. Before `runApp`, so the
  // first read of `introGateProvider` already reports the hold and the router
  // never has to be told to change its mind mid-mount. Nothing re-arms it;
  // signing out, tab changes and returning from the background cannot replay
  // it. See `core/startup/intro_gate.dart`.
  IntroGate.armColdLaunch();
  // The composition root installs the conflict feature's review recorder
  // over `core/sync`'s no-op hook, and the Shift feature's composer/applier
  // over `features/conflict`'s empty registries, so a conflict classified by
  // Auto Sync can store safe review metadata — and a later `useCurrent` can
  // apply it — for the Needs Review inbox without core sync or the generic
  // conflict feature ever importing a feature themselves.
  runApp(ProviderScope(
    overrides: [
      localStoreProvider.overrideWithValue(localStore),
      settingsRepositoryProvider.overrideWithValue(settingsRepository),
      deviceSettingsSnapshotProvider.overrideWithValue(deviceSettings),
      displayRefreshProvider.overrideWithValue(displayRefresh),
      ...conflictReviewOverrides,
      ...shiftConflictReviewOverrides,
    ],
    child: const MtmApp(),
  ));
}

bool shouldUseImmersiveSystemUi({
  required bool isWeb,
  required TargetPlatform platform,
}) =>
    !isWeb && platform == TargetPlatform.android;

class MtmApp extends ConsumerStatefulWidget {
  const MtmApp({super.key});

  @override
  ConsumerState<MtmApp> createState() => _MtmAppState();
}

class _MtmAppState extends ConsumerState<MtmApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyAndroidSystemUi();
    // Point 17B — hydrate the pre-session journey from the device vault.
    // Deferred to a post-frame callback, like Auto Sync below: calling
    // `restore()` synchronously in `initState` sets provider state while
    // GoRouter's `refreshListenable` is still mounting for the very first
    // frame, and that reentrant rebuild-during-mount is what corrupted the
    // element tree (`'_elements.contains(element)'`) under
    // `admin_profile_test.dart`. A post-frame callback still runs before the
    // classifier can settle on anything: `currentUser()`'s own restore takes
    // real latency in every build, real or mocked, so `AuthGate.restoring`
    // already holds `/startup` for longer than this needs.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(onboardingControllerProvider.notifier).restore(),
    );
    // Auto Sync is the primary path: once the app is up, ask the
    // coordinator to drain anything left pending from a previous run. It is
    // a no-op when the outbox is empty.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => ref.read(syncSchedulerProvider).onAppStart(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyAndroidSystemUi();
      ref.read(syncSchedulerProvider).onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _applyAndroidSystemUi() async {
    if (!shouldUseImmersiveSystemUi(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      return;
    }
    // Android's supported sticky transient-reveal behavior is exposed by
    // immersiveSticky. Flutter applies it once here and again on resume,
    // never during build or while a text field/dialog is interacting. The
    // mode hides both system bars; an edge swipe reveals them temporarily.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final theme = ref.watch(themeStateProvider);

    final motion = ref.watch(activeMotionLevelProvider);
    // Watched, not read: the platform forgets the refresh-rate preference
    // between launches, and this provider's `build` is what restores it.
    // Nothing is rendered from the value — the display is the output.
    ref.watch(frameRateProvider);

    return MaterialApp.router(
      title: S.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      // Global RTL + MotionScope for the whole subtree.
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: MotionScope(
            // The stored value was available before runApp. Accessibility
            // still wins inside motionSpec(), including on the first frame.
            level: motion,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      theme: AppTheme.light(theme.palette, eyeProtect: theme.eyeProtect),
      darkTheme: AppTheme.dark(theme.palette, eyeProtect: theme.eyeProtect),
      themeMode: theme.mode,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
