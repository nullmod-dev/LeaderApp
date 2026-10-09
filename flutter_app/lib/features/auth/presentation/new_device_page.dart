import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../../../core/widgets/status_screen.dart';
import '../../../l10n/strings.dart';
import '../data/auth_providers.dart';
import '../data/device_trust_repository.dart';
import '../domain/auth_models.dart';
import '../domain/device_trust.dart';
import '../domain/session_access.dart';
import '_auth_scaffold.dart';
import 'device_trust_copy.dart';
import 'onboarding_ui.dart';

/// `/new-device` — a trusted device answers "a new device signed in: is it
/// you?" (`access.pendingDeviceApprovals`, reached from `DeviceTrustBar`).
///
/// **Yes** lifts the new device's restriction at once. **No** blocks it and
/// ends every session of the account — this phone's too — so it asks first,
/// and then leaves for `/account-secured`. Nothing to answer (the window
/// ended, or another trusted device answered) is its own quiet state.
class NewDevicePage extends ConsumerStatefulWidget {
  const NewDevicePage({super.key});

  @override
  ConsumerState<NewDevicePage> createState() => _NewDevicePageState();
}

class _NewDevicePageState extends ConsumerState<NewDevicePage> {
  bool _approving = false;
  bool _denying = false;
  String? _error;
  bool _limitReached = false;

  bool get _busy => _approving || _denying;

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  String get _devicesRoute => ref.read(authRoleProvider) == AuthRole.superAdmin
      ? '/platform/more/security/devices'
      : '/more/security/devices';

  Future<void> _approve(PendingDeviceApproval device) async {
    setState(() {
      _approving = true;
      _error = null;
      _limitReached = false;
    });
    final messenger = ScaffoldMessenger.of(context);
    final result =
        await ref.read(deviceTrustControllerProvider).approve(device.id);
    if (!mounted) return;
    setState(() => _approving = false);
    switch (result) {
      case Success():
        messenger
            .showSnackBar(const SnackBar(content: Text(S.newDeviceApproved)));
        _leave();
      case Failure(:final code) when code == trustedDeviceLimitCode:
        setState(() {
          _limitReached = true;
          _error = S.newDeviceLimitReached;
        });
      case Failure(:final message):
        setState(
            () => _error = message.isEmpty ? S.problemUnexpectedBody : message);
      case Offline():
        setState(() => _error = S.onboardingOfflineNotice);
    }
  }

  Future<void> _deny(PendingDeviceApproval device) async {
    final confirmed = await showAppConfirmation(
      context: context,
      title: S.newDeviceDenyTitle,
      identity: device.label,
      change: S.newDeviceDenyBody,
      unchanged: S.newDeviceDenyUnchanged,
      confirmLabel: S.newDeviceDenyAction,
      severity: ConfirmationSeverity.destructive,
      keyPrefix: 'new-device-deny',
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _denying = true;
      _error = null;
      _limitReached = false;
    });
    final result =
        await ref.read(deviceTrustControllerProvider).deny(device.id);
    if (!mounted) return;
    switch (result) {
      case Success(:final data):
        context.go('/account-secured?reset=${data.passwordReset ? 1 : 0}');
      case Failure(:final message):
        setState(() {
          _denying = false;
          _error = message.isEmpty ? S.problemUnexpectedBody : message;
        });
      case Offline():
        setState(() {
          _denying = false;
          _error = S.onboardingOfflineNotice;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(sessionAccessProvider).pendingDeviceApprovals;
    if (pending.isEmpty && !_busy) {
      return StatusScreen(
        icon: Icons.devices_outlined,
        title: S.newDeviceNoneTitle,
        body: S.newDeviceNoneBody,
        primaryAction: FilledButton(
          key: const Key('new-device-none-back'),
          onPressed: _leave,
          child: const Text(S.back),
        ),
      );
    }
    if (pending.isEmpty) {
      // A No has just ended the session; the app is moving on.
      return const AuthScaffold(
        title: S.newDeviceApprovalTitle,
        subtitle: '',
        child: SizedBox.shrink(),
      );
    }
    final device = pending.first;
    final c = context.c;
    return AuthScaffold(
      title: S.newDeviceApprovalTitle,
      subtitle: S.newDeviceApprovalSub,
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            key: const Key('new-device-card'),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: c.line),
            ),
            child: Row(children: [
              Icon(Icons.smartphone_rounded, color: c.ink2, size: 22),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.label,
                      style:
                          TextStyle(color: c.ink, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${S.newDeviceSignedInAt}'
                      '${DeviceTrustCopy.moment(device.signedInAt)}',
                      style: TextStyle(color: c.ink3, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ]),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            OnboardingErrorBanner(message: _error!),
          ],
          if (_limitReached)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('new-device-open-devices'),
                onPressed: () => context.push(_devicesRoute),
                child: const Text(S.myDevicesTitle),
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          FilledButton(
            key: const Key('new-device-yes'),
            onPressed: _busy ? null : () => _approve(device),
            child: _approving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(S.newDeviceYes),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            key: const Key('new-device-no'),
            onPressed: _busy ? null : () => _deny(device),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.crit,
              side: BorderSide(color: c.crit),
            ),
            child: _denying
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(S.newDeviceNo),
          ),
        ],
      ),
    );
  }
}
