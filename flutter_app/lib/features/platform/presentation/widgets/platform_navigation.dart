import 'package:flutter/material.dart';

import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/strings.dart';
import '../platform_destinations.dart';

/// The platform surface's two navigation controls: a docked bar for compact
/// widths and a rail for expanded ones.
///
/// **Why not the tenant's `GlassBottomNav`.** That bar is the tenant app's
/// signature — a floating blurred pill that hides every label but the selected
/// one. Both properties are wrong here. A control plane wants its navigation
/// *grounded* (the operator should never wonder what is underneath it) and it
/// wants all four labels legible at once, because the areas are unfamiliar
/// nouns rather than the four rooms someone works in daily. This is a
/// different composition of the same design tokens — not a second theme, and
/// not a second navigation *model*: both controls below read the one
/// `platformDestinations` registry.
///
/// **Why not Material's `NavigationBar`/`NavigationRail`.** `NavigationBar`
/// pins its own height and clips its labels once the text scale passes about
/// 1.3, which `§35` explicitly forbids solving with a smaller font. These grow
/// instead: the row is laid out from its content, so a label that needs two
/// lines gets a taller bar rather than a truncated word.

/// The compact bar. Goes in `Scaffold.bottomNavigationBar`, so the body is
/// inset by it and nothing floats over content.
class PlatformNavigationBar extends StatelessWidget {
  const PlatformNavigationBar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      explicitChildNodes: true,
      label: S.platformNavLabel,
      child: Material(
        color: c.surface,
        // One hairline, no elevation and no shadow: the bar is separated from
        // the body by a line and a change of ground, which is all the
        // separation a docked control needs (`§43` — restrained elevation).
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: BorderDirectional(top: BorderSide(color: c.line)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final destination in platformDestinations)
                    Expanded(
                      child: _PlatformNavItem(
                        destination: destination,
                        selected: destination.area.branchIndex == currentIndex,
                        onTap: () => onSelected(destination.area.branchIndex),
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

/// The expanded rail. Sits at the leading edge of the shell — the *right* in
/// Arabic, which `Row` under an RTL `Directionality` produces without a single
/// conditional.
class PlatformNavigationRail extends StatelessWidget {
  const PlatformNavigationRail({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  /// Wide enough for «العمليات» on two lines at a 1.6 text scale, which is the
  /// longest label the registry can hold at the largest scale `§35` asks for.
  static const double width = 96;

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      explicitChildNodes: true,
      label: S.platformNavLabel,
      child: Material(
        color: c.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Directional, so the divider is on the inner edge in both
            // directions rather than always on the left.
            border: BorderDirectional(end: BorderSide(color: c.line)),
          ),
          child: SizedBox(
            width: width,
            child: SafeArea(
              right: false,
              left: false,
              // A short landscape window plus a large text scale can make four
              // items taller than the rail; scrolling is the only answer that
              // does not shrink something.
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.lg,
                  ),
                  child: Column(
                    children: [
                      for (final destination in platformDestinations)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _PlatformNavItem(
                            destination: destination,
                            selected:
                                destination.area.branchIndex == currentIndex,
                            onTap: () =>
                                onSelected(destination.area.branchIndex),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One destination, in either control.
///
/// Selection is carried three ways on purpose — the glyph switches from
/// outlined to filled, the icon gains a tinted plate, and the label gains
/// weight and full-strength ink — so it survives a monochrome rendering and a
/// colour-vision difference alike (`§32`: no colour-only state).
class _PlatformNavItem extends StatelessWidget {
  const _PlatformNavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final PlatformDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      // On the node itself: a screen reader's activation dispatches a
      // semantics action, which never reaches an `InkWell` under an
      // `ExcludeSemantics`. Same treatment as `ChoicePill`.
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: ConstrainedBox(
            // The comfortable-target floor. Everything above it is content
            // height, so a larger text scale grows the control instead of
            // clipping it.
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: effectiveDuration(context, MotionTokens.short),
                    curve: effectiveCurve(context, MotionTokens.standard),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? c.primaryTint : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      size: 22,
                      color: selected ? c.primary : c.ink3,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    destination.label,
                    textAlign: TextAlign.center,
                    // Two lines rather than an ellipsis or a smaller font: an
                    // abbreviated navigation label is a worse answer to a
                    // large text scale than a taller bar.
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? c.ink : c.ink3,
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
