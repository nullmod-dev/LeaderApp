import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/startup/startup_destination.dart';
import '../../../core/startup/startup_providers.dart';
import '../../../core/time/clock.dart';
import '../../../l10n/strings.dart';
import 'device_authenticator.dart';

enum AppLockPhase {
  /// Nothing to prove: the app is usable.
  open,

  /// A signed-in session waits for the phone's screen lock.
  locked,

  /// The system prompt is up.
  checking,
}

@immutable
class AppLockStatus {
  const AppLockStatus(this.phase, {this.lastOutcome});

  const AppLockStatus.open() : this(AppLockPhase.open);

  const AppLockStatus.locked() : this(AppLockPhase.locked);

  final AppLockPhase phase;

  /// Why the last attempt left the app locked, for the lock screen's message.
  final DeviceUnlockOutcome? lastOutcome;
}

/// The app lock: an account still signed in on this phone opens with the
/// phone's own fingerprint/face/PIN — never with a password or a code.
///
/// **A UX gate on this device, not authentication.** The session itself is
/// the server's: it ends 7 days after the sign-in that opened it, and then the
/// person signs in again in full. The lock only stops someone holding an
/// unlocked phone from walking into an account that is still signed in.
///
/// When it locks:
///  - every cold launch — armed here, before the session read lands;
///  - a return to the app after [relockAfter] or more in the background.
///
/// It never locks a fresh sign-in: every destination that means "no full
/// session on this phone" (the sign-in form, an expired session, the code
/// screen, onboarding) disarms it, so the session that follows was just
/// proved with a password, Google or a code. A phone with no screen lock at
/// all has nothing to check against and opens.
class AppLockController extends Notifier<AppLockStatus> {
  static const relockAfter = Duration(minutes: 5);

  DateTime? _backgroundedAt;

  @override
  AppLockStatus build() {
    if (!ref.watch(deviceAuthenticatorProvider).enabled) {
      return const AppLockStatus.open();
    }
    ref.listen<StartupDestination>(startupDestinationProvider, (_, next) {
      if (_endsSession(next)) state = const AppLockStatus.open();
    });
    return _endsSession(ref.read(startupDestinationProvider))
        ? const AppLockStatus.open()
        : const AppLockStatus.locked();
  }

  static bool _endsSession(StartupDestination destination) =>
      switch (destination) {
        StartupDestination.signedOut ||
        StartupDestination.sessionExpired ||
        StartupDestination.offlineSessionExpired ||
        // Nothing could be read, so there is no account to protect yet.
        StartupDestination.launchOffline ||
        StartupDestination.launchServerError ||
        StartupDestination.invalidSession ||
        StartupDestination.emailVerification ||
        StartupDestination.teamLink ||
        StartupDestination.firstTimeSetup =>
          true,
        _ => false,
      };

  /// The app went to the background.
  void onBackgrounded() {
    // The system prompt itself backgrounds the app; only an open app counts.
    if (state.phase != AppLockPhase.open) return;
    _backgroundedAt = ref.read(clockProvider)();
  }

  /// The app came back.
  void onResumed() {
    final at = _backgroundedAt;
    _backgroundedAt = null;
    if (at == null || state.phase != AppLockPhase.open) return;
    if (!ref.read(deviceAuthenticatorProvider).enabled) return;
    final away = ref.read(clockProvider)().difference(at);
    if (away >= relockAfter) state = const AppLockStatus.locked();
  }

  /// Shows the system prompt once. Single-flight: a second call while the
  /// prompt is up does nothing.
  Future<void> unlock() async {
    if (state.phase != AppLockPhase.locked) return;
    state = const AppLockStatus(AppLockPhase.checking);
    final outcome = await ref
        .read(deviceAuthenticatorProvider)
        .unlock(reason: S.appLockPromptReason);
    // The session ended while the prompt was up (signed out, expired): the
    // lock was already opened for whatever comes next — leave it.
    if (state.phase != AppLockPhase.checking) return;
    state = switch (outcome) {
      DeviceUnlockOutcome.unlocked ||
      DeviceUnlockOutcome.unavailable =>
        const AppLockStatus.open(),
      _ => AppLockStatus(AppLockPhase.locked, lastOutcome: outcome),
    };
  }
}

final appLockControllerProvider =
    NotifierProvider<AppLockController, AppLockStatus>(AppLockController.new);
