import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

/// What one unlock attempt concluded.
enum DeviceUnlockOutcome {
  /// The person proved it is them.
  unlocked,

  /// The prompt was dismissed — by the person or by the system. The lock
  /// stays and they may try again.
  cancelled,

  /// Too many failed attempts: the phone itself has to be unlocked first.
  lockedOut,

  /// The phone has no screen lock, fingerprint or face to check against, so
  /// there is nothing to prove and the app does not lock.
  unavailable,

  /// Anything else. The lock stays and they may try again.
  failed,
}

/// The phone's own screen-lock check — fingerprint, face, or the PIN,
/// pattern or password behind them.
abstract class DeviceAuthenticator {
  /// Whether this build locks a signed-in session at all.
  bool get enabled;

  Future<DeviceUnlockOutcome> unlock({required String reason});
}

/// Mock and test builds: never locks, so no test meets a system prompt.
class NoDeviceAuthenticator implements DeviceAuthenticator {
  const NoDeviceAuthenticator();

  @override
  bool get enabled => false;

  @override
  Future<DeviceUnlockOutcome> unlock({required String reason}) async =>
      DeviceUnlockOutcome.unlocked;
}

/// The real check, through `local_auth`. Biometrics first, with the phone's
/// own PIN, pattern or password as the fallback — exactly what unlocks the
/// phone itself. Installed by `backendOverrides`.
class LocalDeviceAuthenticator implements DeviceAuthenticator {
  LocalDeviceAuthenticator([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  bool get enabled => true;

  @override
  Future<DeviceUnlockOutcome> unlock({required String reason}) async {
    try {
      if (!await _auth.isDeviceSupported()) {
        return DeviceUnlockOutcome.unavailable;
      }
      final ok = await _auth.authenticate(
        localizedReason: reason,
        // A call or a notification mid-prompt retries on return instead of
        // failing.
        persistAcrossBackgrounding: true,
      );
      return ok ? DeviceUnlockOutcome.unlocked : DeviceUnlockOutcome.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.userRequestedFallback =>
          DeviceUnlockOutcome.cancelled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          DeviceUnlockOutcome.lockedOut,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware =>
          DeviceUnlockOutcome.unavailable,
        _ => DeviceUnlockOutcome.failed,
      };
    } catch (_) {
      return DeviceUnlockOutcome.failed;
    }
  }
}

/// [NoDeviceAuthenticator] unless the composition root installs the real one.
final deviceAuthenticatorProvider = Provider<DeviceAuthenticator>((ref) {
  return const NoDeviceAuthenticator();
});
