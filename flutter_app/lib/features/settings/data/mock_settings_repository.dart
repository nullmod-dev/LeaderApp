import 'dart:math';
import 'dart:convert';

import '../../../core/display/frame_rate.dart';
import '../../../core/motion/motion_level.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/local_store.dart';
import '../../../core/theme/theme_state.dart';
import '../domain/settings_models.dart';
import '../domain/settings_repository.dart';

class MockSettingsRepository implements SettingsRepository {
  MockSettingsRepository({LocalStore? localStore}) : _localStore = localStore;

  static const themePrefsKey = 'mtm.settings.theme';
  static const motionLevelKey = 'mtm.settings.motion';
  static const frameRateKey = 'mtm.settings.frame_rate';

  final LocalStore? _localStore;
  final _rand = Random(71);

  NotificationPrefs _prefs = const NotificationPrefs(
    shiftReminders: true,
    stockAlerts: true,
    workshopUpdates: true,
    joinRequests: false,
  );

  // Caches for the device-level preferences. The LocalStore remains the
  // source of truth across repository recreation and process death.
  MotionLevel? _motionLevel;
  FrameRatePreference? _frameRate;
  ThemeState? _themePrefs;

  Future<void> _latency() => Future<void>.delayed(
        Duration(milliseconds: 400 + _rand.nextInt(400)),
      );

  @override
  Future<Result<NotificationPrefs>> notificationPrefs() async {
    await _latency();
    return Success(_prefs);
  }

  @override
  Future<Result<NotificationPrefs>> updateNotificationPrefs(
      NotificationPrefs p) async {
    await _latency();
    _prefs = p;
    return Success(p);
  }

  @override
  Future<Result<MotionLevel?>> motionLevel() async {
    if (_motionLevel case final cached?) return Success(cached);
    final raw = await _localStore?.readString(motionLevelKey);
    if (raw == null) return const Success(null);
    final restored = MotionLevel.fromJson(raw);
    _motionLevel = restored;
    return Success(restored);
  }

  @override
  Future<Result<MotionLevel>> updateMotionLevel(MotionLevel level) async {
    _motionLevel = level;
    await _localStore?.writeString(motionLevelKey, level.toJson());
    return Success(level);
  }

  @override
  Future<Result<FrameRatePreference?>> frameRate() async {
    if (_frameRate case final cached?) return Success(cached);
    final raw = await _localStore?.readString(frameRateKey);
    if (raw == null) return const Success(null);
    final restored = FrameRatePreference.fromJson(raw);
    _frameRate = restored;
    return Success(restored);
  }

  @override
  Future<Result<FrameRatePreference>> updateFrameRate(
      FrameRatePreference p) async {
    _frameRate = p;
    await _localStore?.writeString(frameRateKey, p.toJson());
    return Success(p);
  }

  /// Deliberately **not** behind [_latency].
  ///
  /// This read sits on the launch path alongside motion and frame rate. All
  /// three are local device preferences; none models a server round trip.
  @override
  Future<Result<ThemeState?>> themePrefs() async {
    if (_themePrefs case final cached?) return Success(cached);
    final raw = await _localStore?.readString(themePrefsKey);
    if (raw == null) return const Success(null);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const Success(null);
      final restored = ThemeState.fromJson(Map<String, dynamic>.from(decoded));
      _themePrefs = restored;
      return Success(restored);
    } catch (_) {
      // A corrupt or legacy value is only a lost preference. It must never
      // prevent startup or cause unrelated settings to be wiped.
      return const Success(null);
    }
  }

  @override
  Future<Result<ThemeState>> updateThemePrefs(ThemeState prefs) async {
    await _latency();
    _themePrefs = prefs;
    await _localStore?.writeString(themePrefsKey, jsonEncode(prefs.toJson()));
    return Success(prefs);
  }

  @override
  Future<Result<OrgInfo>> orgInfo() async {
    await _latency();
    return const Success(OrgInfo(
      name: 'فريق الإسعاف التطوعي',
      legalName: 'جمعية الإسعاف الأهلي التطوعية',
      address: 'دمشق, سوريا',
      emailPublic: 'contact@mtm.org',
      detachmentCount: 5,
      memberCount: 25,
    ));
  }
}
