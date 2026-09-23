import 'package:flutter/material.dart';

import 'app_palette.dart';
import 'theme_state.dart';

/// The six established MTM visual palettes, expressed on top of the palette
/// engine rather than beside it.
///
/// The app renders from [PaletteId] + [ThemeMode] and always will — that is
/// where the tokens, the eye-protect wash and the contrast test all live.
/// Each choice maps one-to-one to [PaletteId]. Appearance is deliberately a
/// separate axis: every palette supports Light, Dark and System, and
/// Eye Protection remains independent of both.
enum AppThemeChoice {
  medical(PaletteId.medical),
  slate(PaletteId.slate),
  copper(PaletteId.copper),
  clay(PaletteId.clay),
  indigo(PaletteId.indigo),
  teal(PaletteId.teal);

  const AppThemeChoice(this.palette);

  /// The palette this theme paints with.
  final PaletteId palette;

  /// Compatibility aliases for code and stored test fixtures written while
  /// the six palettes were temporarily collapsed into three product cards.
  static const darkCyber = teal;
  static const purpleArena = indigo;
  static const light = medical;

  /// Every palette has the same independent appearance choice.
  bool get hasModeChoice => true;

  ThemeMode get defaultMode => ThemeMode.light;

  Brightness get previewBrightness => Brightness.light;

  /// Which choice a palette belongs to. One-to-one and exhaustive.
  static AppThemeChoice ofPalette(PaletteId palette) => switch (palette) {
        PaletteId.medical => AppThemeChoice.medical,
        PaletteId.slate => AppThemeChoice.slate,
        PaletteId.copper => AppThemeChoice.copper,
        PaletteId.clay => AppThemeChoice.clay,
        PaletteId.indigo => AppThemeChoice.indigo,
        PaletteId.teal => AppThemeChoice.teal,
      };
}

extension ThemeStateChoice on ThemeState {
  /// The theme this state represents.
  AppThemeChoice get choice => AppThemeChoice.ofPalette(palette);

  /// This state with [next] applied — palette only. Appearance and
  /// Eye Protection are independent and stay untouched.
  ///
  /// Re-picking the theme already in use is a no-op, so tapping the selected
  /// card cannot quietly reset a light-theme user's dark mode back to light.
  ThemeState withChoice(AppThemeChoice next) =>
      next == choice ? this : copyWith(palette: next.palette);

  /// Kept as a compatibility seam for callers written during the temporary
  /// three-card model. All six palette/mode pairs are now valid.
  ThemeState normalizedForChoice() => this;
}
