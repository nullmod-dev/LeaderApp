import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/motion/motion_tokens.dart';

/// The **entry surface**: the one ground the app's front door is painted on,
/// shared by the launch intro (`/startup`) and the sign-in form (`/login`).
///
/// **Why these two screens have their own colours at all.** Every other
/// screen paints from `AppColors` and must, because the user picked that
/// palette. These two come *before* there is a user: they are what the
/// product looks like when nothing has been chosen yet, they carry the Clean
/// Layer mark, and the design takes its palette straight out of that mark's
/// own glass — a teal ground lit from above with a single frosted panel on
/// it. The values are scoped to this file, they are not an `AppColors`
/// palette, they never leak into one, and no screen outside the entry
/// experience may read them.
///
/// **One surface, two screens, so the handoff is invisible.** The intro and
/// the form draw the *same* gradient, the same ambient washes and the same
/// pulse. The route change between them therefore cross-fades content over a
/// ground that never moves, which is what keeps a cold launch from reading as
/// two screens with a flash between them.
///
/// **Appearance and Eye Protection still apply.** Light and dark are two full
/// token sets, and the reading-comfort wash is the same transform the palette
/// engine uses (`AppColors.warmed`): the same warm target, the same strength,
/// and — the point of it — the **ground only**. Ink, the accent and the
/// danger colour come back untouched, because warming a foreground is what
/// costs contrast where text is read.
///
/// **Contrast is checked, not eyeballed.** `test/features/auth/
/// entry_surface_test.dart` holds every ink on this surface to WCAG AA
/// against the ground it is actually drawn on, in light, dark and both
/// eye-protect variants. Change a hex here and run it.
@immutable
class EntryGlass {
  const EntryGlass({
    required this.baseTop,
    required this.baseMid,
    required this.baseBottom,
    required this.horizon,
    required this.wash1,
    required this.wash2,
    required this.pulse,
    required this.pulsePeak,
    required this.fg,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accentInk,
    required this.onAccent,
    required this.ctaDisabled,
    required this.onCtaDisabled,
    required this.danger,
    required this.dangerWash,
    required this.glassTop,
    required this.glassMid,
    required this.glassBottom,
    required this.glassBorder,
    required this.sheen,
    required this.fieldFill,
    required this.fieldFocusFill,
    required this.fieldBorder,
    required this.hairline,
    required this.panelShadow,
    required this.ctaShadow,
    required this.markGlow,
  });

  /// The three stops of the 168° ground gradient.
  final Color baseTop;
  final Color baseMid;
  final Color baseBottom;

  /// The screen's light source: one wide, soft glow seated off the top edge.
  ///
  /// Everything else on the surface is lit consistently with it — the panel's
  /// sheen runs along its top edge, the panel's shadow falls downward, and the
  /// CTA's coloured shadow does too. Without a stated light source a glass
  /// screen reads as flat translucency rather than depth.
  final Color horizon;

  /// Two ambient washes, never under text.
  final Color wash1;
  final Color wash2;

  /// The colour the ambient pulse is drawn in, and the alpha its brightest
  /// frame reaches. Light adds light in both appearances: on the dark ground
  /// this is a mint that lifts it, on the light ground a near-white that
  /// brightens it — a pulse *darker* than its ground reads as a stain.
  final Color pulse;
  final double pulsePeak;

  /// Text roles. [fg] for headings and input, [muted] for supporting copy and
  /// labels, [faint] for the divider word and the footer.
  final Color fg;
  final Color muted;
  final Color faint;

  /// The mark's own mint (dark) / deep teal (light), the ink on it, and —
  /// [accentInk] — the deeper value the accent takes when it is **text**.
  ///
  /// They are two tokens because they answer two different questions. A
  /// filled button, a focus ring and a border are UI components and clear
  /// their 3:1 bar at [accent]; a 13.5 sp link is prose and has to clear
  /// 4.5:1 against the *ground*, which on the light surface [accent] does
  /// not. Using one value for both is how a brand-coloured link ends up
  /// failing contrast on exactly the screen everyone sees first.
  final Color accent;
  final Color accentInk;
  final Color onAccent;

  /// The primary action when there is nothing to submit yet — a real pair of
  /// colours rather than the accent at some opacity.
  ///
  /// The empty form is the **first thing everyone sees**, so the disabled CTA
  /// is the most-viewed state on the most-viewed screen. Diluting the accent
  /// with alpha produced exactly what the redesign was asked to fix: a muddy,
  /// washed-out slab where the brand colour should be. This is instead a
  /// quiet, fully opaque chip — unmistakably not the accent, unmistakably
  /// still a button — and its label clears 4.5:1 on it, which is more than
  /// the convention asks of a disabled control and the right amount for one
  /// whose whole job is to say *what is still missing*.
  final Color ctaDisabled;
  final Color onCtaDisabled;

  /// Error text/border, and the wash behind a refusal notice.
  final Color danger;
  final Color dangerWash;

  /// The frosted panel's fill gradient, its border, and the 1px light across
  /// its top edge.
  final Color glassTop;
  final Color glassMid;
  final Color glassBottom;
  final Color glassBorder;
  final Color sheen;

  /// Fields sit *inside* the panel, so they use flat translucency rather than
  /// a second blur — nested blur is what makes glass UIs look muddy. The well
  /// is a shade away from the panel rather than the same white, because a
  /// white field on a white panel is identifiable only by its border.
  ///
  /// [fieldFocusFill] is the focused well: it **brightens**, so focus is
  /// carried by the surface as well as by the ring and the border.
  final Color fieldFill;
  final Color fieldFocusFill;
  final Color fieldBorder;

  /// The divider rules.
  final Color hairline;

  /// Cast under the panel, under the primary action, and under the mark.
  ///
  /// [ctaShadow] is tinted with the accent rather than black: the button is
  /// the one lit object on the screen, and a coloured shadow is what makes it
  /// read as lit rather than merely stacked.
  final Color panelShadow;
  final Color ctaShadow;
  final Color markGlow;

  /// Resolves the set for [brightness], warmed when reading comfort is on.
  static EntryGlass resolve(Brightness brightness, {bool eyeProtect = false}) {
    final base = brightness == Brightness.dark ? _dark : _light;
    return eyeProtect ? base.warmed() : base;
  }

  /// Whether this set is the dark one. Used where a treatment has to be
  /// stronger on one ground than the other (the focus ring's opacity).
  bool get isDark => baseMid.computeLuminance() < 0.5;

  /// The ring drawn around a focused field: 4dp of the accent, heavier on the
  /// dark ground where a thin ring on near-black disappears.
  List<BoxShadow> get focusRing => [
        BoxShadow(
          color: accent.withValues(alpha: isDark ? 0.28 : 0.20),
          blurRadius: 0,
          spreadRadius: 4,
        ),
      ];

  /// Warms the ground and leaves every foreground alone.
  ///
  /// Deliberately the same transform as `AppColors.warmed()` — same target,
  /// same strength, same asymmetry. Eye Protection has to feel like one
  /// setting across the app, and it cannot be allowed to cost contrast on the
  /// one screen that is nothing but a form.
  EntryGlass warmed() {
    final dark = isDark;
    final target = dark ? const Color(0xFF2A1C08) : const Color(0xFFFFE7C2);
    final amount = dark ? 0.28 : 0.40;
    // The one deviation from `AppColors.warmed`, and it is a consequence of
    // this surface having translucent ground tokens where the palette has
    // only opaque ones. `Color.lerp` interpolates **alpha** as well, and the
    // warm target is opaque — so lerping a 8%-alpha wash 40% of the way there
    // lands it at 45% alpha, which does not warm the ambience, it turns it
    // into a curtain. Each token keeps its own opacity and moves only in hue.
    Color w(Color c) =>
        (Color.lerp(c, target, amount) ?? c).withValues(alpha: c.a);
    return EntryGlass(
      baseTop: w(baseTop),
      baseMid: w(baseMid),
      baseBottom: w(baseBottom),
      horizon: w(horizon),
      wash1: w(wash1),
      wash2: w(wash2),
      pulse: w(pulse),
      pulsePeak: pulsePeak,
      fg: fg,
      muted: muted,
      faint: faint,
      accent: accent,
      accentInk: accentInk,
      onAccent: onAccent,
      ctaDisabled: ctaDisabled,
      onCtaDisabled: onCtaDisabled,
      danger: danger,
      dangerWash: w(dangerWash),
      // The glass fill and border are white-alpha, so warming them would only
      // tint the light passing through. The ground under them already carries
      // the wash.
      glassTop: glassTop,
      glassMid: glassMid,
      glassBottom: glassBottom,
      glassBorder: glassBorder,
      sheen: sheen,
      fieldFill: fieldFill,
      fieldFocusFill: fieldFocusFill,
      fieldBorder: fieldBorder,
      hairline: hairline,
      panelShadow: panelShadow,
      ctaShadow: ctaShadow,
      markGlow: markGlow,
    );
  }

  /// Dark is the appearance the mark was built for.
  static const EntryGlass _dark = EntryGlass(
    baseTop: Color(0xFF08272B),
    baseMid: Color(0xFF03181A),
    baseBottom: Color(0xFF010D0F),
    horizon: Color(0x593E9C8C),
    wash1: Color(0x6B3FA48E),
    wash2: Color(0x7A1D6675),
    pulse: Color(0xFF6FE3C4),
    pulsePeak: 0.19,
    fg: Color(0xFFEFF9F7),
    muted: Color(0xFFAFC6C3),
    faint: Color(0xFF8DA5A3),
    accent: Color(0xFF5FDCBB),
    accentInk: Color(0xFF6FE3C4),
    onAccent: Color(0xFF00201E),
    ctaDisabled: Color(0xFF26544C),
    onCtaDisabled: Color(0xFF9CC6BB),
    danger: Color(0xFFFF8A80),
    dangerWash: Color(0x1FE04A44),
    glassTop: Color(0x1FFFFFFF),
    glassMid: Color(0x0DFFFFFF),
    glassBottom: Color(0x14FFFFFF),
    glassBorder: Color(0x2EFFFFFF),
    sheen: Color(0x70FFFFFF),
    fieldFill: Color(0x14FFFFFF),
    fieldFocusFill: Color(0x26FFFFFF),
    fieldBorder: Color(0x29FFFFFF),
    hairline: Color(0x24FFFFFF),
    panelShadow: Color(0xE0000709),
    ctaShadow: Color(0x665FDCBB),
    markGlow: Color(0x7A46AF95),
  );

  static const EntryGlass _light = EntryGlass(
    baseTop: Color(0xFFE3F4F0),
    baseMid: Color(0xFFD1EAE5),
    baseBottom: Color(0xFFBBDADB),
    // Deliberately weaker than the dark ground's light source. White on a
    // light ground bleaches rather than illuminates, and the first version of
    // this surface washed its top third out to near-paper — which is what
    // made a screen built on a coloured ground read as a grey one.
    horizon: Color(0x59FFFFFF),
    wash1: Color(0x9459BFAA),
    wash2: Color(0xA36FBFD0),
    pulse: Color(0xFFF2FFFA),
    pulsePeak: 0.50,
    fg: Color(0xFF0C2A2D),
    muted: Color(0xFF3F5B5C),
    faint: Color(0xFF44605F),
    accent: Color(0xFF0B7F75),
    accentInk: Color(0xFF07605A),
    onAccent: Color(0xFFFFFFFF),
    ctaDisabled: Color(0xFF9CC6C1),
    onCtaDisabled: Color(0xFF0F3D39),
    danger: Color(0xFFB02325),
    dangerWash: Color(0x14D14B45),
    glassTop: Color(0xD6FFFFFF),
    glassMid: Color(0x9CFFFFFF),
    glassBottom: Color(0xBFFFFFFF),
    glassBorder: Color(0xE0FFFFFF),
    sheen: Color(0xF5FFFFFF),
    fieldFill: Color(0x8FBFE2DC),
    fieldFocusFill: Color(0xD9FFFFFF),
    fieldBorder: Color(0xFF8AACA8),
    hairline: Color(0xFFA9C4C0),
    panelShadow: Color(0x66274A4C),
    ctaShadow: Color(0x4D0B7F75),
    markGlow: Color(0x593F7E78),
  );
}

/// The entry surface's ground: a gradient, a light source, two ambient
/// washes and the pulse.
///
/// The washes are painted as radial gradients rather than blurred layers. A
/// `BackdropFilter` behind the whole screen would be the single most
/// expensive thing in the app, for an effect a gradient reproduces exactly —
/// and this way the ambience costs the same on every device tier, leaving the
/// blur budget for the one surface that needs it: the panel.
class EntryBackdrop extends StatelessWidget {
  const EntryBackdrop({
    super.key,
    required this.glass,
    required this.child,
    this.pulseCenter = const Alignment(0, -0.06),
    this.pausePulse = false,
  });

  final EntryGlass glass;

  /// Where the pulse originates, as a fraction of the box. The intro seats it
  /// on the mark; Login seats it just above the panel.
  final Alignment pulseCenter;

  /// Stops the ambient repaint loop while the person is actively editing a
  /// field. The still pulse remains visible; only its background repaint is
  /// paused so the frosted panel above it can stay cached during keyboard
  /// and focus work.
  final bool pausePulse;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          // 168° in CSS ≈ top-ish to bottom-ish with a slight lean.
          begin: const Alignment(-0.35, -1),
          end: const Alignment(0.35, 1),
          stops: const [0, 0.46, 1],
          colors: [glass.baseTop, glass.baseMid, glass.baseBottom],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The light source first, so everything else sits under it.
          _Wash(
            color: glass.horizon,
            alignment: const Alignment(0, -1.15),
            scale: 1.35,
          ),
          _Wash(color: glass.wash1, alignment: const Alignment(0.88, -0.5)),
          _Wash(
            color: glass.wash2,
            alignment: const Alignment(-0.92, 0.8),
            scale: 1.05,
          ),
          EntryPulse(
            glass: glass,
            center: pulseCenter,
            paused: pausePulse,
          ),
          child,
        ],
      ),
    );
  }
}

class _Wash extends StatelessWidget {
  const _Wash({
    required this.color,
    required this.alignment,
    this.scale = 1,
  });

  final Color color;
  final Alignment alignment;
  final double scale;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: alignment,
              radius: 0.9 * scale,
              colors: [color, color.withValues(alpha: 0)],
              stops: const [0, 1],
            ),
          ),
        ),
      );
}

/// The entry surface's one piece of ongoing motion: a slow pulse.
///
/// **What it is.** A breathing core of light, and two soft rings leaving it
/// half a cycle apart and fading as they widen. One cycle is
/// [period] — slower than a resting heart rate, which is the point: the
/// screen should read as *awake*, not as *waiting*. Leader coordinates
/// emergency teams, and a calm outward pulse is the one ambient idea that
/// says "the system is live" without a spinner, a particle field or an ECG
/// cliché.
///
/// **What it deliberately is not.** It never moves, resizes or overlaps a
/// control: it is a painter behind the form, inside an `IgnorePointer`, and
/// it participates in no layout. It runs no `BackdropFilter` and allocates
/// nothing per frame but three radial shaders, all inside a
/// [RepaintBoundary] — so a rebuild of the form does not repaint it, and a
/// repaint of it does not touch the form.
///
/// **It answers to the motion setting.** The rings are looping ambience, so
/// they stop where the skeleton shimmer and the lock-window halo stop —
/// `MotionSpec.ambientLoops`, which folds in `MediaQuery.disableAnimations`.
/// With ambience off there is **no controller at all**: the painter draws one
/// fixed, mid-expansion frame, so the screen keeps its composition and loses
/// only its movement. Login may also pause an allowed controller while a form
/// field is active; that preserves the current pulse frame and avoids making
/// the glass panel re-filter a moving backdrop during keyboard work.
class EntryPulse extends StatefulWidget {
  const EntryPulse({
    super.key,
    required this.glass,
    this.center = const Alignment(0, -0.06),
    this.paused = false,
  });

  final EntryGlass glass;
  final Alignment center;
  final bool paused;

  /// One full breath. Deliberately long: at this length the eye reads the
  /// change as ambience rather than as an animation demanding attention.
  static const Duration period = Duration(milliseconds: 5200);

  /// The frame drawn when ambience is off — one ring mid-flight and the core
  /// near its brightest, which is the composition at its most legible.
  static const double stillPhase = 0.42;

  @override
  State<EntryPulse> createState() => _EntryPulseState();
}

class _EntryPulseState extends State<EntryPulse>
    // `TickerProviderStateMixin`, not the single-ticker one: the quality
    // level is a live setting, so this widget can genuinely be asked to give
    // its controller up and later create another — and a single-ticker state
    // throws the second time round.
    with
        TickerProviderStateMixin {
  AnimationController? _loop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncToMotionLevel();
  }

  @override
  void didUpdateWidget(EntryPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paused != widget.paused) _syncToMotionLevel();
  }

  void _syncToMotionLevel() {
    final allowed = motionSpec(context).ambientLoops;
    if (!allowed) {
      _loop?.dispose();
      _loop = null;
      return;
    }

    final loop = _loop ??= AnimationController(
      vsync: this,
      duration: EntryPulse.period,
      value: EntryPulse.stillPhase,
    );
    if (widget.paused) {
      loop.stop(canceled: false);
    } else if (!loop.isAnimating) {
      loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loop = _loop;
    return IgnorePointer(
      child: RepaintBoundary(
        child: loop == null
            ? CustomPaint(
                painter: EntryPulsePainter(
                  glass: widget.glass,
                  center: widget.center,
                  phase: EntryPulse.stillPhase,
                ),
              )
            : AnimatedBuilder(
                animation: loop,
                builder: (context, _) => CustomPaint(
                  painter: EntryPulsePainter(
                    glass: widget.glass,
                    center: widget.center,
                    phase: loop.value,
                  ),
                ),
              ),
      ),
    );
  }
}

/// Draws one frame of the pulse. Public so the intro can compose it with its
/// own entrance opacity without duplicating the geometry.
class EntryPulsePainter extends CustomPainter {
  const EntryPulsePainter({
    required this.glass,
    required this.center,
    required this.phase,
    this.opacity = 1,
  });

  final EntryGlass glass;
  final Alignment center;

  /// 0 → 1 across one [EntryPulse.period].
  final double phase;

  /// Scales the whole pulse. The intro fades it in with the mark.
  final double opacity;

  /// How wide the soft band of a ring is, as a fraction of its own radius.
  static const double _band = 0.36;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || opacity <= 0) return;
    final origin = center.alongSize(size);
    final reach = size.longestSide * 0.66;
    final peak = glass.pulsePeak * opacity;

    // The breathing core: brightest at mid-cycle, never fully gone.
    final breath = 0.5 - 0.5 * math.cos(2 * math.pi * phase);
    _blob(
      canvas,
      origin,
      reach * (0.40 + 0.09 * breath),
      peak * (0.50 + 0.50 * breath),
    );

    // Two rings, half a cycle apart, so one is always on its way out as the
    // next leaves — which is what makes the rhythm read as continuous rather
    // than as something starting over.
    for (final offset in const [0.0, 0.5]) {
      final t = (phase + offset) % 1.0;
      // In quickly, out slowly: a wave that appeared as slowly as it fades
      // would read as a fade, not as a pulse.
      final envelope = math.min(1.0, t / 0.14) * math.pow(1 - t, 1.7);
      if (envelope <= 0.001) continue;
      _ring(
        canvas,
        origin,
        reach * (0.26 + 0.78 * t),
        peak * envelope.toDouble() * 0.9,
      );
    }
  }

  void _blob(Canvas canvas, Offset origin, double radius, double alpha) {
    if (radius <= 0 || alpha <= 0.002) return;
    final tint = glass.pulse;
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            tint.withValues(alpha: alpha),
            tint.withValues(alpha: alpha * 0.34),
            tint.withValues(alpha: 0),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: origin, radius: radius)),
    );
  }

  void _ring(Canvas canvas, Offset origin, double radius, double alpha) {
    if (radius <= 0 || alpha <= 0.002) return;
    final tint = glass.pulse;
    // A radial gradient whose stops peak just inside the edge: a soft annulus
    // with no hard rim anywhere, which a stroked circle cannot give.
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            tint.withValues(alpha: 0),
            tint.withValues(alpha: 0),
            tint.withValues(alpha: alpha),
            tint.withValues(alpha: 0),
          ],
          stops: const [0, 1 - _band, 1 - _band * 0.42, 1],
        ).createShader(Rect.fromCircle(center: origin, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(EntryPulsePainter old) =>
      old.phase != phase ||
      old.opacity != opacity ||
      old.center != center ||
      old.glass.pulse != glass.pulse ||
      old.glass.pulsePeak != glass.pulsePeak;
}

/// The one frosted surface on the entry surface.
///
/// Heading, fields, CTA, divider and Google all live inside it, because depth
/// that comes from one surface reads as an object and depth that comes from
/// six reads as noise.
///
/// **Blur is budgeted, not assumed.** The sigma comes from the user's own
/// quality setting (`MotionSpec.blurSigma`), capped at the point where more
/// blur stops being visible. At the cheapest level there is no
/// `BackdropFilter` at all and the fill steps up to stay opaque enough to
/// read on — the screen loses an effect, never its legibility.
class EntryGlassPanel extends StatelessWidget {
  const EntryGlassPanel({
    super.key,
    required this.glass,
    required this.padding,
    required this.child,
  });

  /// CSS `blur(30px)` is roughly this much Gaussian sigma; past it the frost
  /// stops changing and only the GPU notices.
  static const double maxSigma = 15;

  final EntryGlass glass;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final sigma = math.min(motionSpec(context).blurSigma, maxSigma);
    final radius = BorderRadius.circular(30);
    // With no blur behind it the fill has to do the whole job, so it is
    // pulled toward opaque rather than left transparent over a gradient.
    final opaqueFallback = sigma <= 0;
    Color fill(Color c) => opaqueFallback
        ? Color.alphaBlend(c, glass.baseMid).withValues(alpha: 0.97)
        : c;

    final surface = Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: const Alignment(-0.6, -1),
          end: const Alignment(0.6, 1),
          stops: const [0, 0.52, 1],
          colors: [
            fill(glass.glassTop),
            fill(glass.glassMid),
            fill(glass.glassBottom),
          ],
        ),
        border: Border.all(color: glass.glassBorder),
      ),
      child: Stack(
        children: [
          Padding(padding: padding, child: child),
          // A 1px light across the top edge — the highlight a real pane of
          // glass catches from the horizon above it. Inset at both ends so it
          // fades rather than butting into the corners.
          PositionedDirectional(
            top: 0,
            start: 0,
            end: 0,
            child: IgnorePointer(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 30),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      glass.sheen.withValues(alpha: 0),
                      glass.sheen,
                      glass.sheen.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: glass.panelShadow,
              blurRadius: 52,
              spreadRadius: -26,
              offset: const Offset(0, 22),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: sigma <= 0
              ? surface
              : BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: surface,
                ),
        ),
      ),
    );
  }
}
