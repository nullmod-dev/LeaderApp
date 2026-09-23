import 'package:flutter/widgets.dart';

/// User-selectable graphics / animation quality. Persisted via
/// SettingsRepository, and paired in Settings with a separate frame-rate
/// control: **this** enum decides how much work a frame does, the frame-rate
/// preference decides how often frames are asked for. Nothing in this file
/// touches the display refresh rate.
///
/// Five steps, from cheapest to richest. Each step removes or restores a
/// *different kind* of work, so the levels are not one duration slider with
/// five stops:
///
/// - [performance] : motion off. Durations collapse to zero, so no
///                   animation controller, transform layer or opacity layer
///                   is built at all; no blur, no shadows beyond the single
///                   contact layer, no looping ambience, no stagger, no
///                   value tweens. Maximum responsiveness on a weak device.
/// - [low]         : motion is back but short and flat — no blur, no
///                   ambience, no stagger, no counter/progress tweens, and
///                   routes cross-fade without the slide layers.
/// - [balanced]    : the default. Blur, ambience, stagger, value tweens and
///                   the route slide all return at reduced cost; curves
///                   stay non-overshooting.
/// - [high]        : full durations, full travel, wider blur, deeper
///                   stagger and the spring curves that are the app's
///                   signature.
/// - [maximum]     : the ceiling. Widest travel and blur, plus the
///                   outgoing-body cross-fade on tab switches — the one
///                   effect that costs a second subtree. Still refuses
///                   anything wasteful: no new per-frame filters.
///
/// Every step scales the SAME `MotionTokens` values. There is no second set
/// of durations anywhere in the app.
enum MotionLevel {
  performance,
  low,
  balanced,
  high,
  maximum;

  /// Back-compat aliases for the two-value enum this replaced. `full` was
  /// the richest step and `reduced` the cheapest, so they map onto the ends
  /// of the new scale.
  static const MotionLevel full = MotionLevel.high;
  static const MotionLevel reduced = MotionLevel.performance;

  /// Tolerates the old persisted names so a stored preference survives the
  /// upgrade. Anything unrecognised falls to [balanced], the default.
  static MotionLevel fromJson(String s) => switch (s) {
        'performance' || 'reduced' => MotionLevel.performance,
        'low' => MotionLevel.low,
        'high' || 'full' => MotionLevel.high,
        'maximum' => MotionLevel.maximum,
        _ => MotionLevel.balanced,
      };

  String toJson() => name;

  /// The cost/feel profile this level resolves to.
  MotionSpec get spec => switch (this) {
        MotionLevel.performance => MotionSpec.performance,
        MotionLevel.low => MotionSpec.low,
        MotionLevel.balanced => MotionSpec.balanced,
        MotionLevel.high => MotionSpec.high,
        MotionLevel.maximum => MotionSpec.maximum,
      };
}

/// What a [MotionLevel] actually costs, expressed as the handful of dials
/// every animated widget in the app reads.
///
/// Widgets must not switch on [MotionLevel] directly — they ask for the dial
/// they need. Adding a level then means adding one row here, not auditing
/// every call site.
@immutable
class MotionSpec {
  const MotionSpec({
    required this.durationScale,
    required this.intensity,
    required this.blurSigma,
    required this.ambientLoops,
    required this.staggerMaxItems,
    required this.overshoot,
    required this.richShadows,
    required this.crossFadeOutgoing,
    required this.animatedValues,
    required this.slideRoutes,
  });

  /// Multiplier applied to every `MotionTokens` duration. `0` means motion
  /// is off entirely — both the accessibility case and
  /// [MotionLevel.performance] resolve to it.
  final double durationScale;

  /// Multiplier on how far things travel — slide offsets, stagger lift.
  /// Distance is the cheapest thing to trim and the first thing that reads
  /// as "heavy" when a screen is busy.
  final double intensity;

  /// `BackdropFilter` blur radius for the floating nav. `0` drops the
  /// filter entirely — it is the single heaviest paint in the app on
  /// low-end Android.
  final double blurSigma;

  /// Looping ambience: the skeleton shimmer and the lock-window halo.
  /// These run a controller for as long as they are on screen, so they are
  /// the first thing to stop on a weak device.
  final bool ambientLoops;

  /// How many leading list rows get the staggered entry. `0` switches it
  /// off: N simultaneous opacity+transform layers is real work on a weak
  /// device, and a list that appears at once is a perfectly good list.
  /// Never above [MotionTokens.staggerMaxItems], which is the budget that
  /// keeps the whole cascade under 300ms.
  final int staggerMaxItems;

  /// Whether the spring curves (which overshoot) are used. Overshoot costs
  /// nothing extra to compute but reads as "bouncy", which is the wrong
  /// note on a device that is already struggling.
  final bool overshoot;

  /// The two-layer drop shadow under the nav pill. One layer at the cheap
  /// levels.
  final bool richShadows;

  /// Whether a tab switch keeps the outgoing body mounted to cross-fade it.
  /// Off everywhere except [MotionLevel.maximum]: holding it means building
  /// a second full tab subtree for the length of the transition.
  final bool crossFadeOutgoing;

  /// Whether numbers and progress bars ease to their new value instead of
  /// snapping. A tween re-lays-out text (or repaints a bar) on every frame
  /// it runs, often several at once on a dashboard, so the cheap levels
  /// show the final figure immediately — which is also the figure the user
  /// came to read.
  final bool animatedValues;

  /// Whether a route change adds its two slide layers on top of the
  /// cross-fade. The fade alone still says *that* the page changed; the
  /// slide is what says which way, and it is the expensive half.
  final bool slideRoutes;

  /// Staggered list entry runs at all.
  bool get stagger => staggerMaxItems > 0;

  /// Motion off. What `MediaQuery.disableAnimations` resolves to — and
  /// what [MotionLevel.performance] deliberately resolves to as well, since
  /// "off" is exactly what that level promises.
  static const MotionSpec none = MotionSpec(
    durationScale: 0,
    intensity: 0,
    blurSigma: 0,
    ambientLoops: false,
    staggerMaxItems: 0,
    overshoot: false,
    richShadows: false,
    crossFadeOutgoing: false,
    animatedValues: false,
    slideRoutes: false,
  );

  /// Animations effectively disabled: nothing tweens, nothing loops,
  /// nothing blurs, and the shadow stack drops to its single contact
  /// layer. The screen still changes — it just changes on the frame the
  /// user asked for it.
  static const MotionSpec performance = none;

  static const MotionSpec low = MotionSpec(
    durationScale: 0.60,
    intensity: 0.50,
    blurSigma: 0,
    ambientLoops: false,
    staggerMaxItems: 0,
    overshoot: false,
    richShadows: false,
    crossFadeOutgoing: false,
    animatedValues: false,
    slideRoutes: false,
  );

  static const MotionSpec balanced = MotionSpec(
    durationScale: 0.85,
    intensity: 0.80,
    blurSigma: 10,
    ambientLoops: true,
    staggerMaxItems: 6,
    overshoot: false,
    richShadows: true,
    crossFadeOutgoing: false,
    animatedValues: true,
    slideRoutes: true,
  );

  static const MotionSpec high = MotionSpec(
    durationScale: 1.0,
    intensity: 1.0,
    blurSigma: 18,
    ambientLoops: true,
    staggerMaxItems: 8,
    overshoot: true,
    richShadows: true,
    crossFadeOutgoing: false,
    animatedValues: true,
    slideRoutes: true,
  );

  static const MotionSpec maximum = MotionSpec(
    durationScale: 1.0,
    intensity: 1.15,
    blurSigma: 24,
    ambientLoops: true,
    staggerMaxItems: 8,
    overshoot: true,
    richShadows: true,
    crossFadeOutgoing: true,
    animatedValues: true,
    slideRoutes: true,
  );

  /// True when motion is off outright and widgets should render their end
  /// state on the first frame.
  bool get isInstant => durationScale == 0;

  /// True when the frosted nav should draw its `BackdropFilter`.
  bool get hasBlur => blurSigma > 0;
}

/// Ambient access — every widget that reads motion tokens can look this up
/// through [MotionScope.of]. Bound at the app root by [MotionScope].
class MotionScope extends InheritedWidget {
  const MotionScope({
    super.key,
    required this.level,
    required super.child,
  });

  final MotionLevel level;

  static MotionLevel of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<MotionScope>();
    return s?.level ?? MotionLevel.balanced;
  }

  @override
  bool updateShouldNotify(MotionScope oldWidget) => level != oldWidget.level;
}
