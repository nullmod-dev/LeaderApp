import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/startup/startup_destination.dart';
import 'package:mtm/core/startup/startup_providers.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/data/app_lock_controller.dart';
import 'package:mtm/features/auth/data/device_authenticator.dart';

/// The phone's prompt, scripted: answers [next] and counts the prompts.
class _FakeAuthenticator implements DeviceAuthenticator {
  DeviceUnlockOutcome next = DeviceUnlockOutcome.unlocked;
  int prompts = 0;

  @override
  bool get enabled => true;

  @override
  Future<DeviceUnlockOutcome> unlock({required String reason}) async {
    prompts++;
    return next;
  }
}

/// The app lock: armed on a cold launch, opened by the phone's own screen
/// lock, disarmed by every "no full session" destination, re-armed after five
/// minutes away — and absent from every build without a real authenticator.
void main() {
  late _FakeAuthenticator phone;
  late StateProvider<StartupDestination> destination;
  late DateTime now;

  ProviderContainer container({DeviceAuthenticator? authenticator}) {
    final c = ProviderContainer(overrides: [
      deviceAuthenticatorProvider.overrideWithValue(authenticator ?? phone),
      startupDestinationProvider
          .overrideWith((ref) => ref.watch(destination)),
      clockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    phone = _FakeAuthenticator();
    destination = StateProvider<StartupDestination>(
        (ref) => StartupDestination.tenantSurface);
    now = DateTime.utc(2026, 10, 7, 9);
  });

  AppLockPhase phaseOf(ProviderContainer c) =>
      c.read(appLockControllerProvider).phase;

  test('a build without a real authenticator never locks', () {
    final c = container(authenticator: const NoDeviceAuthenticator());
    expect(phaseOf(c), AppLockPhase.open);
  });

  test('a cold launch with a session is locked until the phone says yes',
      () async {
    final c = container();
    expect(phaseOf(c), AppLockPhase.locked);
    await c.read(appLockControllerProvider.notifier).unlock();
    expect(phaseOf(c), AppLockPhase.open);
    expect(phone.prompts, 1);
  });

  test('a dismissed or failed prompt stays locked and says why', () async {
    final c = container();
    for (final outcome in [
      DeviceUnlockOutcome.cancelled,
      DeviceUnlockOutcome.lockedOut,
      DeviceUnlockOutcome.failed,
    ]) {
      phone.next = outcome;
      await c.read(appLockControllerProvider.notifier).unlock();
      final status = c.read(appLockControllerProvider);
      expect(status.phase, AppLockPhase.locked);
      expect(status.lastOutcome, outcome);
    }
  });

  test('a phone with no screen lock has nothing to check and opens', () async {
    phone.next = DeviceUnlockOutcome.unavailable;
    final c = container();
    await c.read(appLockControllerProvider.notifier).unlock();
    expect(phaseOf(c), AppLockPhase.open);
  });

  test('every "no full session" destination disarms, so a fresh sign-in is '
      'never asked again', () {
    for (final ends in [
      StartupDestination.signedOut,
      StartupDestination.sessionExpired,
      StartupDestination.invalidSession,
      StartupDestination.emailVerification,
      StartupDestination.teamLink,
      StartupDestination.firstTimeSetup,
    ]) {
      final c = container();
      c.read(appLockControllerProvider);
      c.read(destination.notifier).state = ends;
      expect(phaseOf(c), AppLockPhase.open, reason: '$ends');
      // Signing in afterwards lands on the product, unlocked.
      c.read(destination.notifier).state = StartupDestination.tenantSurface;
      expect(phaseOf(c), AppLockPhase.open, reason: '$ends');
    }
  });

  test('a launch that is already signed out starts open', () {
    final c = container();
    c.read(destination.notifier).state = StartupDestination.signedOut;
    expect(phaseOf(c), AppLockPhase.open);
  });

  test('five minutes or more in the background re-locks; less does not',
      () async {
    final c = container();
    final lock = c.read(appLockControllerProvider.notifier);
    await lock.unlock();

    lock.onBackgrounded();
    now = now.add(const Duration(minutes: 4, seconds: 59));
    lock.onResumed();
    expect(phaseOf(c), AppLockPhase.open);

    lock.onBackgrounded();
    now = now.add(AppLockController.relockAfter);
    lock.onResumed();
    expect(phaseOf(c), AppLockPhase.locked);
  });

  test('a session that ends while the prompt is up stays open afterwards',
      () async {
    final c = container();
    final lock = c.read(appLockControllerProvider.notifier);
    phone.next = DeviceUnlockOutcome.cancelled;
    final pending = lock.unlock();
    c.read(destination.notifier).state = StartupDestination.signedOut;
    await pending;
    expect(phaseOf(c), AppLockPhase.open);
  });
}
