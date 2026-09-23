import 'package:flutter/material.dart';

/// Resolves a *physical* swipe into the index of the tab it should land on.
///
/// This is the one place the app decides what a swipe means, and it decides
/// it from the layout rather than from tab order.
///
/// ## The rule
///
/// The tabs behave like a filmstrip laid out in visual order. Dragging left
/// pulls the strip left, which brings in whatever sat to the **right**;
/// dragging right brings in whatever sat to the **left**. It is the same
/// contract a pager has, and the body animation in `TabSwitchTransition`
/// moves with the finger to match it:
///
///     swipe LEFT   ->  the tab physically on the RIGHT
///     swipe RIGHT  ->  the tab physically on the LEFT
///
/// ## Which index that is
///
/// Tab bars lay their tabs out from the start edge, so a higher index sits
/// further **left** in RTL and further **right** in LTR:
///
///     LTR   [ 0 ][ 1 ][ 2 ][ 3 ]      index grows rightward
///     RTL   [ 3 ][ 2 ][ 1 ][ 0 ]      index grows leftward
///
/// So from الشفتات (index 1) in the RTL detachment row
/// `الفريق | الشفتات | المخزن | الإحصائيات`, a swipe left lands on الفريق
/// (index 0, the tab to its right) and a swipe right lands on المخزن
/// (index 2, the tab to its left). In LTR the same rule reads as the
/// familiar "swipe left for the next tab".
///
/// Returns `null` when the swipe would run off either end.
int? adjacentTabIndex({
  required int currentIndex,
  required int tabCount,
  required bool towardLeft,
  required TextDirection direction,
}) {
  final rtl = direction == TextDirection.rtl;
  // One step toward the right of the screen, in index terms.
  final rightStep = rtl ? -1 : 1;
  // A leftward swipe reaches for the tab on the right, and vice versa.
  final next = currentIndex + (towardLeft ? rightStep : -rightStep);
  if (next < 0 || next > tabCount - 1 || next == currentIndex) return null;
  return next;
}

/// A second way to move between adjacent surfaces — a horizontal swipe,
/// alongside the tab buttons and the bottom nav, which stay exactly as they
/// were.
///
/// It does **not** turn the shell into a `PageView` — that would fight the
/// `ShellRoute`, break per-tab deep links, and force every tab to build at
/// once. It is a gesture layer over the existing router: on a swipe that
/// clears the thresholds it calls [onSwitch] with the adjacent index and
/// the shell's normal `context.go` does the rest.
///
/// ## Not stealing other people's gestures
///
/// The detector sits at the top of the subtree with
/// [HitTestBehavior.translucent], so taps and vertical scrolling pass
/// straight through. Anything *inside* it that also wants horizontal drags
/// — a horizontally scrolling day strip, a slider, a chart, a carousel,
/// a `Dismissible` row — wins the gesture arena, because hit testing walks
/// innermost-first and the innermost recognizer in contention is the one
/// that takes the pointer. So this never has to enumerate what it must
/// avoid; being the outermost claimant is what makes it yield.
///
/// ## Thresholds
///
/// Either a flick or a deliberate drag switches, and neither a small
/// accidental slip nor a mostly-vertical drag does:
///
/// - a flick: speed past [_minFlingVelocity], in any distance; or
/// - a drag: past [_minDragFraction] of the width (and at least
///   [_minDragDistance]), at any speed.
class SwipeTabs extends StatefulWidget {
  const SwipeTabs({
    super.key,
    required this.currentIndex,
    required this.tabCount,
    required this.onSwitch,
    required this.child,
    this.enabled = true,
  });

  final int currentIndex;
  final int tabCount;
  final ValueChanged<int> onSwitch;
  final Widget child;

  /// Lets a host switch the gesture off without restructuring its tree —
  /// used by the bottom-nav shell, which only swipes between branches while
  /// a branch is showing its root page.
  final bool enabled;

  /// A flick. Fast enough that distance stops mattering.
  static const double _minFlingVelocity = 260;

  /// A deliberate drag, as a fraction of the available width.
  static const double _minDragFraction = 0.28;

  /// …and never less than this, so the gesture does not get trivially easy
  /// on a narrow screen.
  static const double _minDragDistance = 64;

  @override
  State<SwipeTabs> createState() => _SwipeTabsState();
}

class _SwipeTabsState extends State<SwipeTabs> {
  double _dx = 0;

  void _onStart(DragStartDetails _) => _dx = 0;

  void _onUpdate(DragUpdateDetails d) => _dx += d.primaryDelta ?? 0;

  void _onEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    final width = context.size?.width ?? 0;
    final threshold = width == 0
        ? SwipeTabs._minDragDistance
        : (width * SwipeTabs._minDragFraction)
            .clamp(SwipeTabs._minDragDistance, double.infinity);

    // A flick decides on speed; a slow drag has to have covered ground.
    // Taking the direction from whichever test passed keeps a drag that
    // reverses at the last moment from switching the wrong way.
    final bool towardLeft;
    if (velocity.abs() >= SwipeTabs._minFlingVelocity) {
      towardLeft = velocity < 0;
    } else if (_dx.abs() >= threshold) {
      towardLeft = _dx < 0;
    } else {
      return;
    }

    final next = adjacentTabIndex(
      currentIndex: widget.currentIndex,
      tabCount: widget.tabCount,
      towardLeft: towardLeft,
      direction: Directionality.of(context),
    );
    if (next != null) widget.onSwitch(next);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.tabCount <= 1) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onStart,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      child: widget.child,
    );
  }
}
