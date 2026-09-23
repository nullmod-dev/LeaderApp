import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/display/frame_rate.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/motion/motion_level.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/reading_column.dart';
import '../../../l10n/strings.dart';
import '../../shell/main_shell.dart';
import '../data/frame_rate_provider.dart';
import '../data/motion_level_provider.dart';
import 'widgets/settings_widgets.dart';
import 'widgets/theme_choice_card.dart';

/// The one canonical appearance-and-performance screen (`/more/themes`).
///
/// It replaces the pair of screens that used to split these controls, in the
/// order a user actually decides them: palette, reading comfort, appearance,
/// then how much work it does per frame and what it asks of the display. There
/// is no second theme or performance screen — `/more/performance` redirects
/// here — and no control on it is new: the theme cards write
/// `themeControllerProvider`, the quality pills write `motionLevelProvider`
/// and the frame-rate pills write `frameRateProvider`, exactly as before.
///
/// Reading comfort remains independent state, but this is its only
/// user-facing control. It never changes either palette or appearance.
///
/// **The Leader mark is not on this screen, and is not a setting.** There was
/// briefly a «شعار ليدر» section here offering three variants of the lockup.
/// A product's own mark is the one thing that has to be the same object every
/// time it appears — home screen, launch, About — and the launcher icon could
/// never follow the choice anyway (Android only swaps one by toggling
/// activity-aliases, which drops the user's placed shortcut). The selector,
/// its persisted value and its two alternate assets are gone; see
/// `core/brand/brand_mark.dart`.
class ThemesAndPerformancePage extends ConsumerWidget {
  const ThemesAndPerformancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final theme = ref.watch(themeStateProvider);
    final motion = ref.watch(motionLevelProvider);
    final selectedChoice = theme.choice;
    final previewBrightness = switch (theme.mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: const Text(S.sectionThemesPerformance)),
      // One column of label↔value rows: capped at the reading measure so a
      // tablet gains margins instead of a row whose label and value sit at
      // opposite ends of the window. Below 520 dp nothing changes.
      body: FloatingNavPadding(
        child: ReadingColumn(
            child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            // ---- Theme first ----
            const SectionLabel(S.settingsThemeSection),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.xs,
                bottom: AppSpacing.md,
              ),
              child: Text(
                S.settingsThemeSectionSub,
                style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
              ),
            ),
            for (final (choice, label, description) in themeChoices) ...[
              ThemeChoiceCard(
                choice: choice,
                label: label,
                description: description,
                selected: selectedChoice == choice,
                eyeProtect: theme.eyeProtect,
                previewBrightness: previewBrightness,
                onTap: () => ref
                    .read(themeControllerProvider.notifier)
                    .setThemeChoice(choice),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            SettingsSection(children: [
              // Eye Protection directly follows the palette catalogue. It is
              // a wash, not a palette or an appearance mode.
              PickerRow(
                key: const Key('themes-eye-protection'),
                icon: Icons.visibility_outlined,
                label: S.settingsEyeProtect,
                subtitle: S.settingsEyeProtectSub,
                options: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    ChoicePill(
                      label: S.settingsEyeProtectOn,
                      selected: theme.eyeProtect,
                      onTap: () => ref
                          .read(themeControllerProvider.notifier)
                          .setEyeProtect(true),
                    ),
                    ChoicePill(
                      label: S.settingsEyeProtectOff,
                      selected: !theme.eyeProtect,
                      onTap: () => ref
                          .read(themeControllerProvider.notifier)
                          .setEyeProtect(false),
                    ),
                  ],
                ),
              ),
              // Appearance follows Eye Protection for every palette.
              PickerRow(
                key: const Key('themes-appearance'),
                icon: Icons.contrast_rounded,
                label: S.settingsLightMode,
                subtitle: S.settingsLightModeSub,
                options: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final (mode, label) in const [
                      (ThemeMode.light, S.settingsModeLight),
                      (ThemeMode.dark, S.settingsModeDark),
                      (ThemeMode.system, S.settingsModeSystem),
                    ])
                      ChoicePill(
                        label: label,
                        selected: theme.mode == mode,
                        onTap: () => ref
                            .read(themeControllerProvider.notifier)
                            .setMode(mode),
                      ),
                  ],
                ),
              ),
            ]),
            // ---- Then performance ----
            const SectionLabel(S.settingsPerformanceSection),
            SettingsSection(children: [
              PickerRow(
                icon: Icons.auto_awesome_outlined,
                label: S.settingsQuality,
                subtitle: S.settingsQualitySub,
                options: motion.when(
                  loading: () => const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (_, __) => TextButton(
                    onPressed: () => ref.invalidate(motionLevelProvider),
                    child: const Text(S.retry),
                  ),
                  data: (level) => _MotionPicker(level: level),
                ),
              ),
              PickerRow(
                icon: Icons.speed_rounded,
                label: S.settingsFrameRate,
                subtitle: S.settingsFrameRateSub,
                options: _FrameRatePicker(
                  // The note below the pills is the only place the two
                  // settings meet, and it is advice, not enforcement: a
                  // lightest-quality user who wants 90Hz still gets 90Hz.
                  lightestQuality:
                      motion.valueOrNull == MotionLevel.performance,
                ),
              ),
            ]),
          ],
        )),
      ),
    );
  }
}

/// The five-step performance picker.
///
/// Ordered cheapest to richest so the row reads as one scale, and every step
/// says in plain words what it does — the choice is about the device in the
/// user's hand, not about taste.
class _MotionPicker extends ConsumerWidget {
  const _MotionPicker({required this.level});

  final MotionLevel level;

  static const _steps = <(MotionLevel, String, String)>[
    (
      MotionLevel.performance,
      S.settingsMotionPerformance,
      S.settingsMotionPerformanceHint
    ),
    (MotionLevel.low, S.settingsMotionLow, S.settingsMotionLowHint),
    (
      MotionLevel.balanced,
      S.settingsMotionBalanced,
      S.settingsMotionBalancedHint
    ),
    (MotionLevel.high, S.settingsMotionHigh, S.settingsMotionHighHint),
    (MotionLevel.maximum, S.settingsMotionMaximum, S.settingsMotionMaximumHint),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final hint = _steps.firstWhere((s) => s.$1 == level).$3;
    // The platform flag outranks the picker, so say so rather than letting
    // the screen look broken when nothing animates.
    final osOverridden = osReduceMotion(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (value, label, _) in _steps)
              ChoicePill(
                label: label,
                selected: level == value,
                onTap: () => ref.read(motionLevelProvider.notifier).set(value),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AnimatedSwitcher(
          duration: effectiveDuration(context, MotionTokens.short),
          child: Text(
            hint,
            key: ValueKey(level),
            style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
          ),
        ),
        if (osOverridden) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.accessibility_new_rounded, size: 14, color: c.warn),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  S.settingsMotionOsNotice,
                  style: TextStyle(color: c.warn, fontSize: 12, height: 1.5),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The frame-rate picker.
///
/// Two facts drive it, and both come from the device rather than from a
/// wish list: which rates the panel actually has a display mode for, and
/// whether the platform lets an app ask for one. A device that can do
/// neither gets a single Auto pill and a sentence saying why — a row of
/// choices that quietly did nothing would be worse than no row at all.
class _FrameRatePicker extends ConsumerWidget {
  const _FrameRatePicker({required this.lightestQuality});

  /// Whether the performance level is the lightest one. Only used to explain
  /// a combination that spends battery for nothing; it never removes a pill
  /// and never rewrites the stored preference.
  final bool lightestQuality;

  static const _labels = <FrameRatePreference, String>{
    FrameRatePreference.auto: S.settingsFrameRateAuto,
    FrameRatePreference.fps30: S.settingsFrameRate30,
    FrameRatePreference.fps60: S.settingsFrameRate60,
    FrameRatePreference.fps90: S.settingsFrameRate90,
    FrameRatePreference.fps120: S.settingsFrameRate120,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final caps = ref.watch(displayCapabilitiesProvider);
    final pref = ref.watch(frameRateProvider);

    return caps.when(
      loading: () => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (_, __) => TextButton(
        onPressed: () => ref.invalidate(displayCapabilitiesProvider),
        child: const Text(S.retry),
      ),
      data: (caps) {
        final options = availableFrameRates(caps);
        final selected = pref.valueOrNull ?? FrameRatePreference.auto;
        final exact = isFrameRateExact(selected, caps);
        final hz = selected.hz;
        final highRate = hz != null && hz > 60;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final option in options)
                  ChoicePill(
                    label: _labels[option]!,
                    selected: selected == option,
                    onTap: () =>
                        ref.read(frameRateProvider.notifier).set(option),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              selected == FrameRatePreference.auto
                  ? S.settingsFrameRateAutoHint
                  : S.settingsFrameRateFixedHint,
              style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
            ),
            // Only claim the exact number when the panel can hold it.
            if (!exact) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                S.settingsFrameRateNearest,
                style: TextStyle(color: c.warn, fontSize: 12, height: 1.5),
              ),
            ],
            if (lightestQuality && highRate) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                S.settingsFrameRatePerformanceNote,
                style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
              ),
            ],
            if (!caps.canChoose) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: c.ink3),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      S.settingsFrameRateUnsupported,
                      style:
                          TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
                    ),
                  ),
                ],
              ),
            ],
            if (caps.activeRate != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${S.settingsFrameRateCurrent}: '
                '${toArabicIndic(caps.activeRate!.round().toString())} '
                '${S.settingsFrameRateHz}',
                style: TextStyle(color: c.ink3, fontSize: 12, height: 1.5),
              ),
            ],
          ],
        );
      },
    );
  }
}
