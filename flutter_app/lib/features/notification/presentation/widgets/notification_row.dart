import 'package:flutter/material.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/forward_chevron.dart';
import '../../../../l10n/strings.dart';
import '../../domain/notification_models.dart';
import '../notification_copy.dart';

/// One row of the Notifications Center.
///
/// Compact on purpose: this is a list to scan, not a feed to read. Two lines
/// and a timestamp, sized so a screenful holds many rows rather than four
/// oversized cards.
///
/// **Unread reads three ways at once** — a filled dot on the leading edge, a
/// semibold title in full ink, and the type icon in its own severity tint —
/// so the distinction survives every palette, eye-protect, dark mode, and a
/// user who cannot separate the two colours. A read row keeps the same
/// geometry and drops to muted ink and a neutral icon, so nothing shifts when
/// the row changes state.
class NotificationRow extends StatelessWidget {
  const NotificationRow({
    super.key,
    required this.notification,
    required this.now,
    required this.onTap,
    this.opensDestination = true,
  });

  final AppNotification notification;
  final DateTime now;

  final VoidCallback? onTap;

  /// False for an informational row — one whose record the app has nowhere to
  /// open. The row still acknowledges a tap by marking itself read, but it
  /// draws no chevron: a row that leads nowhere must not look like one that
  /// does.
  final bool opensDestination;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final unread = !notification.isRead;
    final (tint, ink) = switch (notification.severity) {
      NotificationSeverity.critical => (c.critTint, c.crit),
      NotificationSeverity.warning => (c.warnTint, c.warn),
      NotificationSeverity.info => (c.infoTint, c.info),
    };

    return Semantics(
      button: onTap != null,
      selected: unread,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The unread dot sits in a fixed-width column so a read and an
                // unread row align to the same left edge.
                SizedBox(
                  width: 14,
                  child: unread
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Semantics(
                            label: S.notificationsUnreadDot,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: c.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        )
                      : null,
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: unread ? tint : c.surface2,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Icon(
                    notificationIcon(notification.kind),
                    size: 17,
                    color: unread ? ink : c.ink3,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              notificationTitle(notification.kind),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.35,
                                fontWeight:
                                    unread ? FontWeight.w600 : FontWeight.w400,
                                color: unread ? c.ink : c.ink2,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              notificationTimeLabel(
                                notification.occurredAt,
                                now,
                              ),
                              // The clock reads left-to-right inside an
                              // otherwise right-to-left row.
                              textDirection: TextDirection.ltr,
                              style: TextStyle(fontSize: 11, color: c.ink3),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        notificationSubtitle(notification),
                        // Two lines: a long Arabic item name plus its detail
                        // wraps rather than being cut mid-word, and a third
                        // line would make the list stop scanning.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: c.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null && opensDestination) ...[
                  const SizedBox(width: AppSpacing.sm),
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: ForwardChevron(size: 18),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
