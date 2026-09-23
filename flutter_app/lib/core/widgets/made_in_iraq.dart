import 'package:flutter/material.dart';

import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../../l10n/strings.dart';

/// «صنع بفخر في العراق» — the line the product closes with.
///
/// **One widget, three screens.** It ends the About page, it ends the
/// Settings hub, and it closes the Login screen. Writing the same
/// `Center(Text(...))` three times would be how they slowly stop matching —
/// one gains a divider, one keeps a different grey — so there is one of it.
///
/// **Deliberately not a row, not a card and not a link.** It sits at the
/// bottom of the scrollable content with space above it, in the quietest ink
/// the palette has that is still readable. It is not tappable: there is
/// nowhere for it to go, and a tap target that does nothing is worse than
/// none. It is also not pinned — a sticky footer would spend permanent screen
/// height on a sentence read once.
///
/// **No flag.** Text alone, because an emoji flag renders differently on every
/// platform and a bitmap one would be an asset decision nobody has made.
///
/// Theme-wise it asks the palette for `ink3` and nothing else, so it follows
/// light, dark and the eye-protect wash without a second definition. Login
/// is the one screen that does not paint from the palette — it has its own
/// green/glass ground — so it passes [color] and the quieter [padding] its
/// rhythm needs. Everything else about the line stays identical, which is
/// the point of it being one widget.
class MadeInIraqFooter extends StatelessWidget {
  const MadeInIraqFooter({super.key, this.color, this.padding});

  /// Overrides the palette's `ink3`. Only for a surface the palette does
  /// not own.
  final Color? color;

  /// Overrides the default generous-above/small-below gap.
  final EdgeInsetsGeometry? padding;

  /// The key both screens' tests look for.
  static const widgetKey = Key('made-in-iraq');

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      // Generous above, small below: the gap is what separates it from the
      // content, and `PlatformPage`/`ListView` already pad the bottom.
      padding: padding ??
          const EdgeInsets.only(
            top: AppSpacing.xxl,
            bottom: AppSpacing.md,
          ),
      child: Center(
        child: Text(
          S.madeInIraq,
          key: widgetKey,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: color ?? c.ink3,
            fontSize: 12,
            height: 1.6,
            // A hair of tracking: the line is set small and centred, and
            // Arabic at 12sp reads tight without it.
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
