import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// How much weight a section heading carries.
///
/// Two levels, because the app genuinely has two — not because a widget with
/// a style enum looks more general.
enum SectionHeaderStyle {
  /// The small tracked eyebrow above a grouped card: `ink3 / 12 / w600 /
  /// 0.6`. The settings hub, the organisation screens, the notification
  /// groups and most platform sections are all this.
  label,

  /// A page-level section heading: `titleMedium`, with an optional
  /// brand-tinted icon before it. Used where a platform page opens a major
  /// block — health signals, security alerts, the overview's attention list.
  heading,
}

/// The one section heading in this app.
///
/// **Why one.** The 2026-09-19 UI audit found five spellings of this
/// component: `SectionHeader` and Settings' `SectionLabel` were
/// typographically identical and differed only in padding and a trailing
/// action, while three platform pages each carried a byte-identical private
/// `_SectionTitle` (icon + `titleMedium`). One heading, five implementations,
/// and no way to change the app's section rhythm in one place.
///
/// **What it deliberately does not do.** No subtitle: nothing in the app has
/// ever needed a second line under a section heading, and a slot nobody fills
/// is a slot the next screen fills wrongly. No count badge, no chevron, no
/// tappable header — a section heading is a label, and the things inside it
/// are the controls.
///
/// Announced as a heading, so a screen reader can jump between sections
/// rather than reading every row to find the next group.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.action,
    this.onAction,
    this.actionIcon,
    this.actionKey,
    this.style = SectionHeaderStyle.label,
    this.padding,
  });

  final String title;

  /// A brand-tinted glyph before the title. Only meaningful with
  /// [SectionHeaderStyle.heading]; an eyebrow carries no icon.
  final IconData? icon;

  /// A short text action at the end of the row — «امسح الكل», «عرض الكل».
  /// One word or two; anything longer belongs in the section, not above it.
  final String? action;
  final VoidCallback? onAction;

  /// A glyph before the action label. Only for an action that *creates*
  /// something — «إنشاء عرض» — where the `+` is the part scanned first. A
  /// destructive or navigational action carries no icon.
  final IconData? actionIcon;

  /// Keys the action button itself rather than the header, so a test taps the
  /// control instead of the row that contains it.
  final Key? actionKey;

  final SectionHeaderStyle style;

  /// Overrides the default rhythm. Passed only where a header sits inside
  /// something that already owns its spacing (a bottom sheet).
  final EdgeInsetsGeometry? padding;

  /// The rhythm above and below a section label, stated once so the whole
  /// app breathes the same way.
  static const EdgeInsetsGeometry labelPadding = EdgeInsetsDirectional.fromSTEB(
    AppSpacing.xs,
    AppSpacing.lg,
    AppSpacing.xs,
    AppSpacing.sm,
  );

  /// A page-level heading brings its own spacing from the page that lays it
  /// out, so the primitive adds none.
  static const EdgeInsetsGeometry headingPadding = EdgeInsets.zero;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final heading = style == SectionHeaderStyle.heading;
    return Padding(
      padding: padding ?? (heading ? headingPadding : labelPadding),
      child: Row(
        children: [
          if (icon != null && heading) ...[
            Icon(icon, size: 19, color: c.primary),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: heading
                    ? Theme.of(context).textTheme.titleMedium
                    // The eyebrow token: `ink3 / 12 / w600 / 0.6`, which is
                    // what all ~55 section labels already spelled by hand.
                    : AppTypography.eyebrow(c),
              ),
            ),
          ),
          if (action != null)
            // `Size(0, 32)`, never `Size.fromHeight` — that is
            // `Size(double.infinity, 32)`, and a header action that claims the
            // full width stops being an action beside a heading.
            actionIcon == null
                ? TextButton(
                    key: actionKey,
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text(action!),
                  )
                : TextButton.icon(
                    key: actionKey,
                    onPressed: onAction,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      minimumSize: const Size(0, 36),
                    ),
                    icon: Icon(actionIcon, size: 18),
                    label: Text(action!),
                  ),
        ],
      ),
    );
  }
}
