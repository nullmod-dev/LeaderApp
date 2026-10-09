import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../../l10n/strings.dart';

/// The one sentence every action that needs the server says when the phone
/// is offline. Shared so thirty call sites cannot drift into thirty wordings,
/// and so none of them falls back to a bare «بدون اتصال» that names the
/// state without saying what it stopped.
const SnackBar actionNeedsConnectionSnackBar =
    SnackBar(content: Text(S.actionNeedsConnection));

/// The offline bar at the top of a shell: the app is running on the stored
/// copy of the account, not on the server.
///
/// It owns the status-bar inset while it shows (the same contract as the
/// device-trust bar), and opens and closes by [AnimatedSize] only — it never
/// slides across the screen. [detail] is the second line, used for the last
/// 48 hours of the offline window.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.visible, this.detail});

  final bool visible;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final detail = this.detail;
    return AnimatedSize(
      alignment: Alignment.topCenter,
      duration: effectiveDuration(context, MotionTokens.short),
      curve: effectiveCurve(context, MotionTokens.enter),
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Material(
              color: c.warnTint,
              child: Semantics(
                key: const Key('offline-banner'),
                container: true,
                liveRegion: true,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
                        AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 18, color: c.warn),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                S.offlineCopyBanner,
                                style: TextStyle(
                                  color: c.ink2,
                                  fontSize: 12,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (detail != null)
                                Text(
                                  detail,
                                  key: const Key('offline-banner-detail'),
                                  style: TextStyle(
                                    color: c.ink2,
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
