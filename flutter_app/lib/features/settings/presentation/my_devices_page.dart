import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/animated_counter.dart';
import '../../../core/problem/problem.dart';
import '../../../core/problem/problem_presentation.dart';
import '../../../core/result/result.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/confirmation_dialog.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/refresh_indicator.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../l10n/strings.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/data/device_trust_repository.dart';
import '../../auth/domain/device_trust.dart';
import '../../auth/presentation/device_trust_copy.dart';
import '../../shell/main_shell.dart';

/// My devices (`/more/security/devices`, and the platform's
/// `/platform/more/security/devices`) — the devices that sign in to this
/// account without an email code, and the one action on them: removing one.
///
/// A removed device's sessions end and it needs a code to come back. The
/// device in use is never removable (sign out instead), and a new device
/// still in its restricted window cannot remove anything — the server
/// refuses it, so the screen says so instead of offering the button.
class MyDevicesPage extends ConsumerWidget {
  const MyDevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final devices = ref.watch(accountDevicesProvider);
    final restricted =
        ref.watch(sessionAccessProvider).deviceRestriction != null;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text(S.myDevicesTitle)),
      body: AppRefreshIndicator(
        onRefresh: () => ref.refresh(accountDevicesProvider.future),
        child: FloatingNavPadding(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(S.myDevicesSub,
                  style: TextStyle(color: c.ink2, fontSize: 13, height: 1.5)),
              if (restricted) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  S.myDevicesRestrictedNote,
                  key: const Key('my-devices-restricted-note'),
                  style: TextStyle(color: c.warn, fontSize: 12, height: 1.5),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              ...devices.when(
                loading: () => const [
                  Skeleton(height: 72, radius: AppRadii.lg),
                  SizedBox(height: AppSpacing.sm),
                  Skeleton(height: 72, radius: AppRadii.lg),
                ],
                error: (_, __) => [_problem(ref, ProblemView.fallback)],
                data: (result) => switch (result) {
                  Success(:final data) =>
                    _list(context, ref, data, canRemove: !restricted),
                  Failure(:final message, :final code) => [
                      _problem(
                        ref,
                        resolveProblem(Problem.of(ProblemCode.parse(code),
                            rawCode: code, detail: message)),
                      ),
                    ],
                  Offline() => [
                      EmptyState(
                        key: const Key('my-devices-offline'),
                        icon: Icons.cloud_off_rounded,
                        title: S.offlineTitle,
                        body: S.noCachedCopy,
                        actionLabel: S.retry,
                        onAction: () => ref.invalidate(accountDevicesProvider),
                      ),
                    ],
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _problem(WidgetRef ref, ProblemView view) => EmptyState(
        key: const Key('my-devices-problem'),
        icon: Icons.error_outline_rounded,
        title: view.title,
        body: view.message,
        actionLabel: S.retry,
        onAction: () => ref.invalidate(accountDevicesProvider),
      );

  List<Widget> _list(
    BuildContext context,
    WidgetRef ref,
    AccountDevices data, {
    required bool canRemove,
  }) {
    if (data.devices.isEmpty) {
      return const [
        EmptyState(
          key: Key('my-devices-empty'),
          icon: Icons.devices_other_outlined,
          title: S.myDevicesEmpty,
          body: S.myDevicesSub,
        ),
      ];
    }
    final ordered = [
      ...data.devices.where((d) => d.current),
      ...data.devices.where((d) => !d.current),
    ];
    return [
      Text(
        S.myDevicesCount
            .replaceFirst('%s', toArabicIndic('${data.trustedCount}'))
            .replaceFirst('%s', toArabicIndic('${data.limit}')),
        key: const Key('my-devices-count'),
        style: TextStyle(color: context.c.ink3, fontSize: 12),
      ),
      const SizedBox(height: AppSpacing.sm),
      for (final device in ordered) ...[
        _DeviceCard(
          key: Key('my-device-${device.id}'),
          device: device,
          onRemove: device.current || !canRemove
              ? null
              : () => _confirmRemove(context, ref, device),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    ];
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    AccountDevice device,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showAppConfirmation(
      context: context,
      title: S.deviceRemoveTitle,
      identity: device.label,
      change: S.deviceRemoveBody,
      unchanged: S.deviceRemoveUnchanged,
      confirmLabel: S.deviceRemove,
      severity: ConfirmationSeverity.warning,
      keyPrefix: 'my-device-remove',
    );
    if (confirmed != true) return;
    final result =
        await ref.read(deviceTrustControllerProvider).remove(device.id);
    final message = switch (result) {
      Success() => S.deviceRemoved,
      Failure(:final message, :final code) => resolveProblem(Problem.of(
              ProblemCode.parse(code),
              rawCode: code,
              detail: message))
          .message,
      Offline() => S.onboardingOfflineNotice,
    };
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({super.key, required this.device, required this.onRemove});

  final AccountDevice device;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final chip = switch (device) {
      AccountDevice(restricted: true, status: AccountDeviceStatus.untrusted) =>
        const StatusChip(
            kind: StatusKind.muted, label: S.deviceStatusUntrusted),
      AccountDevice(restricted: true) => const StatusChip(
          kind: StatusKind.warn, label: S.deviceStatusRestricted),
      AccountDevice(status: AccountDeviceStatus.trusted) =>
        const StatusChip(kind: StatusKind.ok, label: S.deviceStatusTrusted),
      _ => const StatusChip(
          kind: StatusKind.muted, label: S.deviceStatusUntrusted),
    };
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: device.current ? c.primary : c.line),
      ),
      child: Row(
        children: [
          Icon(Icons.smartphone_rounded, color: c.ink2, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      device.label,
                      style:
                          TextStyle(color: c.ink, fontWeight: FontWeight.w600),
                    ),
                    chip,
                    if (device.current)
                      Text(S.deviceThisDevice,
                          style: TextStyle(color: c.primary, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${S.deviceLastSeen}${DeviceTrustCopy.moment(device.lastSeenAt)}',
                  style: TextStyle(color: c.ink3, fontSize: 12),
                ),
              ],
            ),
          ),
          if (onRemove != null)
            TextButton(
              key: Key('my-device-remove-${device.id}'),
              onPressed: onRemove,
              style: TextButton.styleFrom(
                foregroundColor: c.crit,
                minimumSize: const Size(48, 48),
              ),
              child: const Text(S.deviceRemove),
            ),
        ],
      ),
    );
  }
}
