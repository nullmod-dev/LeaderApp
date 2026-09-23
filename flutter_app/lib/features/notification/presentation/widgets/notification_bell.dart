import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/motion/animated_counter.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/strings.dart';
import '../../../home/data/home_providers.dart';
import '../../data/notification_providers.dart';
import '../notification_copy.dart';
import '../notifications_center_page.dart';

/// The app's single entry point into the Notifications Center: the bell in
/// the dashboard's app bar.
///
/// One entry point on purpose. The dashboard's alert rows still open the
/// surface that fixes each condition directly, which is a shorter path than
/// routing them through a list; the bell is for the conditions the user has
/// not looked at yet, and for the ones that are no longer today's.
///
/// The count comes from [unreadNotificationCountProvider], which counts the
/// very list the centre renders — so the badge cannot drift from the screen
/// after a read, a "mark all", a refresh, or a sync run that changes the
/// outbox.
class NotificationBellAction extends ConsumerWidget {
  const NotificationBellAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The feed is per detachment, like every other detachment-scoped read.
    // Until one resolves there is nothing to count, and the bell shows no
    // badge rather than a guess.
    final detachment = ref.watch(activeDetachmentProvider).valueOrNull?.when(
          success: (data, {stale = false}) => data,
          failure: (_, __) => null,
          offline: (cached) => cached,
        );
    final count = detachment == null
        ? 0
        : ref.watch(unreadNotificationCountProvider(detachment.id));

    return IconButton(
      key: const Key('notifications-bell'),
      tooltip: S.notificationsOpen,
      onPressed: () => context.push(NotificationsCenterPage.routePath),
      icon: _Bell(count: count),
    );
  }
}

class _Bell extends StatelessWidget {
  const _Bell({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      label: '${S.notificationsOpen}، ${unreadNotificationsLabel(count)}',
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_rounded),
          if (count > 0)
            PositionedDirectional(
              // Further off the glyph than a Material badge sits by default:
              // the bell is 24 dp and the badge is most of a third of it, so
              // a corner overlap leaves the icon readable while an inset one
              // turns it into a blob. The `Stack` does not clip, and the
              // 48 dp touch target absorbs the offset.
              top: -6,
              end: -9,
              // The badge is the one piece of text in the app drawn *on top
              // of* something rather than beside it. At 1.6× on a 320 dp
              // phone the unclamped badge grew to the width of the 24 dp
              // bell and covered it, so the control lost the glyph that says
              // what it is (found in the Phase 3C render review). Clamping
              // this subtree alone keeps the count legible — 10 sp still
              // scales, to 13 — without letting it swallow the icon; every
              // other string on the screen still scales in full.
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  constraints:
                      const BoxConstraints(minWidth: 16, minHeight: 16),
                  decoration: BoxDecoration(
                    color: c.crit,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    // Ringed in the bar's own ground so the badge reads as
                    // sitting on the bell rather than merging with the icon.
                    border: Border.all(color: c.surface, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      // Past nine the exact number stops being information
                      // and starts being a layout problem.
                      count > 9
                          ? '${toArabicIndic('9')}+'
                          : toArabicIndic(count.toString()),
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        color: c.surface,
                        fontSize: 10,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
