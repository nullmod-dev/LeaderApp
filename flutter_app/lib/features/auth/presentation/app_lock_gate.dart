import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/startup/startup_providers.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/strings.dart';
import '../../demo/data/demo_workspace.dart';
import '../data/app_lock_controller.dart';
import '../data/auth_providers.dart';
import '../data/device_authenticator.dart';
import '../data/sign_out_controller.dart';
import '_auth_scaffold.dart';
import 'onboarding_ui.dart';

/// Covers the product surface with [AppLockScreen] while the app lock holds.
///
/// Sits in `MaterialApp.builder`, above the router, so the navigation stack
/// underneath survives a lock and an unlock untouched. It only ever covers a
/// product surface: the sign-in form, onboarding and every status screen have
/// nothing of the account to hide. A Customer Demo is not an account and is
/// never locked.
class AppLockGate extends ConsumerWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockControllerProvider);
    final shown = lock.phase != AppLockPhase.open &&
        ref.watch(startupDestinationProvider).isProductSurface &&
        !ref.watch(isCustomerDemoSessionProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Always wrapped, so the router's subtree is never re-parented.
        ExcludeSemantics(
          excluding: shown,
          child: AbsorbPointer(absorbing: shown, child: child),
        ),
        if (shown) const AppLockScreen(),
      ],
    );
  }
}

class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  @override
  void initState() {
    super.initState();
    // The prompt opens by itself; the button is for a second try.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(appLockControllerProvider.notifier).unlock();
    });
  }

  static String? _message(DeviceUnlockOutcome? outcome) => switch (outcome) {
        DeviceUnlockOutcome.cancelled => S.appLockCancelled,
        DeviceUnlockOutcome.lockedOut => S.appLockLockedOut,
        DeviceUnlockOutcome.failed => S.appLockFailed,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final lock = ref.watch(appLockControllerProvider);
    final signingOut =
        ref.watch(signOutControllerProvider) == SignOutPhase.inProgress;
    final email = ref.watch(currentUserProvider).valueOrNull?.email;
    final message = _message(lock.lastOutcome);
    final busy = lock.phase == AppLockPhase.checking || signingOut;

    return AuthScaffold(
      title: S.appLockTitle,
      subtitle: S.appLockSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (email != null) ...[
            Text(
              '${S.signedInAs}\u2066$email\u2069',
              style: TextStyle(color: c.ink2, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (message != null) ...[
            OnboardingErrorBanner(message: message),
            const SizedBox(height: AppSpacing.lg),
          ],
          OnboardingPrimaryButton(
            label: S.appLockUnlock,
            busy: lock.phase == AppLockPhase.checking,
            onPressed: busy
                ? null
                : () => ref.read(appLockControllerProvider.notifier).unlock(),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: TextButton(
              onPressed: busy
                  ? null
                  : () => ref.read(signOutControllerProvider.notifier).signOut(),
              child: Text(
                S.appLockSignOut,
                style: TextStyle(color: c.ink3, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
