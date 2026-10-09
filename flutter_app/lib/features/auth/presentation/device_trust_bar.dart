import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/motion_tokens.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/clock.dart';
import '../../../l10n/strings.dart';
import '../data/auth_providers.dart';
import '../domain/session_access.dart';
import 'device_trust_copy.dart';

/// Device trust, above every page of a shell (tenant and platform):
///
///  - on a **new or untrusted device** (`access.deviceRestriction`) — a quiet
///    warning that older data and the account are locked here for now, with
///    the time it lifts. What exactly is refused, the server says on each
///    action (`session_restricted`), so the bar never lists rules;
///  - on a **trusted device** with new devices waiting
///    (`access.pendingDeviceApprovals`) — the "is it you?" notice and the way
///    to answer it.
///
/// Nothing at all otherwise. The bar re-reads the session when a window
/// ends, so it leaves on its own.
class DeviceTrustBar extends ConsumerStatefulWidget {
  const DeviceTrustBar({super.key});

  @override
  ConsumerState<DeviceTrustBar> createState() => _DeviceTrustBarState();
}

class _DeviceTrustBarState extends ConsumerState<DeviceTrustBar> {
  Timer? _timer;
  DateTime? _scheduledFor;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule(DateTime? until) {
    if (until == _scheduledFor) return;
    _timer?.cancel();
    _timer = null;
    _scheduledFor = until;
    if (until == null) return;
    var delay = until.difference(ref.read(clockProvider)().toUtc());
    if (delay.isNegative) delay = Duration.zero;
    _timer = Timer(delay + const Duration(seconds: 1), () {
      if (mounted) ref.invalidate(currentUserResultProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(sessionAccessProvider);
    final restriction = access.deviceRestriction;
    _schedule(restriction?.until);

    final Widget child;
    if (restriction != null) {
      child = _RestrictedBar(
          key: const ValueKey('device-restricted'), restriction: restriction);
    } else if (access.pendingDeviceApprovals.isNotEmpty) {
      child = const _PendingBar(key: ValueKey('device-pending'));
    } else {
      child = const SizedBox.shrink(key: ValueKey('device-trust-hidden'));
    }
    return AnimatedSwitcher(
      duration: effectiveDuration(context, MotionTokens.short),
      reverseDuration: effectiveDuration(context, MotionTokens.micro),
      switchInCurve: effectiveCurve(context, MotionTokens.enter),
      switchOutCurve: effectiveCurve(context, MotionTokens.exit),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _RestrictedBar extends StatelessWidget {
  const _RestrictedBar({super.key, required this.restriction});

  final DeviceRestriction restriction;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final until = restriction.until;
    final message = until != null
        ? '${S.deviceRestrictedBanner}${DeviceTrustCopy.moment(until)}'
        : S.deviceLimitBanner;
    return Material(
      color: c.warnTint,
      child: Semantics(
        key: const Key('device-restricted-bar'),
        container: true,
        liveRegion: true,
        label: message,
        excludeSemantics: true,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.phonelink_lock_outlined, size: 18, color: c.warn),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: c.ink2, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingBar extends StatelessWidget {
  const _PendingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 16 ||
        MediaQuery.sizeOf(context).width < 360;
    final notice = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.devices_other_outlined, size: 18, color: c.info),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            S.pendingDeviceBanner,
            style: TextStyle(color: c.ink2, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
    final review = TextButton(
      key: const Key('device-pending-review'),
      onPressed: () => context.push('/new-device'),
      style: TextButton.styleFrom(
        foregroundColor: c.info,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      child: const Text(S.pendingDeviceReview),
    );
    return Material(
      color: c.infoTint,
      child: Semantics(
        key: const Key('device-pending-bar'),
        container: true,
        liveRegion: true,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg, AppSpacing.xs, AppSpacing.sm, AppSpacing.xs),
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      notice,
                      Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: review),
                    ],
                  )
                : Row(children: [Expanded(child: notice), review]),
          ),
        ),
      ),
    );
  }
}

/// The other half of [DeviceTrustBar]: while the bar shows it owns the status
/// bar inset, so the page under it must not reserve it a second time.
class DeviceTrustBodyInset extends ConsumerWidget {
  const DeviceTrustBodyInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(sessionAccessProvider);
    final shows = access.deviceRestriction != null ||
        access.pendingDeviceApprovals.isNotEmpty;
    if (!shows) return child;
    return MediaQuery.removePadding(
        context: context, removeTop: true, child: child);
  }
}
