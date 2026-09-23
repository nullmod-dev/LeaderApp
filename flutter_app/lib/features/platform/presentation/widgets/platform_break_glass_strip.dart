import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/time/clock.dart';
import '../../../../l10n/strings.dart';
import '../../data/platform_break_glass_providers.dart';
import '../../domain/platform_break_glass_models.dart';
import '../platform_break_glass_actions.dart';
import '../platform_break_glass_copy.dart';
import '../platform_operations_routes.dart';

bool _shows(BreakGlassAccessDecision decision) =>
    decision.isPossiblyLive && decision.grant != null;

/// Hands the top system inset to the strip while it is shown.
///
/// The strip sits above the branch body, so it is the one that must clear the
/// status bar; the page's own app bar beneath it would otherwise pad for the
/// status bar a second time. The `MediaQuery` is always present so the branch
/// body keeps its place in the tree whether the strip is shown or not.
class PlatformBreakGlassBodyInset extends ConsumerStatefulWidget {
  const PlatformBreakGlassBodyInset({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PlatformBreakGlassBodyInset> createState() =>
      _PlatformBreakGlassBodyInsetState();
}

class _PlatformBreakGlassBodyInsetState
    extends ConsumerState<PlatformBreakGlassBodyInset> {
  Timer? _releaseInset;
  ProviderSubscription<bool>? _visibility;
  late bool _stripOwnsTopInset;

  @override
  void initState() {
    super.initState();
    _stripOwnsTopInset = ref.read(breakGlassAccessProvider.select(_shows));
    _visibility = ref.listenManual(
      breakGlassAccessProvider.select(_shows),
      (_, shown) {
        _releaseInset?.cancel();
        _releaseInset = null;
        if (shown) {
          if (mounted && !_stripOwnsTopInset) {
            setState(() => _stripOwnsTopInset = true);
          }
          return;
        }

        final duration = effectiveDuration(context, MotionTokens.micro);
        if (duration == Duration.zero) {
          if (mounted && _stripOwnsTopInset) {
            setState(() => _stripOwnsTopInset = false);
          }
          return;
        }
        _releaseInset = Timer(duration, () {
          if (mounted && _stripOwnsTopInset) {
            setState(() => _stripOwnsTopInset = false);
          }
        });
      },
    );
  }

  @override
  void dispose() {
    _releaseInset?.cancel();
    _visibility?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removePadding(
      context: context,
      removeTop: _stripOwnsTopInset,
      child: widget.child,
    );
  }
}

/// The one persistent emergency-context owner in the Platform shell.
///
/// It also schedules the two one-shot reevaluations required by the domain:
/// the near-expiry threshold and `expiresAt`. There is no polling and no
/// second-level countdown.
class PlatformBreakGlassStrip extends ConsumerStatefulWidget {
  const PlatformBreakGlassStrip({super.key});

  @override
  ConsumerState<PlatformBreakGlassStrip> createState() =>
      _PlatformBreakGlassStripState();
}

class _PlatformBreakGlassStripState
    extends ConsumerState<PlatformBreakGlassStrip> {
  Timer? _timer;
  String? _scheduled;
  String? _announcedExpiry;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule(BreakGlassAccessDecision decision) {
    final grant = decision.grant;
    if (!decision.isPossiblyLive || grant == null) {
      _timer?.cancel();
      _timer = null;
      _scheduled = null;
      return;
    }
    final now = ref.read(clockProvider)().toUtc();
    final nearAt = grant.expiresAt.subtract(kBreakGlassNearExpiryWindow);
    final target = !decision.isNearExpiry && nearAt.isAfter(now)
        ? nearAt
        : grant.expiresAt;
    final key = '${grant.id}|${grant.revision}|${target.toIso8601String()}';
    if (_scheduled == key) return;
    _timer?.cancel();
    _scheduled = key;
    var delay = target.difference(now);
    if (delay.isNegative) delay = Duration.zero;
    _timer = Timer(delay, () {
      if (!mounted) return;
      _scheduled = null;
      final atExpiry = !ref.read(clockProvider)().toUtc().isBefore(
            grant.expiresAt,
          );
      ref.invalidate(breakGlassAccessProvider);
      if (atExpiry) {
        ref.invalidate(breakGlassCurrentProvider);
        if (_announcedExpiry != grant.id) {
          _announcedExpiry = grant.id;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
              S.breakGlassExpiredForTeam.replaceFirst(
                '%s',
                grant.tenant.displayName,
              ),
            ),
          ));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final decision = ref.watch(breakGlassAccessProvider);
    _schedule(decision);
    final duration = effectiveDuration(context, MotionTokens.short);
    final reverseDuration = effectiveDuration(context, MotionTokens.micro);
    final child = !_shows(decision)
        ? const SizedBox.shrink(key: ValueKey('break-glass-strip-hidden'))
        : _strip(context, decision);

    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reverseDuration,
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

  Widget _strip(
    BuildContext context,
    BreakGlassAccessDecision decision,
  ) {
    final grant = decision.grant!;
    final unverified = decision.state != BreakGlassAccessState.usable;
    final state = unverified
        ? S.breakGlassStripUnverified
        : decision.isNearExpiry
            ? S.breakGlassStripNearExpiry
            : S.breakGlassReadOnlyScope;
    final semantic =
        '${S.breakGlassActiveTitle}، ${grant.tenant.displayName}، $state، ${S.breakGlassExpiresAt} ${BreakGlassCopy.timestamp(grant.expiresAt)}';
    final c = context.c;

    return Material(
      color: c.warnTint,
      child: Semantics(
        key: const Key('platform-break-glass-strip'),
        container: true,
        explicitChildNodes: true,
        liveRegion: true,
        label: semantic,
        // Top: the strip is the first thing under the status bar; see
        // [PlatformBreakGlassBodyInset] for the other half of that hand-off.
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scaledLabel = MediaQuery.textScalerOf(context).scale(16);
                final stacksAction =
                    constraints.maxWidth < 360 && scaledLabel > 20;
                final open = Semantics(
                  button: true,
                  label:
                      '${S.breakGlassOpenManagement}، ${grant.tenant.displayName}',
                  excludeSemantics: true,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: InkWell(
                      key: const Key('platform-break-glass-strip-open'),
                      onTap: () => context.go(PlatformOperationsRoutes.access),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${S.breakGlassActiveTitle} · ${grant.tenant.displayName}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: c.ink),
                            ),
                            Text(
                              '$state · ${S.breakGlassExpiresAt} '
                              '${BreakGlassCopy.timestamp(grant.expiresAt)}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: c.ink2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
                final end = TextButton(
                  key: const Key('platform-break-glass-strip-end'),
                  style: TextButton.styleFrom(
                    foregroundColor: c.ink,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: decision.isUsable
                      ? () => confirmAndEndBreakGlass(context, ref, grant)
                      : null,
                  child: const Text(S.breakGlassEndAction),
                );

                if (stacksAction) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: c.warn),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: open),
                        ],
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: end,
                      ),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: c.warn),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: open),
                    const SizedBox(width: AppSpacing.sm),
                    end,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
