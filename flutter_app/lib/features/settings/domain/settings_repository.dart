import '../../../core/display/frame_rate.dart';
import '../../../core/motion/motion_level.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/theme_state.dart';
import 'settings_models.dart';

abstract class SettingsRepository {
  Future<Result<NotificationPrefs>> notificationPrefs();
  Future<Result<NotificationPrefs>> updateNotificationPrefs(
      NotificationPrefs p);
  Future<Result<OrgInfo>> orgInfo();

  /// Persisted motion level. Returns `null` on first run — the app then
  /// initialises from `MediaQuery.disableAnimations`.
  Future<Result<MotionLevel?>> motionLevel();
  Future<Result<MotionLevel>> updateMotionLevel(MotionLevel level);

  /// Persisted frame-rate target. Returns `null` on first run, which the
  /// app reads as [FrameRatePreference.auto] — the only choice that is
  /// valid on every device.
  Future<Result<FrameRatePreference?>> frameRate();
  Future<Result<FrameRatePreference>> updateFrameRate(FrameRatePreference p);

  /// Persisted palette / light-dark / eye-protect, as one value. Returns
  /// `null` on first run, which the app reads as [ThemeState.initial] — the
  /// clinical `medical` palette in light mode with the wash off.
  ///
  /// One accessor rather than three because the three are always read
  /// together on launch, and a half-applied theme is a visible glitch.
  Future<Result<ThemeState?>> themePrefs();
  Future<Result<ThemeState>> updateThemePrefs(ThemeState prefs);
}
