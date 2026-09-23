import 'package:flutter/material.dart';

import '../motion/animated_counter.dart';
import '../motion/motion_tokens.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// The signature "lock window" chip that appears on shifts and check-in.
enum LockWindowState { open, restricted, sealed }

class LockWindow extends StatefulWidget {
  const LockWindow({
    super.key,
    required this.state,
    this.remaining,
  });

  final LockWindowState state;

  /// Only used when [state] == open. Format: "mm:ss".
  final Duration? remaining;

  @override
  State<LockWindow> createState() => _LockWindowState();
}

class _LockWindowState extends State<LockWindow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _halo;

  @override
  void initState() {
    super.initState();
    _halo = AnimationController(
      vsync: this,
      duration: MotionTokens.haloPulse,
    );
  }

  @override
  void didUpdateWidget(covariant LockWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncHalo();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncHalo();
  }

  void _syncHalo() {
    // The halo is a looping blurred shadow — the most expensive ambience
    // in the app per frame — so it follows the level's ambience switch
    // rather than the instant/animated one.
    final urgent = widget.state == LockWindowState.open &&
        (widget.remaining?.inSeconds ?? 999) < 60 &&
        motionSpec(context).ambientLoops;
    if (urgent && !_halo.isAnimating) {
      _halo.repeat(reverse: true);
    } else if (!urgent && _halo.isAnimating) {
      _halo.stop();
      _halo.value = 0;
    }
  }

  @override
  void dispose() {
    _halo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final (bg, fg, icon, caption, value) = switch (widget.state) {
      LockWindowState.open => (
          c.okTint,
          c.ok,
          Icons.lock_open_rounded,
          'قابل للتعديل',
          _fmt(widget.remaining ?? Duration.zero),
        ),
      LockWindowState.restricted => (
          c.warnTint,
          c.warn,
          Icons.vpn_key_rounded,
          'مقيّد',
          'تعديل بصلاحية',
        ),
      LockWindowState.sealed => (
          c.mutedTint,
          c.ink2,
          Icons.lock_rounded,
          'مُثبَّت',
          'أضف تصحيحا',
        ),
    };

    final valueStyle = AppTypography.digits(fg, size: 15, letterSpacing: 0.5);

    return AnimatedBuilder(
      animation: _halo,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: fg),
          borderRadius: BorderRadius.circular(AppRadii.md),
          boxShadow: _halo.value == 0
              ? null
              : [
                  BoxShadow(
                    color: fg.withValues(alpha: _halo.value * 0.45),
                    blurRadius: 20,
                    spreadRadius: 3,
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 8),
            // Loose, so an unbounded parent still gets the natural width;
            // a narrow one wraps the caption instead of overflowing.
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    caption,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
                  ),
                  // The countdown redraws every second, so its digits go
                  // through fixed-width cells — otherwise the chip breathes
                  // as the numbers change. The other two states are words,
                  // which must stay one shaped run.
                  if (widget.state == LockWindowState.open)
                    TabularDigits(value, style: valueStyle)
                  else
                    Text(value, style: valueStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(999).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return toArabicIndic('$mm:$ss');
  }
}
