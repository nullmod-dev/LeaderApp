import 'package:flutter/material.dart';

import 'motion_level.dart';

/// Single source of truth for every duration and curve in the app.
/// Widgets must NOT hardcode `Duration(milliseconds: X)` or curves —
/// they call these constants or the context-aware helpers below.
///
/// These are the *full* values. The user's [MotionLevel] scales them; it
/// never replaces them, so there is exactly one duration scale in the app.
class MotionTokens {
  MotionTokens._();

  // ---------- Durations (the "full" values) ----------
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration micro = Duration(milliseconds: 120);
  static const Duration short = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 280);
  static const Duration long = Duration(milliseconds: 420);
  static const Duration xLong = Duration(milliseconds: 600);

  // Stagger — total across first 8 items must stay <300ms.
  static const Duration staggerStep = Duration(milliseconds: 34);
  static const Duration staggerItem = Duration(milliseconds: 240);
  static const int staggerMaxItems = 8;

  // Curves
  static const Curve emphasized = Cubic(0.2, 0, 0, 1);
  static const Curve standard = Cubic(0.4, 0, 0.2, 1);
  static const Curve spring = Cubic(0.34, 1.28, 0.64, 1);
  static const Curve exit = Cubic(0.4, 0, 1, 1);
  static const Curve enter = Cubic(0, 0, 0.2, 1);

  // Press feedback
  static const double pressScale = 0.97;

  // Bottom nav pill morph
  static const Duration navPillMorph = medium;

  // Named one-offs. They live here rather than in the widget so the
  // motion-level setting has a single place to reach.
  static const Duration progressFill = Duration(milliseconds: 700);

  /// How far a switching tab body travels, at full intensity. Deliberately
  /// a nudge and not a page-width slide: the tab bar already says which tab
  /// won, so the body only has to say which *way*.
  static const double tabSwitchTravel = 24;

  // Looping ambience. These drive controllers that are stopped outright
  // when the level turns ambience off (see Skeleton and LockWindow), so
  // they are the one place a raw duration is still the right value to read.
  static const Duration shimmerLoop = Duration(milliseconds: 1200);
  static const Duration haloPulse = Duration(milliseconds: 1600);
}

/// True when the OS asked to disable/reduce animations.
///
/// Reads the single MediaQuery aspect rather than the whole thing, so a
/// keyboard opening or the device rotating does not rebuild every animated
/// widget in the app.
bool osReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// The resolved motion profile for this subtree.
///
/// **Accessibility wins.** If the platform asks for animations to be off,
/// this returns [MotionSpec.none] whatever quality level the user picked —
/// the setting chooses how rich motion is, never whether an accessibility
/// request is honoured.
MotionSpec motionSpec(BuildContext context) =>
    osReduceMotion(context) ? MotionSpec.none : MotionScope.of(context).spec;

/// True when we should short-circuit animations and render the end state on
/// the first frame. This is the SINGLE place that decides — every widget
/// reads through here rather than scattering `if`s.
bool reduceMotion(BuildContext context) => motionSpec(context).isInstant;

/// Pick a duration honoring the current motion profile. Returns
/// [Duration.zero] when motion is off, so `AnimatedContainer`,
/// `AnimatedOpacity`, etc. snap to the target frame; otherwise scales the
/// token by the level's duration scale.
Duration effectiveDuration(BuildContext context, Duration d) {
  final scale = motionSpec(context).durationScale;
  if (scale == 0) return Duration.zero;
  if (scale == 1) return d;
  return Duration(microseconds: (d.inMicroseconds * scale).round());
}

/// Duration for a value tween — an animated counter, a progress bar
/// filling. Returns [Duration.zero] when the level has value tweens off, so
/// the figure snaps to its target instead of re-laying-out on every frame,
/// and otherwise defers to [effectiveDuration].
Duration effectiveValueDuration(BuildContext context, Duration d) =>
    motionSpec(context).animatedValues
        ? effectiveDuration(context, d)
        : Duration.zero;

/// Same idea for curves: a linear curve when motion is off (there's no
/// distance to travel anyway, so the curve is a no-op, but returning
/// [Curves.linear] avoids the spring overshoot showing as a jitter when
/// duration is very small).
Curve effectiveCurve(BuildContext context, Curve c) =>
    reduceMotion(context) ? Curves.linear : c;

/// A curve that overshoots only where the level allows it. Use this instead
/// of reaching for [MotionTokens.spring] directly: at the cheap levels the
/// bounce reads as sloppiness on a device that is already struggling, and
/// two of the properties the nav pill animates have a hard floor at zero.
Curve effectiveSpring(BuildContext context) {
  final spec = motionSpec(context);
  if (spec.isInstant) return Curves.linear;
  return spec.overshoot ? MotionTokens.spring : MotionTokens.emphasized;
}

/// Scale a travel distance by the level's motion intensity. Trimming
/// distance is the cheapest way to make a busy screen feel lighter without
/// removing the motion that explains it.
double motionTravel(BuildContext context, double distance) =>
    distance * motionSpec(context).intensity;
