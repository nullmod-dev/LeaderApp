import 'package:flutter/foundation.dart';

/// Where **this client** goes to update itself.
///
/// ## Ownership: client, not API
///
/// The backend decides *whether* a build is still supported and, when it
/// wants to, *what the minimum version is*. It does not decide *where the
/// app is installed from* — that is a fact about how this client was
/// shipped, and it is the same for every user on a platform whether or not
/// the network can be reached. Keeping it here means:
///
///   * a `426` body never has to carry a store URL;
///   * the update button works with no connectivity, from the persisted
///     gate (`AppVersionGateStore`), before any request succeeds;
///   * a wrong or hostile update URL from the wire can never redirect the
///     user off-store — the backend does not send one, and
///     `AppVersionSupport.fromJson` drops it if it appears.
///
/// See `FRONTEND-BACKEND-INTEGRATION.md` §1 — this fully closes the "who
/// owns the update destination" decision: the client does, with no wire
/// override.
abstract final class UpdateChannel {
  /// The Play Store listing for `applicationId = com.leader.teams`
  /// (`android/app/build.gradle.kts`). The `https` form resolves in a
  /// browser as well as the Play app, so it is the safe default.
  static const String androidStore =
      'https://play.google.com/store/apps/details?id=com.leader.teams';

  /// The Play Store app's own scheme. A launcher should try this first and
  /// fall back to [androidStore]; kept here so the fallback pair lives in
  /// one place.
  static const String androidStoreNative =
      'market://details?id=com.leader.teams';

  /// PLACEHOLDER. MTM has no published iOS listing yet — there is no iOS
  /// build target in the repo. Replace with the real
  /// `https://apps.apple.com/app/id<numeric-id>` when one exists; until
  /// then a launcher on iOS resolves [webFallback].
  static const String iosStore = '';

  /// PLACEHOLDER. Where a platform with no store (desktop, web) or an
  /// unconfigured one is sent. Point at the real download/landing page when
  /// there is one.
  static const String webFallback = 'https://mtm.app/download';

  /// The destination for [platform], or [webFallback] when that platform
  /// has none configured. Never returns an empty string.
  static String forPlatform(TargetPlatform platform) {
    switch (platform) {
      case TargetPlatform.android:
        return androidStore;
      case TargetPlatform.iOS:
        return iosStore.isEmpty ? webFallback : iosStore;
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return webFallback;
    }
  }
}
