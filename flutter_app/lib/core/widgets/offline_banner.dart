import 'package:flutter/material.dart';

import '../motion/animated_counter.dart';
import '../motion/motion_tokens.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../../l10n/strings.dart';

/// Slim banner pinned under the app bar; only visible when [visible] is true.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    required this.visible,
    required this.lastRefreshedAgoMinutes,
  });

  final bool visible;
  final int lastRefreshedAgoMinutes;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnimatedSize(
      alignment: Alignment.topCenter,
      duration: effectiveDuration(context, MotionTokens.short),
      curve: effectiveCurve(context, MotionTokens.enter),
      child: !visible
          ? const SizedBox.shrink()
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              color: c.warnTint,
              child: Row(children: [
                Icon(Icons.cloud_off_rounded, size: 16, color: c.warn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: '${S.offlineTitle} · ',
                        style: TextStyle(
                            color: c.warn, fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: S.offlineSub,
                        style: TextStyle(color: c.ink2),
                      ),
                      TextSpan(
                        text:
                            '${toArabicIndic(lastRefreshedAgoMinutes.toString())} د',
                        style: AppTypography.digits(c.ink),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
    );
  }
}

/// Subtle indicator for "cached content" mode.
class StaleBadge extends StatelessWidget {
  const StaleBadge({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.mutedTint,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        S.staleData,
        style: TextStyle(
          color: c.ink2,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
