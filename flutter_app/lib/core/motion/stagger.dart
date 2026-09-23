import 'package:flutter/material.dart';

import 'motion_tokens.dart';

/// Staggered entry for the first N children of a list.
/// - How many rows animate is the level's call (`MotionSpec.staggerMaxItems`),
///   capped by `MotionTokens.staggerMaxItems` so the cascade always fits the
///   sub-300ms budget.
/// - Switched off entirely at the motion levels that ask for it: eight
///   simultaneous opacity layers is real work on a weak device, and a list
///   appearing at once is a perfectly good list.
class Stagger extends StatelessWidget {
  const Stagger({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  /// How far an entering row lifts, at full intensity.
  static const double _lift = 10;

  @override
  Widget build(BuildContext context) {
    final spec = motionSpec(context);
    final depth = spec.staggerMaxItems < MotionTokens.staggerMaxItems
        ? spec.staggerMaxItems
        : MotionTokens.staggerMaxItems;
    if (index >= depth) return child;
    final delayMs = MotionTokens.staggerStep.inMilliseconds * index;
    final lift = _lift * spec.intensity;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: effectiveDuration(
        context,
        MotionTokens.staggerItem + Duration(milliseconds: delayMs),
      ),
      curve: Interval(
        delayMs / (MotionTokens.staggerItem.inMilliseconds + delayMs),
        1.0,
        curve: effectiveSpring(context),
      ),
      builder: (context, v, c) => Opacity(
        opacity: v.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - v) * lift),
          child: c,
        ),
      ),
      child: child,
    );
  }
}
