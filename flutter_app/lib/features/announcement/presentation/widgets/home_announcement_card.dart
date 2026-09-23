import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/motion/press_scale.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/time/clock.dart';
import '../../../../l10n/strings.dart';
import '../../data/announcement_providers.dart';
import '../../domain/announcement_models.dart';
import '../../domain/announcement_selectors.dart';
import '../announcement_copy.dart';
import '../announcement_sheet.dart';
import '../announcements_page.dart';

/// The dashboard's announcement promotion — the top of Home for exactly one
/// hour after publication, and nothing at all before or after.
///
/// ## What "one hour" means, precisely
///
/// The truth is [isPromotedOnHome], a pure function of the record and an
/// injected clock: `now - publishedAt < 1h`. So `+59m59s` shows and `+1h00m00s`
/// does not, and reopening the app tomorrow evaluates correctly with no timer
/// having ever run. The [Timer] below is a *nudge*, not the source of truth —
/// it exists only so a dashboard left open across the boundary redraws itself
/// rather than sitting on a promotion that has expired. Kill the timer and the
/// behaviour is still right on the next build.
///
/// ## What happens at the boundary
///
/// The widget returns [SizedBox.shrink]. It is the first child of the
/// dashboard's list, so when it renders nothing the list is byte-for-byte the
/// list it was before announcements existed: the context header moves back to
/// the top, no placeholder is left behind, and no permanent layout was changed
/// to make room. The announcement itself is untouched — it is still in the
/// Notifications Center, and still on the detachment surface if it was placed
/// there.
///
/// ## More than one at a time
///
/// One card, never a stack. The newest active promotion is shown (ties broken
/// on id, so the choice is deterministic and the card cannot flicker between
/// two), and the rest are a single quiet line that opens the announcements
/// screen. A dashboard whose operational content starts below the fold is a
/// dashboard that has stopped being one.
class HomeAnnouncementCard extends ConsumerStatefulWidget {
  const HomeAnnouncementCard({super.key, required this.detachmentId});

  final String detachmentId;

  @override
  ConsumerState<HomeAnnouncementCard> createState() => _S();
}

class _S extends ConsumerState<HomeAnnouncementCard> {
  Timer? _expiry;

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  /// Schedules one rebuild for the instant the top promotion ends.
  ///
  /// Rescheduled on every build because the top announcement can change under
  /// it — a newer one is published, this one is withdrawn. A timer already set
  /// for the same moment is cheap to replace and impossible to leak.
  void _scheduleBoundary(Announcement? top, DateTime now) {
    _expiry?.cancel();
    if (top == null) return;
    final remaining = homePromotionEndsAt(top).difference(now);
    if (remaining.isNegative) return;
    _expiry = Timer(remaining, () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = ref.watch(clockProvider)();
    final promoted = ref.watch(homeAnnouncementsProvider(widget.detachmentId));
    final top = promoted.isEmpty ? null : promoted.first;
    _scheduleBoundary(top, now);

    // Nothing promoted: the dashboard is exactly what it was.
    if (top == null) return const SizedBox.shrink();

    final others = promoted.length - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: PressScale(
        onTap: () => showAnnouncementSheet(context: context, announcement: top),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          key: const Key('home-announcement'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            // The informational tint, not a warning: an announcement is
            // something to read, and a dashboard that shouts at the top every
            // time somebody posts a notice teaches people to stop looking.
            color: c.infoTint,
            border: Border.all(color: c.info.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.campaign_outlined, size: 18, color: c.info),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    S.announcementLabel,
                    style: TextStyle(
                      color: c.info,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Text(
                top.text,
                // Three lines, then the sheet. Long enough for a real notice,
                // short enough that today's shift card stays above the fold.
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.ink, fontSize: 14, height: 1.5),
              ),
              if (others > 0) ...[
                const SizedBox(height: AppSpacing.sm),
                GestureDetector(
                  key: const Key('home-announcement-more'),
                  onTap: () => context.push(AnnouncementsPage.routePath),
                  child: Text(
                    announcementHomeMoreLabel(others),
                    style: TextStyle(
                      color: c.info,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
