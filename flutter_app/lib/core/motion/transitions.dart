import 'package:flutter/material.dart';

import 'motion_tokens.dart';

/// Shared-axis (Y) transition — used for every top-level route change.
/// Mirror-safe: the geometry is horizontal only, no directional glyphs.
///
/// Complexity scales with the motion level. At the cheap levels this is a
/// plain cross-fade; the slide layers are only built from `balanced` up, so
/// a weak device pays for two widgets instead of four.
class SharedAxisPageTransition extends StatelessWidget {
  const SharedAxisPageTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  /// Travel as a fraction of the page width, at full intensity.
  static const double _slide = 0.06;

  @override
  Widget build(BuildContext context) {
    final spec = motionSpec(context);
    if (spec.isInstant) return child;

    final incoming = CurvedAnimation(
      parent: animation,
      curve: MotionTokens.emphasized,
      reverseCurve: MotionTokens.exit,
    );
    final outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: MotionTokens.exit,
      reverseCurve: MotionTokens.emphasized,
    );

    Widget result = FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(incoming),
      child: FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0).animate(outgoing),
        child: child,
      ),
    );

    // The slide is the expensive half — two more transform layers on every
    // route change. Below `balanced` the cross-fade alone carries it.
    if (spec.slideRoutes) {
      final travel = _slide * spec.intensity;
      result = SlideTransition(
        position: Tween<Offset>(
          begin: Offset(travel, 0),
          end: Offset.zero,
        ).animate(incoming),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset.zero,
            end: Offset(-travel, 0),
          ).animate(outgoing),
          child: result,
        ),
      );
    }

    return result;
  }
}

/// Directional transition for switching between the tabs of a detail shell
/// or between bottom-nav branches.
///
/// It replaces a plain cross-fade, which said *that* the body changed but
/// never *which way* — the missing spatial cue is what made a swipe feel
/// disconnected from the tab it landed on.
///
/// ## Direction
///
/// The tabs are a filmstrip in visual order and the body travels **with the
/// user's finger**, exactly as a pager does. A swipe to the left drags the
/// strip left, which is why it lands on the tab physically to the *right*
/// (see `SwipeTabs`); the incoming body therefore enters from the right
/// edge and travels left, following the finger the whole way.
///
/// Which side of the strip a tab sits on depends on the ambient
/// [Directionality], because the tab bar lays its tabs out from the start
/// edge: a higher index sits further **left** in RTL and further **right**
/// in LTR. Nothing here assumes "next" means "right".
///
/// Taps on the tab bar animate identically — direction comes from the index
/// delta, not from the gesture — so the two ways of moving agree: choosing a
/// tab that sits to the right always pulls it in from the right.
///
/// ## Cost
///
/// Only the incoming body is animated, and only with a transform and an
/// opacity. The outgoing body is dropped on the frame it leaves unless the
/// level asks for the cross-fade, because keeping it means building a whole
/// second tab subtree for the length of the transition.
class TabSwitchTransition extends StatefulWidget {
  const TabSwitchTransition({
    super.key,
    required this.index,
    required this.child,
  });

  /// The currently selected tab. A change to this drives the animation and
  /// its sign; the widget never reads the gesture itself.
  final int index;

  final Widget child;

  @override
  State<TabSwitchTransition> createState() => _TabSwitchTransitionState();
}

class _TabSwitchTransitionState extends State<TabSwitchTransition>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  AnimationController get _controller => _ctrl ??= AnimationController(
        vsync: this,
        duration: MotionTokens.short,
      )..addStatusListener(_onStatus);

  void _onStatus(AnimationStatus status) {
    // Drop the transform/opacity layers — and the outgoing subtree — the
    // moment they stop earning their place.
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _outgoing = null);
    }
  }

  /// Where the incoming body starts, as a sign on the x axis. `+1` is the
  /// right edge.
  double _enterSign = 0;

  /// Held only when the level asks for the outgoing cross-fade.
  Widget? _outgoing;

  @override
  void didUpdateWidget(covariant TabSwitchTransition old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;

    final spec = motionSpec(context);
    if (spec.isInstant) {
      _outgoing = null;
      // Do not create an animation controller for an experience that never
      // animates. If one exists because the motion level changed at runtime,
      // finish it immediately.
      _ctrl
        ?..stop()
        ..value = 1;
      return;
    }

    final rtl = Directionality.of(context) == TextDirection.rtl;
    final delta = widget.index - old.index;
    // A higher index sits further left in RTL, further right in LTR.
    final destinationIsRight = rtl ? delta < 0 : delta > 0;
    // The strip slides toward the destination's own side, so a tab that
    // sits to the right is pulled in from the right while the body travels
    // left — the direction the finger that asked for it went.
    _enterSign = destinationIsRight ? 1.0 : -1.0;

    _outgoing = spec.crossFadeOutgoing ? old.child : null;
    _controller
      ..duration = effectiveDuration(context, MotionTokens.short)
      ..forward(from: 0);
  }

  @override
  void dispose() {
    // The lowest-performance/reduced-motion path may never have needed a
    // controller. Reading a `late` controller here used to create one while
    // the element was already deactivated, which is not a safe time to look
    // up TickerMode.
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spec = motionSpec(context);
    // Steady state: no transform layer, no opacity layer, no cost.
    if (spec.isInstant) return widget.child;
    final controller = _controller;
    if (!controller.isAnimating) return widget.child;

    final travel = MotionTokens.tabSwitchTravel * spec.intensity;
    final outgoing = _outgoing;

    return AnimatedBuilder(
      animation: controller,
      child: widget.child,
      builder: (context, child) {
        final t = MotionTokens.enter.transform(controller.value);
        final incoming = Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(_enterSign * (1 - t) * travel, 0),
            child: child,
          ),
        );
        if (outgoing == null) return incoming;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            IgnorePointer(
              child: Opacity(
                opacity: 1 - t,
                // Exits the way the incoming body arrived from: both move
                // in the direction of the finger.
                child: Transform.translate(
                  offset: Offset(-_enterSign * t * travel, 0),
                  child: outgoing,
                ),
              ),
            ),
            incoming,
          ],
        );
      },
    );
  }
}
