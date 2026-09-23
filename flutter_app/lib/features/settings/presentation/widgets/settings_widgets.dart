import 'package:flutter/material.dart';

import '../../../../core/display/frame_rate.dart';
import '../../../../core/motion/motion_level.dart';
import '../../../../core/motion/motion_tokens.dart';
import '../../../../core/motion/press_scale.dart';
import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/theme_choice.dart';
import '../../../../core/widgets/forward_chevron.dart';
import '../../../../core/widgets/section_header.dart';
import '../../../../l10n/strings.dart';

/// Shared building blocks for the Settings hub and its nested category
/// screens (Themes, Performance, Sync). Extracted from the original single
/// `settings_page.dart` so every screen in the hub speaks the same visual
/// language — grouped card, section label, navigation row, picker row — and
/// so none of it exists twice.

/// The complete historical MTM palette catalogue, in its established order.
///
/// One list, so the picker and every settings summary agree about a palette's
/// name and description.
const themeChoices = <(AppThemeChoice, String, String)>[
  (
    AppThemeChoice.medical,
    S.settingsPaletteMedical,
    S.settingsPaletteMedicalSub,
  ),
  (
    AppThemeChoice.slate,
    S.settingsPaletteSlate,
    S.settingsPaletteSlateSub,
  ),
  (
    AppThemeChoice.copper,
    S.settingsPaletteCopper,
    S.settingsPaletteCopperSub,
  ),
  (AppThemeChoice.clay, S.settingsPaletteClay, S.settingsPaletteClaySub),
  (
    AppThemeChoice.indigo,
    S.settingsPaletteIndigo,
    S.settingsPaletteIndigoSub,
  ),
  (AppThemeChoice.teal, S.settingsPaletteTeal, S.settingsPaletteTealSub),
];

String themeChoiceLabel(AppThemeChoice choice) =>
    themeChoices.firstWhere((t) => t.$1 == choice).$2;

String themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.light => S.settingsModeLight,
      ThemeMode.dark => S.settingsModeDark,
      ThemeMode.system => S.settingsModeSystem,
    };

/// The plain name of a motion/quality level, and of a frame-rate preference.
///
/// Here rather than private to the Settings hub because the platform surface's
/// own settings screen shows the same one-line appearance summary from the same
/// providers. Two spellings of «متوازن» is a small drift, and a small drift
/// between two screens that claim to report one setting is still a lie on one
/// of them.
const _motionLevelLabels = <MotionLevel, String>{
  MotionLevel.performance: S.settingsMotionPerformance,
  MotionLevel.low: S.settingsMotionLow,
  MotionLevel.balanced: S.settingsMotionBalanced,
  MotionLevel.high: S.settingsMotionHigh,
  MotionLevel.maximum: S.settingsMotionMaximum,
};

String motionLevelLabel(MotionLevel level) => _motionLevelLabels[level]!;

const _frameRateLabels = <FrameRatePreference, String>{
  FrameRatePreference.auto: S.settingsFrameRateAuto,
  FrameRatePreference.fps30: S.settingsFrameRate30,
  FrameRatePreference.fps60: S.settingsFrameRate60,
  FrameRatePreference.fps90: S.settingsFrameRate90,
  FrameRatePreference.fps120: S.settingsFrameRate120,
};

String frameRateLabel(FrameRatePreference rate) => _frameRateLabels[rate]!;

/// The settings hub's name for a section eyebrow.
///
/// Kept as a name — it reads well at ~40 call sites and says «this is the
/// settings idiom» — but it is the shared [SectionHeader] underneath, so the
/// hub and the rest of the app cannot drift apart again.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => SectionHeader(title: label);
}

class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // A `Material`, not a `Container` with a `BoxDecoration`. The rows inside
    // are `ListTile`s, and a ListTile paints its ink on the nearest Material
    // ancestor — with a decorated box in between, the splash was drawn behind
    // the card's own background and never seen. (Flutter says so out loud:
    // "ListTile background color or ink splashes may be invisible", the
    // complaint several router tests used to tolerate by name.) The shape,
    // hairline and clipping are identical; the difference is that a tap on a
    // settings row now has visible feedback.
    return Material(
      color: c.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(color: c.line),
      ),
      child: Column(children: [
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1)
            Divider(height: 1, color: c.line, indent: 52),
        ],
      ]),
    );
  }
}

/// A navigable row on the hub — a category (Themes, Performance, Sync,
/// Organization) or an account destination (Profile, Security,
/// Notifications). [subtitle] is the only place a small live summary (the
/// active palette, the selected performance level, the sync state) may
/// appear on the hub — never the controls themselves.
class NavigationRow extends StatelessWidget {
  const NavigationRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.subtitleColor,
    this.iconColor,
    this.badge,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? subtitleColor;
  final VoidCallback onTap;

  /// Tints the leading glyph. Defaults to `ink2`, which is what a navigation
  /// row is: an affordance, not a signal. Passed only where the destination
  /// itself carries consequence — the platform's emergency-access row is
  /// `crit` because opening it is the first step of a grant, and a row that
  /// looked exactly like «تقارير المنصة» was the audit's complaint about it.
  final Color? iconColor;

  /// A [StatusChip]-sized widget between the text and the chevron, for live
  /// state the row's subtitle cannot carry in words alone — an active
  /// emergency grant, a report's data kind. It never replaces the chevron:
  /// the row still opens something, and that is what the chevron says.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // A badge in the trailing slot competes with the title for the row's
    // width, and at a large text scale the title loses: the reports catalogue
    // rendered «الاشتراكات» broken across two lines *mid-word* at 320 dp and
    // 1.6×. Past that scale the badge moves under the subtitle, where it has
    // the whole row, and the trailing slot goes back to being the chevron.
    final stacked = badge != null &&
        MediaQuery.textScalerOf(context).scale(14) > 19;
    final subtitleText = subtitle == null
        ? null
        : Text(
            subtitle!,
            style: TextStyle(color: subtitleColor ?? c.ink3, fontSize: 12),
          );
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: iconColor ?? c.ink2),
      title: Text(label),
      subtitle: !stacked
          ? subtitleText
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (subtitleText != null) subtitleText,
                const SizedBox(height: AppSpacing.xs),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: badge!,
                ),
              ],
            ),
      // The one forward-disclosure glyph; the mirroring rule is stated on
      // `ForwardChevron`.
      trailing: badge == null || stacked
          ? const ForwardChevron()
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                badge!,
                const SizedBox(width: AppSpacing.sm),
                const ForwardChevron(),
              ],
            ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      minVerticalPadding: AppSpacing.md,
    );
  }
}

class PickerRow extends StatelessWidget {
  const PickerRow({
    super.key,
    required this.icon,
    required this.label,
    required this.options,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget options;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: c.ink2),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.titleSmall),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle!,
                      style: TextStyle(color: c.ink3, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.md),
          options,
        ],
      ),
    );
  }
}

class ChoicePill extends StatelessWidget {
  const ChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.swatch,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Optional colour preview shown before the label. The palette row uses it
  /// so a name like "Teal" is not the only thing telling you what you are
  /// about to apply.
  final Color? swatch;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final fg = selected ? c.primaryInk : c.ink2;
    // Announce the pill as a selectable option rather than as loose text, so
    // a screen reader says "selected" instead of leaving the state invisible.
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      // Registered on the node itself: TalkBack's double-tap dispatches a
      // semantics action, which never reaches the gesture detector once the
      // subtree below is excluded.
      onTap: onTap,
      child: ExcludeSemantics(
        child: PressScale(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: AnimatedContainer(
            duration: effectiveDuration(context, MotionTokens.short),
            curve: effectiveCurve(context, MotionTokens.standard),
            padding: EdgeInsetsDirectional.only(
              start: swatch == null ? AppSpacing.md : AppSpacing.sm,
              end: AppSpacing.md,
              top: 6,
              bottom: 6,
            ),
            decoration: BoxDecoration(
              color: selected ? c.primary : c.surface2,
              border: Border.all(color: selected ? c.primary : c.line),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (swatch != null) ...[
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: swatch,
                      shape: BoxShape.circle,
                      // A hairline in the pill's own foreground, so a swatch
                      // close to the pill ground still reads as a disc.
                      border: Border.all(
                        color: fg.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    softWrap: true,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
