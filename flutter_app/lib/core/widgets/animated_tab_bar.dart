import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';
import '../motion/press_scale.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

/// Persistent tab bar under the AppBar with an animated indicator.
///
/// **The type is the app's, explicitly.** `AnimatedDefaultTextStyle` does not
/// merge with the inherited style — it *replaces* it — so a bare `TextStyle`
/// here dropped the tab labels off `IBMPlexSansArabic` onto whatever the
/// platform's default family is. Phase 3A's first Statistics render caught
/// it: every tab label on the detachment detail shell drew as a row of
/// placeholder boxes. This is the same defect Phase 2 found in `labelSmall`,
/// in the one other widget that sets a text style without a family, and it is
/// why every style in this app is built from an `AppTypography` token.
class AnimatedTabBar extends StatefulWidget {
  const AnimatedTabBar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onChanged,
  });
  final List<String> tabs;
  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  State<AnimatedTabBar> createState() => _AnimatedTabBarState();
}

class _AnimatedTabBarState extends State<AnimatedTabBar> {
  final _scrollController = ScrollController();
  late List<GlobalKey> _tabKeys = _keysFor(widget.tabs.length);
  double? _lastTextScale;

  static List<GlobalKey> _keysFor(int count) =>
      List<GlobalKey>.generate(count, (_) => GlobalKey());

  @override
  void didUpdateWidget(covariant AnimatedTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabs.length != widget.tabs.length ||
        !_sameTabs(oldWidget.tabs, widget.tabs)) {
      _tabKeys = _keysFor(widget.tabs.length);
    }
    if (oldWidget.currentIndex != widget.currentIndex ||
        !_sameTabs(oldWidget.tabs, widget.tabs)) {
      _revealSelected(animate: true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (_lastTextScale != scale) {
      _lastTextScale = scale;
      _revealSelected(animate: false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  static bool _sameTabs(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _revealSelected({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.currentIndex >= _tabKeys.length) return;
      final tabContext = _tabKeys[widget.currentIndex].currentContext;
      if (tabContext == null) return;
      Scrollable.ensureVisible(
        tabContext,
        alignment: 0.5,
        duration: animate
            ? effectiveDuration(context, MotionTokens.medium)
            : Duration.zero,
        curve: MotionTokens.emphasized,
      );
    });
  }

  List<double> _tabWidths(
    BuildContext context,
    BoxConstraints constraints,
    TextStyle style,
  ) {
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final widths = <double>[
      for (final label in widget.tabs)
        math.max(
          88,
          (TextPainter(
                text: TextSpan(text: label, style: style),
                textDirection: direction,
                textScaler: scaler,
                maxLines: 1,
              )..layout())
                  .width +
              AppSpacing.xl * 2,
        ),
    ];
    if (!constraints.maxWidth.isFinite || widths.isEmpty) return widths;
    final natural = widths.fold<double>(0, (sum, width) => sum + width);
    if (natural >= constraints.maxWidth) return widths;
    final extra = (constraints.maxWidth - natural) / widths.length;
    return [for (final width in widths) width + extra];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final baseStyle = AppTypography.chip(c).copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widths = _tabWidths(context, constraints, baseStyle);
          final contentWidth =
              widths.fold<double>(0, (sum, width) => sum + width);
          final indicatorStart = widths
              .take(widget.currentIndex.clamp(0, widths.length))
              .fold<double>(0, (sum, width) => sum + width);
          final selectedWidth = widths.isEmpty
              ? 0.0
              : widths[widget.currentIndex.clamp(0, widths.length - 1)];
          return SizedBox(
            height: 46,
            child: SingleChildScrollView(
              key: const Key('animated-tab-strip-scroll'),
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                height: 46,
                child: Stack(
                  children: [
                    AnimatedPositionedDirectional(
                      duration: effectiveDuration(context, MotionTokens.medium),
                      curve: MotionTokens.emphasized,
                      start: indicatorStart,
                      width: selectedWidth,
                      bottom: 0,
                      height: 3,
                      child: Center(
                        child: Container(
                          key: const Key('animated-tab-indicator'),
                          width: selectedWidth * 0.55,
                          height: 3,
                          decoration: BoxDecoration(
                            color: c.primary,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(3),
                              topRight: Radius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (int i = 0; i < widget.tabs.length; i++)
                          SizedBox(
                            key: _tabKeys[i],
                            width: widths[i],
                            height: 46,
                            child: Semantics(
                              button: true,
                              selected: widget.currentIndex == i,
                              label: widget.tabs[i],
                              onTap: () => widget.onChanged(i),
                              child: ExcludeSemantics(
                                child: PressScale(
                                  onTap: () => widget.onChanged(i),
                                  child: Center(
                                    child: AnimatedDefaultTextStyle(
                                      duration: effectiveDuration(
                                          context, MotionTokens.short),
                                      curve: MotionTokens.standard,
                                      style: baseStyle.copyWith(
                                        color: widget.currentIndex == i
                                            ? c.primary
                                            : c.ink2,
                                        fontWeight: widget.currentIndex == i
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                      ),
                                      child: Text(
                                        widget.tabs[i],
                                        maxLines: 1,
                                        softWrap: false,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
