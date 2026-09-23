import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/brand/brand_mark.dart';
import '../../../core/motion/motion_tokens.dart';
import '../../../core/startup/intro_gate.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../l10n/strings.dart';
import 'entry_glass.dart';

/// The Leader launch experience — what a cold start of the app looks like.
///
/// ## The idea
///
/// Leader coordinates volunteer emergency teams, and the one thing a team
/// wants to know about the system it is about to open is that it is **live**.
/// So the intro is a pulse: the mark arrives, a wave leaves it, the name
/// settles under it, and the wave keeps going out into the ground the sign-in
/// form is painted on. It is the product's own [EntryPulse] — the same
/// ambience Login runs — started early and made briefly brighter, which is
/// why the handoff between the two screens reads as one continuous surface
/// rather than as two screens with a cut between them.
///
/// Not a spinner, not a progress bar, not an ECG line. A spinner says *wait*,
/// which is the opposite of what a 2.5-second launch should say, and a
/// heartbeat trace is the cliché every medical product reaches for.
///
/// ## The sequence
///
/// At full motion, from the first frame:
///
/// | from   | to     | what                                            |
/// |--------|--------|-------------------------------------------------|
/// | 0 ms    | 750 ms  | the mark fades up and settles from 0.86 scale |
/// | 0 ms    | 2500 ms | the pulse runs behind the composition         |
/// | 825 ms  | 1375 ms | «ليدر» fades up and rises 10 dp               |
/// | 2500 ms | —       | the gate opens; the router moves when it can  |
///
/// Full-motion levels keep [minimumHold] intact so the finished composition
/// gets a visible breath. Low uses its existing shortened duration, and the
/// duration is **zero** when motion is off — a reduce-motion launch gets the
/// composed end state and no hold at all.
///
/// ## What it does about boot
///
/// It never fakes a delay and it never blocks on one. The gate it releases
/// only ever produces `restoring`, which is the screen the app was already
/// going to show; the router leaves the moment the session classifier can
/// answer. Two cases, both designed:
///
/// * **boot finishes first** — the common one. The sequence plays out and the
///   app moves on the frame after it ends.
/// * **boot is still working** — the sequence ends, the gate opens, and the
///   classifier still says `restoring`, so this screen stays up. After
///   [_captionDelay] more it says so in words, with the same live-region
///   sentence the old startup surface used. A launch that is quick never
///   shows that line at all, which is the point of the delay.
class LeaderIntro extends ConsumerStatefulWidget {
  const LeaderIntro({super.key});

  /// How long the entrance runs, at full motion. Long enough for the mark, a
  /// wave and the wordmark to each get their own moment; short enough that a
  /// person opening the app twice in a minute does not resent it.
  static const Duration minimumHold = Duration(milliseconds: 2500);

  /// How long after the entrance ends before the app admits it is still
  /// working. Only ever seen on a slow boot.
  static const Duration _captionDelay = Duration(milliseconds: 600);

  @override
  ConsumerState<LeaderIntro> createState() => _LeaderIntroState();
}

class _LeaderIntroState extends ConsumerState<LeaderIntro>
    with SingleTickerProviderStateMixin {
  AnimationController? _entrance;
  Timer? _caption;
  bool _showCaption = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Read, not watched: whether this launch plays an entrance is decided
    // once, on the frame the screen appears. The gate moving to `done`
    // underneath it must not restart or cancel anything.
    final holding = ref.read(introGateProvider) == IntroPhase.holding;
    final duration = _introDuration(context);

    if (!holding || duration == Duration.zero) {
      // Either this is not a cold launch, or motion is off. Both mean: draw
      // the finished composition, release anything still held, and let the
      // router move whenever it is ready. Post-frame, because this runs
      // inside a build and writing provider state there is not allowed.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _release();
        _revealCaption();
      });
      return;
    }

    _entrance = AnimationController(vsync: this, duration: duration)
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        // A ticker callback, outside the build phase, so this one may write
        // straight through.
        _release();
        _caption?.cancel();
        _caption = Timer(LeaderIntro._captionDelay, _revealCaption);
      })
      ..forward();
  }

  /// Full-motion profiles all get the complete 2.5-second brand sequence.
  /// The lower profiles still do exactly what their existing definitions
  /// promise: Low shortens it and removes ambience; Performance and the OS
  /// reduced-motion path collapse it to zero.
  static Duration _introDuration(BuildContext context) {
    final scaled = effectiveDuration(context, LeaderIntro.minimumHold);
    if (scaled == Duration.zero || !motionSpec(context).ambientLoops) {
      return scaled;
    }
    return LeaderIntro.minimumHold;
  }

  void _release() {
    if (!mounted) return;
    ref.read(introGateProvider.notifier).finish();
  }

  void _revealCaption() {
    if (!mounted || _showCaption) return;
    setState(() => _showCaption = true);
  }

  @override
  void dispose() {
    _caption?.cancel();
    _entrance?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = ref.watch(themeStateProvider);
    final brightness = switch (theme.mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => media.platformBrightness,
    };
    final glass = EntryGlass.resolve(brightness, eyeProtect: theme.eyeProtect);
    final entrance = _entrance;

    return Scaffold(
      backgroundColor: glass.baseMid,
      body: EntryBackdrop(
        glass: glass,
        // The wave leaves the mark, which sits above centre.
        pulseCenter: const Alignment(0, -0.16),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: entrance == null
                  ? _content(glass, 1, 1, 1)
                  : AnimatedBuilder(
                      animation: entrance,
                      builder: (context, _) {
                        final t = entrance.value;
                        return _content(
                          glass,
                          // The mark: in over the first 30% of the sequence.
                          _stage(t, 0, 0.30, MotionTokens.enter),
                          // Settling scale, on the emphasised curve so it
                          // arrives rather than springs.
                          _stage(t, 0, 0.32, MotionTokens.emphasized),
                          // The wordmark, once the mark has landed.
                          _stage(t, 0.33, 0.55, MotionTokens.enter),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// One sub-stage of the sequence: `0` before it starts, `1` after it ends,
  /// and [curve] applied in between.
  static double _stage(double t, double start, double end, Curve curve) {
    if (t <= start) return 0;
    if (t >= end) return 1;
    return curve.transform((t - start) / (end - start));
  }

  Widget _content(
    EntryGlass glass,
    double markIn,
    double markSettle,
    double wordIn,
  ) {
    // The mark is at 0.86 on arrival and 1.0 when it lands: a controlled
    // settle, not a pop. Anything bouncier on a brand mark reads as a game.
    final scale = 0.86 + 0.14 * markSettle;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: markIn,
          child: Transform.scale(
            scale: scale,
            child: BrandMark(
              size: 108,
              glow: glass.markGlow.withValues(
                alpha: glass.markGlow.a * markIn,
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Opacity(
          opacity: wordIn,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - wordIn)),
            child: Text(
              S.productNameAr,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: glass.fg,
                fontSize: 30,
                height: 1.25,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ),
        // Reserved whatever the caption is doing, so revealing it cannot move
        // the mark that is already on screen.
        SizedBox(
          height: 64,
          child: AnimatedOpacity(
            opacity: _showCaption ? 1 : 0,
            duration: effectiveDuration(context, MotionTokens.medium),
            curve: effectiveCurve(context, MotionTokens.standard),
            child: Padding(
              padding: const EdgeInsets.only(top: 26),
              child: Semantics(
                liveRegion: _showCaption,
                child: Text(
                  S.startupRestoring,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: glass.faint,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
