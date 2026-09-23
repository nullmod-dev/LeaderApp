import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/motion/transitions.dart';

/// The tabs are a filmstrip in visual order, so the body enters from the
/// destination tab's own side of the screen — and which side that is
/// depends on the ambient `Directionality`, because a higher index sits
/// further left in RTL and further right in LTR.
///
/// A swipe left lands on the tab physically to the right, so the body
/// travels left and the incoming tab enters from the **right** edge. RTL
/// and LTR reach that from opposite index deltas, which is the whole reason
/// this is tested rather than eyeballed.

const _childKey = Key('tab-body');

/// At [MotionLevel.maximum] the outgoing body is kept mounted to cross-fade
/// it, so the key matches twice. The incoming body is the one painted last.
final _incoming = find.byKey(_childKey).last;

Widget _host({
  required TextDirection direction,
  required int index,
  required MotionLevel level,
  bool disableAnimations = false,
}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: direction,
        child: MotionScope(
          level: level,
          child: TabSwitchTransition(
            index: index,
            child: Container(key: _childKey, color: const Color(0xFF000000)),
          ),
        ),
      ),
    );

/// Horizontal offset of the body relative to where it settles.
Future<double> _midTransitionShift(
  WidgetTester tester, {
  required TextDirection direction,
  required int from,
  required int to,
}) async {
  await tester.pumpWidget(_host(
    direction: direction,
    index: from,
    level: MotionLevel.high,
  ));
  await tester.pumpAndSettle();
  final settled = tester.getTopLeft(_incoming).dx;

  await tester.pumpWidget(_host(
    direction: direction,
    index: to,
    level: MotionLevel.high,
  ));
  await tester.pump(const Duration(milliseconds: 40));
  final mid = tester.getTopLeft(_incoming).dx;

  await tester.pumpAndSettle();
  expect(tester.getTopLeft(_incoming).dx, closeTo(settled, 0.01),
      reason: 'the body must land exactly where it started');
  return mid - settled;
}

void main() {
  testWidgets('RTL: moving to a higher index enters from the left',
      (tester) async {
    // RTL index 0 -> 1 lands on the tab physically to the LEFT, which is
    // the swipe-right destination, so the body travels right and the
    // incoming tab enters from the left edge.
    final shift = await _midTransitionShift(
      tester,
      direction: TextDirection.rtl,
      from: 0,
      to: 1,
    );
    expect(shift, lessThan(0));
  });

  testWidgets('RTL: moving to a lower index enters from the right',
      (tester) async {
    final shift = await _midTransitionShift(
      tester,
      direction: TextDirection.rtl,
      from: 2,
      to: 1,
    );
    expect(shift, greaterThan(0));
  });

  testWidgets('LTR mirrors both of those', (tester) async {
    // LTR index 0 -> 1 lands on the tab to the RIGHT — the swipe-left
    // destination — so the body travels left and enters from the right
    // edge, the opposite sign to RTL.
    expect(
      await _midTransitionShift(
        tester,
        direction: TextDirection.ltr,
        from: 0,
        to: 1,
      ),
      greaterThan(0),
    );
    expect(
      await _midTransitionShift(
        tester,
        direction: TextDirection.ltr,
        from: 2,
        to: 1,
      ),
      lessThan(0),
    );
  });

  testWidgets('a cheaper level travels less than a richer one', (tester) async {
    Future<double> shiftAt(MotionLevel level) async {
      await tester.pumpWidget(
          _host(direction: TextDirection.rtl, index: 0, level: level));
      await tester.pumpAndSettle();
      final settled = tester.getTopLeft(_incoming).dx;
      await tester.pumpWidget(
          _host(direction: TextDirection.rtl, index: 1, level: level));
      await tester.pump(const Duration(milliseconds: 1));
      final start = tester.getTopLeft(_incoming).dx;
      await tester.pumpAndSettle();
      return (start - settled).abs();
    }

    final performance = await shiftAt(MotionLevel.performance);
    final low = await shiftAt(MotionLevel.low);
    final balanced = await shiftAt(MotionLevel.balanced);
    final maximum = await shiftAt(MotionLevel.maximum);
    expect(low, lessThan(balanced));
    expect(balanced, lessThan(maximum));
    // `performance` promises animations off, so the body does not travel
    // at all — it is already where it belongs on the first frame.
    expect(performance, 0);
    expect(low, greaterThan(0));
  });

  testWidgets('OS reduce-motion removes the transform entirely',
      (tester) async {
    await tester.pumpWidget(_host(
      direction: TextDirection.rtl,
      index: 0,
      level: MotionLevel.maximum,
      disableAnimations: true,
    ));
    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(_incoming).dx;

    await tester.pumpWidget(_host(
      direction: TextDirection.rtl,
      index: 1,
      level: MotionLevel.maximum,
      disableAnimations: true,
    ));
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.getTopLeft(_incoming).dx, closeTo(settled, 0.01));
    expect(find.byType(Transform), findsNothing);
  });
}
