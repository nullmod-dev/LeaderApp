import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/result/result.dart';
import '../domain/app_version_gate_store.dart';
import '../domain/app_version_models.dart';
import '../domain/app_version_repository.dart';
import '../domain/update_channel.dart';
import 'mock_app_version_gate_store.dart';
import 'mock_app_version_repository.dart';

/// Swap this override in a real build to plug in a network-backed repo —
/// the same seam every other feature uses.
final appVersionRepositoryProvider = Provider<AppVersionRepository>((ref) {
  return MockAppVersionRepository();
});

/// Persists "this build was already refused", so an offline relaunch cannot
/// walk past a `426` it already saw. Override with a real local-preferences
/// implementation in a shipping build.
final appVersionGateStoreProvider = Provider<AppVersionGateStore>((ref) {
  return MockAppVersionGateStore();
});

/// The forced-upgrade gate.
///
/// A plain [Notifier], not an `AsyncNotifier`, because the router's
/// `redirect` has to read this **synchronously** on every navigation — and
/// because "we are still checking" is one of the four states the screen
/// draws, not an envelope around them.
///
/// The rules that keep this honest:
///
///   1. A check only blocks the app if it **finds** a reason to. It never
///      blocks merely by being in flight.
///   2. But a build this device already saw refused stays blocked across a
///      restart, network or none — the persisted verdict
///      ([AppVersionGateStore]) is consulted before the launch check, and
///      an offline launch that cannot re-confirm keeps the gate shut rather
///      than opening it on a timeout.
///
/// So a first, never-refused launch with no connectivity opens exactly as
/// it always did; a launch of a build that was refused last run does not.
class AppVersionController extends Notifier<AppVersionState> {
  /// True once this notifier is gone. The launch check is fire-and-forget,
  /// so its answer can arrive after the container that owns it was torn
  /// down — a widget test that pumps and ends is the ordinary way to hit
  /// this. Writing `state` then throws, so every write is guarded.
  bool _disposed = false;

  @override
  AppVersionState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    // Fire-and-forget: `build` must return the state to paint now, and the
    // answer arrives a microtask (mock) or a round trip (real) later.
    Future<void>.microtask(check);
    return const AppVersionState.supported();
  }

  /// Runs the support check.
  ///
  /// Called once at launch, and again every time the user taps
  /// **إعادة المحاولة** on the blocking screen. Also the entry point for a
  /// `426` received on any ordinary authenticated request — see
  /// `FRONTEND-BACKEND-INTEGRATION.md` §1.
  Future<void> check() async {
    if (_disposed) return;

    // 1. Persisted verdict first. Only when we are not already blocked (a
    //    retry from the screen skips straight to the network call): a build
    //    refused on a previous run re-enters the gate now, before a check
    //    that an offline device may never be able to answer.
    if (!state.blocksApp) {
      final restored = await _restorePersistedGate();
      if (_disposed) return;
      if (restored != null) state = restored;
    }

    final wasBlocking = state.blocksApp;
    // Only a user-visible re-check shows `checking`; the launch check must
    // not flash a blocking screen at an app that is fine.
    if (wasBlocking) {
      state = AppVersionState.checking(support: state.support);
    }
    final previous = state.support;

    final result = await ref.read(appVersionRepositoryProvider).checkSupport();
    if (_disposed) return;

    state = switch (result) {
      Success(:final data) => data.supported
          ? const AppVersionState.supported()
          : AppVersionState.upgradeRequired(data),
      // A check that could not complete keeps the user where they are: shut
      // out if they were shut out, inside if they were inside.
      Failure(:final message) => wasBlocking
          ? AppVersionState.checkFailed(message: message, support: previous)
          : const AppVersionState.supported(),
      Offline(:final cached) => wasBlocking
          ? AppVersionState.checkFailed(support: cached ?? previous)
          : const AppVersionState.supported(),
    };

    // 2. Persist the verdict, but only when the check actually reached one.
    //    A `Failure`/`Offline` re-check changes nothing on disk — the record
    //    it would overwrite is the last real answer.
    if (result case Success(:final data)) _persistVerdict(data);
  }

  /// Reads the stored gate and turns it into a blocking state when it is
  /// about *this* build. A record about another build is stale — dropped
  /// here so it can never resurface.
  Future<AppVersionState?> _restorePersistedGate() async {
    final store = ref.read(appVersionGateStoreProvider);
    final PersistedUpgradeGate? record;
    try {
      record = await store.read();
    } catch (_) {
      // A store that cannot be read is not a reason to block: fail open,
      // exactly as an unreachable network launch check does.
      return null;
    }
    if (record == null) return null;
    if (record.appliesTo(AppInfo.buildIdentity)) {
      return AppVersionState.upgradeRequired(
        AppVersionSupport(
          supported: false,
          minimumVersion: record.minimumVersion,
        ),
      );
    }
    // Belongs to a build (version + build number) that is no longer
    // installed — a fix shipped as a new build must not stay blocked on it.
    try {
      await store.clear();
    } catch (_) {/* best effort */}
    return null;
  }

  /// Fire-and-forget write of the latest real answer.
  void _persistVerdict(AppVersionSupport support) {
    final store = ref.read(appVersionGateStoreProvider);
    final future = support.supported
        ? store.clear()
        : store.write(
            PersistedUpgradeGate(
              blockedVersion: AppInfo.buildIdentity,
              minimumVersion: support.minimumVersion,
            ),
          );
    future.catchError((_) {/* a failed write must not crash the gate */});
  }

  /// Sends the user to the client-owned update destination.
  ///
  /// Returns what actually happened so the screen can say so; see
  /// [UpdateDestination] for why "opened" is not yet the answer in a build
  /// with no launcher. The destination is entirely [UpdateChannel]'s — the
  /// backend never names it, so nothing from the wire is passed here.
  Future<UpdateLaunchOutcome> openUpdateDestination() =>
      ref.read(updateDestinationProvider).open();
}

final appVersionProvider =
    NotifierProvider<AppVersionController, AppVersionState>(
  AppVersionController.new,
);

/// What [UpdateDestination.open] managed to do.
enum UpdateLaunchOutcome {
  /// The store page was opened. The production outcome once a launcher is
  /// wired — see [UpdateDestination].
  opened,

  /// The destination was put on the clipboard instead (the launcher-less
  /// development build).
  copied,

  /// There was no destination to go to at all.
  unavailable,
}

/// Takes the user to the update.
///
/// The destination is **wholly client-owned** ([UpdateChannel]): this build
/// knows where it is installed from, so `open` needs nothing from the
/// network and works from the persisted gate while offline. The backend
/// never sends an update URL — a `426` body that carried one would be
/// ignored (see `AppVersionSupport.fromJson`), so a hostile or stale value
/// on the wire can never redirect the user off-store.
///
/// MTM ships no URL-launcher plugin and this feature does not add one (a
/// platform channel and a plugin dependency are both outside a frontend-only
/// task). The launcher-less build therefore does the one honest thing it
/// can with the app's own primitives — it hands the user the resolved link
/// through the same copy idiom the report export and the MFA backup codes
/// already use.
///
/// TO INTEGRATE: replace the body of [open] with the launch call
/// (`url_launcher`, trying [UpdateChannel.androidStoreNative] then the
/// `https` form on Android) and return [UpdateLaunchOutcome.opened]. The
/// button, its label and every state on the screen stay exactly as they
/// are.
class UpdateDestination {
  const UpdateDestination();

  /// The destination this client resolves for the platform it is running
  /// on. Exposed so a launcher implementation and the tests share one
  /// source of truth.
  String resolvedDestination() =>
      UpdateChannel.forPlatform(defaultTargetPlatform);

  Future<UpdateLaunchOutcome> open() async {
    final url = resolvedDestination();
    if (url.isEmpty) return UpdateLaunchOutcome.unavailable;
    await Clipboard.setData(ClipboardData(text: url));
    return UpdateLaunchOutcome.copied;
  }
}

final updateDestinationProvider = Provider<UpdateDestination>((ref) {
  return const UpdateDestination();
});
