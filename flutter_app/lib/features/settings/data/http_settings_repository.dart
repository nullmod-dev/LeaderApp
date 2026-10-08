import '../../../core/display/frame_rate.dart';
import '../../../core/motion/motion_level.dart';
import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/theme_state.dart';
import '../domain/settings_models.dart';
import '../domain/settings_repository.dart';

/// `/settings/notifications` and `/settings/organization`
/// (`docs/api/tenant-administration.md` §§1–2).
///
/// Appearance, animation quality and frame rate belong to the **device**, not
/// to an account (the backend deliberately has no endpoint for them), so
/// those six methods go to [_device] — the same local-store repository
/// `main()` hydrates before the first frame.
class HttpSettingsRepository implements SettingsRepository {
  HttpSettingsRepository(this._api, {required SettingsRepository device})
      : _device = device;

  final ApiClient _api;
  final SettingsRepository _device;

  @override
  Future<Result<NotificationPrefs>> notificationPrefs() => _api.send(
        'GET',
        '/settings/notifications',
        parse: (json) =>
            NotificationPrefs.fromJson(json as Map<String, dynamic>),
      );

  @override
  Future<Result<NotificationPrefs>> updateNotificationPrefs(
    NotificationPrefs p,
  ) =>
      _api.send(
        'PUT',
        '/settings/notifications',
        body: p.toJson(),
        parse: (json) =>
            NotificationPrefs.fromJson(json as Map<String, dynamic>),
      );

  /// Optional text fields are omitted by the server when unset.
  @override
  Future<Result<OrgInfo>> orgInfo() => _api.send(
        'GET',
        '/settings/organization',
        parse: (json) {
          final j = json as Map<String, dynamic>;
          return OrgInfo(
            name: (j['name'] as String?) ?? '',
            legalName: (j['legalName'] as String?) ?? '',
            address: (j['address'] as String?) ?? '',
            emailPublic: (j['emailPublic'] as String?) ?? '',
            detachmentCount: (j['detachmentCount'] as int?) ?? 0,
            memberCount: (j['memberCount'] as int?) ?? 0,
          );
        },
      );

  @override
  Future<Result<MotionLevel?>> motionLevel() => _device.motionLevel();

  @override
  Future<Result<MotionLevel>> updateMotionLevel(MotionLevel level) =>
      _device.updateMotionLevel(level);

  @override
  Future<Result<FrameRatePreference?>> frameRate() => _device.frameRate();

  @override
  Future<Result<FrameRatePreference>> updateFrameRate(FrameRatePreference p) =>
      _device.updateFrameRate(p);

  @override
  Future<Result<ThemeState?>> themePrefs() => _device.themePrefs();

  @override
  Future<Result<ThemeState>> updateThemePrefs(ThemeState prefs) =>
      _device.updateThemePrefs(prefs);
}
