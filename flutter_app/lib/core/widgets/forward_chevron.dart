import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// The one glyph this app uses for "this row opens something".
///
/// **The rule, stated once.** Forward disclosure is
/// [Icons.chevron_right_rounded] — never `chevron_left`, and never a manual
/// `Transform.flip` or an `if (rtl)` at a call site.
///
/// Both rounded chevrons declare `matchTextDirection: true`, so Flutter
/// mirrors them under `Directionality.rtl` (`icon.dart`, `IconTheme`'s
/// direction handling). Starting from `chevron_right` therefore paints a
/// physically **left**-pointing chevron in Arabic and a right-pointing one in
/// a left-to-right locale — in both cases pointing the way the user is about
/// to travel. Starting from `chevron_left` paints the mirror of that, which
/// is the glyph for *back*: the defect this widget exists to retire, found on
/// thirteen surfaces in the 2026-09-19 UI audit (P1-1).
///
/// A screen reader is not told about it: the chevron repeats what the row's
/// own label and `button` semantics already say. Pass [semanticLabel] only
/// where the chevron is the row's *only* affordance.
///
/// This is disclosure, not navigation history. A **back** control (an app bar
/// leading action, «رجوع») is a different thing and keeps
/// `Icons.arrow_back_rounded`, which Flutter also mirrors; do not route it
/// through here.
class ForwardChevron extends StatelessWidget {
  const ForwardChevron({
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  /// Defaults to the ambient icon size, as a bare [Icon] would.
  final double? size;

  /// Defaults to `c.ink3` — a chevron is an affordance, not a signal. Pass a
  /// colour only where the row is deliberately tinted (a warning row).
  final Color? color;

  final String? semanticLabel;

  /// The glyph itself, for the rare caller that must hand an `IconData` to
  /// something else (a `ListTile.trailing` built by a generic row builder).
  /// Prefer the widget.
  static const IconData icon = Icons.chevron_right_rounded;

  @override
  Widget build(BuildContext context) => Icon(
        icon,
        size: size,
        color: color ?? context.c.ink3,
        semanticLabel: semanticLabel,
      );
}

/// The two week/period arrows, so "earlier" and "later" cannot be swapped.
///
/// Same mirroring rule as [ForwardChevron], applied to a timeline rather than
/// to a hierarchy: [earlier] is `chevron_left` (it paints to the *right* in
/// Arabic, where earlier days are) and [later] is `chevron_right`. The shifts
/// tab had these the other way round with a comment that misstated the
/// mirroring (UI audit P1-1).
abstract final class DirectionalArrows {
  /// Moves back in time — the previous week, the previous month.
  static const IconData earlier = Icons.chevron_left_rounded;

  /// Moves forward in time — the next week, the next month.
  static const IconData later = Icons.chevron_right_rounded;
}
