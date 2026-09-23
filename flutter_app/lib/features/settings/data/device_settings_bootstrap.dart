import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/display/frame_rate.dart';
import '../../../core/motion/motion_level.dart';
import '../../../core/theme/theme_state.dart';
import '../domain/settings_repository.dart';

/// The local, device-level settings that must exist before the first Flutter
/// frame is painted.
///
/// Login and the cold-launch intro are part of the app, not a temporary
/// pre-authentication environment. They therefore need the same appearance
/// and performance choices as the authenticated shell. `main()` loads this
/// snapshot from [SettingsRepository] before `runApp`, while the normal
/// controllers continue to own live changes after launch.
class DeviceSettingsSnapshot {
  const DeviceSettingsSnapshot({
    required this.theme,
    required this.motionLevel,
    required this.frameRate,
  });

  const DeviceSettingsSnapshot.initial()
      : theme = const ThemeState.initial(),
        motionLevel = MotionLevel.balanced,
        frameRate = FrameRatePreference.auto;

  final ThemeState theme;
  final MotionLevel motionLevel;
  final FrameRatePreference frameRate;
}

/// Loads all launch-critical preferences together from the existing settings
/// repository. The reads are started together so the native splash is held
/// only for one local-storage round trip, not three serial ones.
Future<DeviceSettingsSnapshot> loadDeviceSettings(
  SettingsRepository repository, {
  required bool osDisablesAnimations,
}) async {
  final themeFuture = repository.themePrefs();
  final motionFuture = repository.motionLevel();
  final frameRateFuture = repository.frameRate();

  final themeResult = await themeFuture;
  final motionResult = await motionFuture;
  final frameRateResult = await frameRateFuture;

  final theme = themeResult.when<ThemeState?>(
        success: (value, {stale = false}) => value,
        failure: (_, __) => null,
        offline: (cached) => cached,
      ) ??
      const ThemeState.initial();
  final motion = motionResult.when<MotionLevel?>(
        success: (value, {stale = false}) => value,
        failure: (_, __) => null,
        offline: (cached) => cached,
      ) ??
      (osDisablesAnimations ? MotionLevel.performance : MotionLevel.balanced);
  final frameRate = frameRateResult.when<FrameRatePreference?>(
        success: (value, {stale = false}) => value,
        failure: (_, __) => null,
        offline: (cached) => cached,
      ) ??
      FrameRatePreference.auto;

  return DeviceSettingsSnapshot(
    theme: theme,
    motionLevel: motion,
    frameRate: frameRate,
  );
}

/// The snapshot available synchronously to the app root.
///
/// `main()` overrides this with the value loaded before `runApp`. The default
/// keeps widget tests and alternate embedders usable when they construct
/// the application widget directly.
final deviceSettingsSnapshotProvider = Provider<DeviceSettingsSnapshot>(
  (ref) => const DeviceSettingsSnapshot.initial(),
);
