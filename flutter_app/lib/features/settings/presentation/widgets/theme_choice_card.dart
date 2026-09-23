import 'package:flutter/material.dart';

import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/motion/press_scale.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_choice.dart';
import '../../../../l10n/strings.dart';

/// One of the three product themes, as a compact row with a real preview.
///
/// The preview is resolved from the theme's own tokens — the same
/// `AppColors.resolve` the app paints with, warmed when reading comfort is
/// on — so the swatch shows what the tap will actually do rather than a
/// hand-drawn approximation that can drift from the palette.
///
/// Deliberately small: a full-bleed theme mockup would push the performance
/// controls below the fold on a phone, and the choice applies instantly
/// anyway, so the whole screen is the real preview.
class ThemeChoiceCard extends StatelessWidget {
  const ThemeChoiceCard({
    super.key,
    required this.choice,
    required this.label,
    required this.description,
    required this.selected,
    required this.eyeProtect,
    required this.previewBrightness,
    required this.onTap,
  });

  final AppThemeChoice choice;
  final String label;
  final String description;
  final bool selected;

  /// Whether the reading-comfort wash is on. The preview carries it so the
  /// two settings are visibly independent: turning comfort on changes every
  /// card's ground and none of the cards' identity.
  final bool eyeProtect;
  final Brightness previewBrightness;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: PressScale(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: AnimatedContainer(
            duration: effectiveDuration(context, MotionTokens.short),
            curve: effectiveCurve(context, MotionTokens.standard),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: selected ? c.primaryTint : c.surface,
              border: Border.all(
                color: selected ? c.primary : c.line,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(
              children: [
                _Preview(
                  choice: choice,
                  eyeProtect: eyeProtect,
                  brightness: previewBrightness,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: c.ink,
                          fontSize: 15,
                          // Weight, the check mark and the border all carry
                          // the selected state, so it never rests on colour
                          // alone.
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          color: c.ink3,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 22,
                  color: selected ? c.primary : c.line2,
                  semanticLabel: selected ? S.settingsThemeSelected : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A miniature of the theme: its ground, a surface card on top of it, its
/// primary, and a line of body ink — the four tokens that decide whether a
/// theme reads as light, dark, cyan or purple at a glance.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.choice,
    required this.eyeProtect,
    required this.brightness,
  });

  final AppThemeChoice choice;
  final bool eyeProtect;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final base = AppColors.resolve(choice.palette, brightness);
    final p = eyeProtect ? base.warmed() : base;

    return Container(
      width: 64,
      height: 46,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: p.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: p.line),
              ),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Container(
                width: 18,
                height: 6,
                decoration: BoxDecoration(
                  color: p.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: p.ink3,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
