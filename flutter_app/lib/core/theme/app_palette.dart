import 'package:flutter/material.dart';

/// Design tokens — mirror the exact values in `tokens.css` used by the
/// admin dashboards already shipped in this workspace. Do NOT invent new
/// colors here. Any new surface must be derived from these tokens.
///
/// [medical] is the default: the clean clinical green-on-white the app opens
/// with. [slate]/[copper]/[clay] are the original earthy set; [indigo] and
/// [teal] are two cooler alternates. Eye-protect is NOT a palette — it is a
/// warm low-blue wash applied on top of any of these, see [AppColors.warmed].
enum PaletteId { medical, slate, copper, clay, indigo, teal }

class AppColors {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.line2,
    required this.primary,
    required this.primaryInk,
    required this.primaryPressed,
    required this.primaryTint,
    required this.ok,
    required this.okTint,
    required this.warn,
    required this.warnTint,
    required this.crit,
    required this.critTint,
    required this.info,
    required this.infoTint,
    required this.muted,
    required this.mutedTint,
    required this.focus,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color line;
  final Color line2;
  final Color primary;
  final Color primaryInk;
  final Color primaryPressed;
  final Color primaryTint;
  final Color ok;
  final Color okTint;
  final Color warn;
  final Color warnTint;
  final Color crit;
  final Color critTint;
  final Color info;
  final Color infoTint;
  final Color muted;
  final Color mutedTint;
  final Color focus;

  // -----------------------------------------------------------
  // Slate — light  (mirrors body[data-palette="slate"][data-mode="light"])
  // -----------------------------------------------------------
  static const AppColors slateLight = AppColors(
    bg: Color(0xFFECEAE4),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF5F3EE),
    surface3: Color(0xFFE4E1D9),
    ink: Color(0xFF1A1F26),
    ink2: Color(0xFF4A5058),
    ink3: Color(0xFF7A8189),
    line: Color(0xFFDAD6CC),
    line2: Color(0xFFC7C2B4),
    primary: Color(0xFFB84A3E),
    primaryInk: Color(0xFFFFFFFF),
    primaryPressed: Color(0xFF9E3B2F),
    primaryTint: Color(0xFFF5E4E0),
    ok: Color(0xFF1F8F5A),
    okTint: Color(0xFFDFF1E7),
    warn: Color(0xFFD48806),
    warnTint: Color(0xFFFBEBCB),
    crit: Color(0xFF7A241B),
    critTint: Color(0xFFF0D8D3),
    info: Color(0xFF1B6C99),
    infoTint: Color(0xFFDCEBF3),
    muted: Color(0xFF7C8B92),
    mutedTint: Color(0xFFE4E7E8),
    focus: Color(0xFFB84A3E),
  );

  static const AppColors slateDark = AppColors(
    bg: Color(0xFF0F1319),
    surface: Color(0xFF171C24),
    surface2: Color(0xFF1E242E),
    surface3: Color(0xFF262D38),
    ink: Color(0xFFEDECE6),
    ink2: Color(0xFFB4B7BD),
    ink3: Color(0xFF7C8189),
    line: Color(0xFF2B323D),
    line2: Color(0xFF3A424F),
    primary: Color(0xFFD26254),
    primaryInk: Color(0xFFFFFFFF),
    primaryPressed: Color(0xFFB84A3E),
    primaryTint: Color(0xFF3A1E1A),
    ok: Color(0xFF3AB878),
    okTint: Color(0xFF143726),
    warn: Color(0xFFE8A63D),
    warnTint: Color(0xFF3A2A0F),
    crit: Color(0xFFE24E3F),
    critTint: Color(0xFF3D1A16),
    info: Color(0xFF4C9BCB),
    infoTint: Color(0xFF13293A),
    muted: Color(0xFF8A939B),
    mutedTint: Color(0xFF2A303A),
    focus: Color(0xFFD26254),
  );

  // -----------------------------------------------------------
  // Copper — light
  // -----------------------------------------------------------
  static const AppColors copperLight = AppColors(
    bg: Color(0xFFEAEBEE),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF2F4F7),
    surface3: Color(0xFFDFE3E9),
    ink: Color(0xFF141B26),
    ink2: Color(0xFF46505E),
    ink3: Color(0xFF78828F),
    line: Color(0xFFD6DBE2),
    line2: Color(0xFFBFC6D0),
    primary: Color(0xFFB45341),
    primaryInk: Color(0xFFFFFFFF),
    primaryPressed: Color(0xFF96412F),
    primaryTint: Color(0xFFF3E1DA),
    ok: Color(0xFF1E8A6E),
    okTint: Color(0xFFDAF0E7),
    warn: Color(0xFFC89424),
    warnTint: Color(0xFFF7EAC9),
    crit: Color(0xFF7B2116),
    critTint: Color(0xFFEDD6D0),
    info: Color(0xFF2E6EA6),
    infoTint: Color(0xFFDCEAF5),
    muted: Color(0xFF7B8894),
    mutedTint: Color(0xFFDFE3E9),
    focus: Color(0xFFB45341),
  );

  static const AppColors copperDark = AppColors(
    bg: Color(0xFF0C121C),
    surface: Color(0xFF141C29),
    surface2: Color(0xFF1B2435),
    surface3: Color(0xFF232E43),
    ink: Color(0xFFE9ECF2),
    ink2: Color(0xFFA9B3C0),
    ink3: Color(0xFF6F7B8B),
    line: Color(0xFF253046),
    line2: Color(0xFF354061),
    primary: Color(0xFFCE6952),
    primaryInk: Color(0xFFFFFFFF),
    primaryPressed: Color(0xFFB45341),
    primaryTint: Color(0xFF3A1E17),
    ok: Color(0xFF35B48D),
    okTint: Color(0xFF12362A),
    warn: Color(0xFFDDA43B),
    warnTint: Color(0xFF38290F),
    crit: Color(0xFFDA4E3F),
    critTint: Color(0xFF3B1A15),
    info: Color(0xFF5B9CD8),
    infoTint: Color(0xFF162A45),
    muted: Color(0xFF8993A2),
    mutedTint: Color(0xFF28324A),
    focus: Color(0xFFCE6952),
  );

  // -----------------------------------------------------------
  // Clay — light
  // -----------------------------------------------------------
  static const AppColors clayLight = AppColors(
    bg: Color(0xFFEDE6D8),
    surface: Color(0xFFFCF9F2),
    surface2: Color(0xFFF3ECDA),
    surface3: Color(0xFFE3D9C1),
    ink: Color(0xFF1F1912),
    ink2: Color(0xFF4E4436),
    ink3: Color(0xFF83795F),
    line: Color(0xFFD6C9AC),
    line2: Color(0xFFBFAE87),
    primary: Color(0xFFA83A2E),
    primaryInk: Color(0xFFFFFFFF),
    primaryPressed: Color(0xFF8B2A21),
    primaryTint: Color(0xFFEFD9D3),
    ok: Color(0xFF4A7A3E),
    okTint: Color(0xFFDFE9D4),
    warn: Color(0xFFB8791A),
    warnTint: Color(0xFFF1E1BE),
    crit: Color(0xFF6B1F17),
    critTint: Color(0xFFE6CDC6),
    info: Color(0xFF2C5F8A),
    infoTint: Color(0xFFDCE5F0),
    muted: Color(0xFF857960),
    mutedTint: Color(0xFFDED4B9),
    focus: Color(0xFFA83A2E),
  );

  static const AppColors clayDark = AppColors(
    bg: Color(0xFF14100A),
    surface: Color(0xFF1E1912),
    surface2: Color(0xFF26201A),
    surface3: Color(0xFF302921),
    ink: Color(0xFFECE4D2),
    ink2: Color(0xFFB0A78F),
    ink3: Color(0xFF7A7057),
    line: Color(0xFF2E2719),
    line2: Color(0xFF40372A),
    primary: Color(0xFFC55643),
    primaryInk: Color(0xFFFFFFFF),
    primaryPressed: Color(0xFFA83A2E),
    primaryTint: Color(0xFF3A1913),
    ok: Color(0xFF6DA55A),
    okTint: Color(0xFF1C2C15),
    warn: Color(0xFFD69A2C),
    warnTint: Color(0xFF382712),
    crit: Color(0xFFC64B3D),
    critTint: Color(0xFF3A1811),
    info: Color(0xFF5989BE),
    infoTint: Color(0xFF182640),
    muted: Color(0xFF9A8E70),
    mutedTint: Color(0xFF2E2716),
    focus: Color(0xFFC55643),
  );

  // -----------------------------------------------------------
  // Medical — light  (the default: clean clinical green on white)
  // -----------------------------------------------------------
  static const AppColors medicalLight = AppColors(
    bg: Color(0xFFEEF2EF),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF1F6F3),
    surface3: Color(0xFFE0E9E3),
    ink: Color(0xFF15201B),
    ink2: Color(0xFF44514A),
    ink3: Color(0xFF76847C),
    line: Color(0xFFD7E1DB),
    line2: Color(0xFFC0CDC4),
    primary: Color(0xFF1B7F51),
    primaryInk: Color(0xFFFFFFFF),
    primaryPressed: Color(0xFF13653F),
    primaryTint: Color(0xFFDDF0E6),
    ok: Color(0xFF15803D),
    okTint: Color(0xFFDCF0E3),
    warn: Color(0xFFC8860A),
    warnTint: Color(0xFFF8EBCF),
    crit: Color(0xFF851C16),
    critTint: Color(0xFFF6DAD7),
    info: Color(0xFF1B6B98),
    infoTint: Color(0xFFD9EBF4),
    muted: Color(0xFF7C8B84),
    mutedTint: Color(0xFFE3E9E5),
    focus: Color(0xFF1B7F51),
  );

  static const AppColors medicalDark = AppColors(
    bg: Color(0xFF0D1411),
    surface: Color(0xFF141D18),
    surface2: Color(0xFF1B2620),
    surface3: Color(0xFF243029),
    ink: Color(0xFFE7EEE9),
    ink2: Color(0xFFAAB7B0),
    ink3: Color(0xFF6E7C74),
    line: Color(0xFF27332C),
    line2: Color(0xFF37453C),
    primary: Color(0xFF3FB27B),
    primaryInk: Color(0xFF0E2E1F),
    primaryPressed: Color(0xFF1E8E5A),
    primaryTint: Color(0xFF10301F),
    ok: Color(0xFF3AB878),
    okTint: Color(0xFF123626),
    warn: Color(0xFFE0A63D),
    warnTint: Color(0xFF382A10),
    crit: Color(0xFFE2554A),
    critTint: Color(0xFF3B1A17),
    info: Color(0xFF4C9BCB),
    infoTint: Color(0xFF13293A),
    muted: Color(0xFF85938B),
    mutedTint: Color(0xFF283029),
    focus: Color(0xFF3FB27B),
  );

  // -----------------------------------------------------------
  // Indigo — light
  // -----------------------------------------------------------
  static const AppColors indigoLight = AppColors(
    bg: Color(0xFFEBECF2),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFF1F2F8),
    surface3: Color(0xFFDFE1EE),
    ink: Color(0xFF161826),
    ink2: Color(0xFF464A61),
    ink3: Color(0xFF767B93),
    line: Color(0xFFD5D8E6),
    line2: Color(0xFFBEC2D6),
    primary: Color(0xFF4340C4),
    primaryInk: Color(0xFFFFFFFF),
    primaryPressed: Color(0xFF3633A6),
    primaryTint: Color(0xFFE2E2F7),
    ok: Color(0xFF1C8066),
    okTint: Color(0xFFD9F0E8),
    warn: Color(0xFFC28A1E),
    warnTint: Color(0xFFF5E9C8),
    crit: Color(0xFF831C16),
    critTint: Color(0xFFF3D9D6),
    info: Color(0xFF2C699E),
    infoTint: Color(0xFFDBEAF5),
    muted: Color(0xFF7C8195),
    mutedTint: Color(0xFFE0E2EE),
    focus: Color(0xFF4340C4),
  );

  static const AppColors indigoDark = AppColors(
    bg: Color(0xFF0C0D18),
    surface: Color(0xFF141625),
    surface2: Color(0xFF1B1E31),
    surface3: Color(0xFF23273F),
    ink: Color(0xFFE9EAF3),
    ink2: Color(0xFFA9AEC5),
    ink3: Color(0xFF6F7593),
    line: Color(0xFF262A44),
    line2: Color(0xFF363B5C),
    primary: Color(0xFF7B79E8),
    primaryInk: Color(0xFF05041F),
    primaryPressed: Color(0xFF4340C4),
    primaryTint: Color(0xFF1E1D3E),
    ok: Color(0xFF35B48D),
    okTint: Color(0xFF11362A),
    warn: Color(0xFFDDA43B),
    warnTint: Color(0xFF38290F),
    crit: Color(0xFFDB5445),
    critTint: Color(0xFF3B1A15),
    info: Color(0xFF5B9CD8),
    infoTint: Color(0xFF162A45),
    muted: Color(0xFF868BA2),
    mutedTint: Color(0xFF272B45),
    focus: Color(0xFF7B79E8),
  );

  // -----------------------------------------------------------
  // Teal — light
  // -----------------------------------------------------------
  static const AppColors tealLight = AppColors(
    bg: Color(0xFFE9EFEE),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEFF5F4),
    surface3: Color(0xFFDCE7E5),
    ink: Color(0xFF12201F),
    ink2: Color(0xFF42514F),
    ink3: Color(0xFF738381),
    line: Color(0xFFD2DEDC),
    line2: Color(0xFFB9C9C6),
    primary: Color(0xFF0F7B85),
    primaryInk: Color(0xFFFFFFFF),
    primaryPressed: Color(0xFF0B626A),
    primaryTint: Color(0xFFD6ECEE),
    ok: Color(0xFF1C8151),
    okTint: Color(0xFFDCF0E5),
    warn: Color(0xFFC2870F),
    warnTint: Color(0xFFF6E9C9),
    crit: Color(0xFF7C251E),
    critTint: Color(0xFFF0DAD5),
    info: Color(0xFF206B91),
    infoTint: Color(0xFFD9E9F2),
    muted: Color(0xFF778784),
    mutedTint: Color(0xFFDFE8E6),
    focus: Color(0xFF0F7B85),
  );

  static const AppColors tealDark = AppColors(
    bg: Color(0xFF091413),
    surface: Color(0xFF101D1C),
    surface2: Color(0xFF162625),
    surface3: Color(0xFF1F302F),
    ink: Color(0xFFE5EEED),
    ink2: Color(0xFFA7B6B4),
    ink3: Color(0xFF6C7C79),
    line: Color(0xFF223231),
    line2: Color(0xFF324442),
    primary: Color(0xFF29AAB4),
    primaryInk: Color(0xFF08292C),
    primaryPressed: Color(0xFF0F7C86),
    primaryTint: Color(0xFF0B3033),
    ok: Color(0xFF35B48D),
    okTint: Color(0xFF11362A),
    warn: Color(0xFFDDA43B),
    warnTint: Color(0xFF38290F),
    crit: Color(0xFFDB5445),
    critTint: Color(0xFF3B1A15),
    info: Color(0xFF5B9CD8),
    infoTint: Color(0xFF162A45),
    muted: Color(0xFF849492),
    mutedTint: Color(0xFF243433),
    focus: Color(0xFF29AAB4),
  );

  static AppColors resolve(PaletteId id, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    return switch (id) {
      PaletteId.medical => isLight ? medicalLight : medicalDark,
      PaletteId.slate => isLight ? slateLight : slateDark,
      PaletteId.copper => isLight ? copperLight : copperDark,
      PaletteId.clay => isLight ? clayLight : clayDark,
      PaletteId.indigo => isLight ? indigoLight : indigoDark,
      PaletteId.teal => isLight ? tealLight : tealDark,
    };
  }

  /// Eye-protect: a warm, low-blue wash of this palette.
  ///
  /// Not a palette of its own — it recolours already-resolved tokens toward
  /// amber so it composes with all six and with both light and dark. The
  /// surfaces move most, text moves a little so contrast holds, and the
  /// semantic colours (ok / warn / crit / info) are left untouched so a
  /// warning still reads as a warning through the filter.
  AppColors warmed() => _warmCache[this] ??= _buildWarmed();

  /// Warms the **ground only** — backgrounds, surfaces, hairlines and the
  /// status tints. Text, icons, the primary and every semantic colour come
  /// back untouched.
  ///
  /// That asymmetry is the whole design. A filter that warms the foreground
  /// too pulls dark text up toward the amber and light text down into it, and
  /// the screen loses contrast exactly where it is read. Moving only the
  /// ground keeps every foreground/background pair above the floors asserted
  /// by `test/core/theme/palette_contrast_test.dart`.
  ///
  /// One factor for every ground token, rather than a per-token table: the
  /// palettes encode their depth in the *gaps* between `bg`, `surface` and
  /// `surface2`, and warming those at different rates flattens the hierarchy
  /// the layout depends on. A single pull moves them together.
  ///
  /// The target and the strength are picked per brightness. A light theme
  /// drifts toward a paper cream; a dark theme toward a warm coal, and more
  /// gently, because a dark ground reaches its target far sooner.
  AppColors _buildWarmed() {
    // Read from the palette's own background rather than from a flag, so the
    // transform stays correct for any palette added later.
    final dark = bg.computeLuminance() < 0.5;
    final target = dark ? const Color(0xFF2A1C08) : const Color(0xFFFFE7C2);
    final amount = dark ? 0.28 : 0.40;
    Color w(Color base) => Color.lerp(base, target, amount) ?? base;

    return AppColors(
      bg: w(bg),
      surface: w(surface),
      surface2: w(surface2),
      surface3: w(surface3),
      ink: ink,
      ink2: ink2,
      ink3: ink3,
      line: w(line),
      line2: w(line2),
      primary: primary,
      primaryInk: primaryInk,
      primaryPressed: primaryPressed,
      primaryTint: w(primaryTint),
      ok: ok,
      okTint: w(okTint),
      warn: warn,
      warnTint: w(warnTint),
      crit: crit,
      critTint: w(critTint),
      info: info,
      infoTint: w(infoTint),
      muted: muted,
      mutedTint: w(mutedTint),
      focus: focus,
    );
  }

  /// `MaterialApp` rebuilds its `ThemeData` on every frame that touches the
  /// root, and the wash is ~15 blends. There are only twelve palette
  /// variants, all canonical `const` instances, so memoising on identity
  /// bounds the work to one pass each for the life of the isolate.
  static final Map<AppColors, AppColors> _warmCache = {};
}

/// Access colors from context via `Theme.of(context).extension<AppColors>()`.
class AppColorsExt extends ThemeExtension<AppColorsExt> {
  const AppColorsExt(this.c);
  final AppColors c;

  @override
  ThemeExtension<AppColorsExt> copyWith({AppColors? c}) =>
      AppColorsExt(c ?? this.c);

  @override
  ThemeExtension<AppColorsExt> lerp(
    covariant ThemeExtension<AppColorsExt>? other,
    double t,
  ) =>
      this;
}

extension AppColorsX on BuildContext {
  AppColors get c => Theme.of(this).extension<AppColorsExt>()!.c;
}
