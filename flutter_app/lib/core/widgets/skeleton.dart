import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

/// One shimmer clock shared by every [Skeleton] beneath it.
///
/// A loading list is the densest cluster of animation in the app — a
/// five-row [SkeletonList] holds twenty shimmer bars. Twenty controllers
/// ticking the same 1.2s loop is twenty times the scheduler work and
/// twenty rebuild trees per frame, for an effect that is *more* convincing
/// when the bars are in phase anyway. [SkeletonList] provides one clock;
/// a [Skeleton] standing on its own still falls back to its own.
class ShimmerScope extends InheritedWidget {
  const ShimmerScope({super.key, required this.clock, required super.child});

  final Animation<double> clock;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShimmerScope>()?.clock;

  @override
  bool updateShouldNotify(ShimmerScope oldWidget) => clock != oldWidget.clock;
}

/// Shimmer skeleton — pure widget, no external package.
///
/// The shimmer is looping ambience, so it stops entirely at the motion
/// levels that turn ambience off: the bar still renders, it just holds
/// still. A stopped controller costs nothing per frame.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 8,
  });
  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _own = AnimationController(
    vsync: this,
    duration: MotionTokens.shimmerLoop,
  );

  Animation<double>? _shared;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shared = ShimmerScope.maybeOf(context);
    _sync();
  }

  /// Only run the private controller when nobody is driving one for us and
  /// the level still wants ambience.
  void _sync() {
    final wants = _shared == null && motionSpec(context).ambientLoops;
    if (wants && !_own.isAnimating) {
      _own.repeat();
    } else if (!wants && _own.isAnimating) {
      _own
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (!motionSpec(context).ambientLoops) return _base(c);

    // The shimmer repaints every frame; the boundary keeps that off the
    // list around it.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _shared ?? _own,
        builder: (context, _) {
          final t = (_shared ?? _own).value;
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(-1 + t * 2, 0),
                end: Alignment(1 + t * 2, 0),
                colors: [c.surface2, c.surface3, c.surface2],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _base(AppColors c) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
}

/// Convenience: a card-shaped skeleton row matching a list item.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: const Row(children: [
        Skeleton(width: 40, height: 40, radius: 20),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton(width: 160, height: 14),
              SizedBox(height: 8),
              Skeleton(width: 100, height: 12),
            ],
          ),
        ),
        Skeleton(width: 48, height: 20, radius: 10),
      ]),
    );
  }
}

class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.count = 5});
  final int count;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: MotionTokens.shimmerLoop,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wants = motionSpec(context).ambientLoops;
    if (wants && !_clock.isAnimating) {
      _clock.repeat();
    } else if (!wants && _clock.isAnimating) {
      _clock
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShimmerScope(
        clock: _clock,
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.lg),
          itemCount: widget.count,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (_, __) => const SkeletonRow(),
        ),
      );
}
