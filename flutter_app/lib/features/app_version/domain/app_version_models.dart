import 'package:flutter/foundation.dart';

/// What the backend says about the installed build.
///
/// PROVISIONAL WIRE SHAPE — the field names below are the frontend's working
/// assumption, not an agreed contract. See `FRONTEND-BACKEND-INTEGRATION.md`
/// §1; the items marked `Backend contract decision required` there are the
/// ones that may still move. Only [supported] is structural: everything else
/// is display detail the screen degrades without.
@immutable
class AppVersionSupport {
  const AppVersionSupport({
    required this.supported,
    this.minimumVersion,
  });

  /// Whether the installed build may keep talking to the backend. The wire
  /// signal for `false` is `HTTP 426 Upgrade Required`; a body flag is a
  /// second, optional way to say the same thing.
  final bool supported;

  /// Lowest build the backend still serves, e.g. `1.4.0`. Shown to the user
  /// beside their own version. Null when the backend did not say — the
  /// screen then omits that row rather than inventing a number.
  final String? minimumVersion;

  /// The update **destination** is not modelled here on purpose: it is
  /// wholly client-owned ([UpdateChannel]). An `updateUrl` (or any other
  /// unrecognised member) in a `426` body is **ignored** by [fromJson], so a
  /// stale or hostile value on the wire can never redirect the user
  /// off-store. See `FRONTEND-BACKEND-INTEGRATION.md` §1.
  factory AppVersionSupport.fromJson(Map<String, dynamic> j) =>
      AppVersionSupport(
        supported: j['supported'] as bool,
        minimumVersion: j['minimumVersion'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'supported': supported,
        if (minimumVersion != null) 'minimumVersion': minimumVersion,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppVersionSupport &&
          other.supported == supported &&
          other.minimumVersion == minimumVersion;

  @override
  int get hashCode => Object.hash(supported, minimumVersion);
}

/// The four states the launch gate can be in.
///
/// Three of them block the app. Which is the whole point: a build the
/// backend refuses to serve must not reach a screen that reads data, and a
/// re-check that fails must not quietly drop the user back inside.
enum AppVersionStatus {
  /// The build is fine. The app runs its normal startup flow.
  supported,

  /// A re-check is in flight. Only ever entered from an already-blocked
  /// state — see [AppVersionState.blocksApp].
  checking,

  /// The backend refused this build (`426`). Blocking, non-dismissible.
  upgradeRequired,

  /// A re-check could not complete. The user stays on the blocking screen
  /// with a retry, because "we could not ask" is not "you may pass".
  checkFailed,
}

/// The gate's live value: a [AppVersionStatus] plus whatever the last
/// answer told us.
///
/// [support] survives [AppVersionStatus.checking] and
/// [AppVersionStatus.checkFailed] deliberately: the screen keeps showing the
/// version pair it already knows while a retry runs, instead of blanking out
/// and re-appearing.
@immutable
class AppVersionState {
  const AppVersionState._(this.status, {this.support, this.message});

  /// Nothing is blocking the app. Also the state a device opens on: an app
  /// that refuses to start because a version check has not answered yet is
  /// worse than one running a slightly old build.
  const AppVersionState.supported() : this._(AppVersionStatus.supported);

  const AppVersionState.checking({AppVersionSupport? support})
      : this._(AppVersionStatus.checking, support: support);

  const AppVersionState.upgradeRequired(AppVersionSupport support)
      : this._(AppVersionStatus.upgradeRequired, support: support);

  const AppVersionState.checkFailed({
    String? message,
    AppVersionSupport? support,
  }) : this._(AppVersionStatus.checkFailed, support: support, message: message);

  final AppVersionStatus status;

  /// The last answer from the backend, when there is one.
  final AppVersionSupport? support;

  /// Why the last check failed. Null unless [status] is
  /// [AppVersionStatus.checkFailed].
  final String? message;

  /// True when the app must not be reachable. The router reads exactly this
  /// — one predicate, so no screen can be added that forgets a state.
  bool get blocksApp => status != AppVersionStatus.supported;

  /// The lowest supported build, when the backend named one.
  String? get minimumVersion => support?.minimumVersion;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppVersionState &&
          other.status == status &&
          other.support == support &&
          other.message == message;

  @override
  int get hashCode => Object.hash(status, support, message);

  @override
  String toString() => 'AppVersionState(${status.name})';
}
