import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/widgets/swipe_tabs.dart';

/// The swipe-to-switch gesture layer.
///
/// The contract it has to keep: the tabs are a filmstrip in visual order,
/// so a swipe **left** lands on the tab physically on the **right** and a
/// swipe **right** lands on the tab physically on the **left** — the pager
/// rule, worked out from the current `Directionality` and the visual tab
/// order, never from a fixed "higher index means forward" rule. In RTL the
/// tabs read right-to-left, so a higher index sits further left; in LTR the
/// opposite.
///
/// It also has to stay out of the way: no switch on a small slip, none on a
/// vertical scroll, and none at either end of the row.

Widget _host({
  required TextDirection direction,
  required int index,
  required ValueChanged<int> onSwitch,
  ScrollController? scroll,
  bool enabled = true,
}) {
  return Directionality(
    textDirection: direction,
    child: MediaQuery(
      data: const MediaQueryData(size: Size(400, 800)),
      child: SwipeTabs(
        currentIndex: index,
        tabCount: 4,
        enabled: enabled,
        onSwitch: onSwitch,
        child: ListView.builder(
          controller: scroll,
          itemCount: 40,
          itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
        ),
      ),
    ),
  );
}

/// Drags [dx] logical pixels over enough frames that no fling velocity
/// accumulates — the distance threshold is what decides, not speed.
Future<void> _slowDrag(WidgetTester tester, double dx) async {
  final gesture =
      await tester.startGesture(tester.getCenter(find.byType(ListView)));
  final step = dx / 13;
  for (var i = 0; i < 13; i++) {
    await gesture.moveBy(Offset(step, 0));
    await tester.pump(const Duration(milliseconds: 40));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('a swipe lands on the tab from the opposite side', () {
    testWidgets('RTL: left goes to the tab on the right, right to the left',
        (tester) async {
      // RTL lays الفريق|الشفتات|المخزن|الإحصائيات out as [3][2][1][0]
      // left-to-right, so from الشفتات (1) the tab on the right is الفريق
      // (0) and the tab on the left is المخزن (2). Dragging the strip left
      // brings in whatever sat to the right of it.
      var index = -1;
      await tester.pumpWidget(_host(
        direction: TextDirection.rtl,
        index: 1,
        onSwitch: (i) => index = i,
      ));
      await tester.fling(find.byType(ListView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(index, 0, reason: 'swipe left from الشفتات lands on الفريق');

      await tester.pumpWidget(_host(
        direction: TextDirection.rtl,
        index: 1,
        onSwitch: (i) => index = i,
      ));
      await tester.fling(find.byType(ListView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(index, 2, reason: 'swipe right from الشفتات lands on المخزن');
    });

    testWidgets('RTL: the rule holds from the middle of the row',
        (tester) async {
      var index = -1;
      await tester.pumpWidget(_host(
        direction: TextDirection.rtl,
        index: 2,
        onSwitch: (i) => index = i,
      ));
      await tester.fling(find.byType(ListView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(index, 1, reason: 'swipe left from المخزن lands on الشفتات');

      await tester.pumpWidget(_host(
        direction: TextDirection.rtl,
        index: 2,
        onSwitch: (i) => index = i,
      ));
      await tester.fling(find.byType(ListView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(index, 3, reason: 'swipe right from المخزن lands on الإحصائيات');
    });

    testWidgets('LTR mirrors it, because the visual order mirrors',
        (tester) async {
      var index = -1;
      await tester.pumpWidget(_host(
        direction: TextDirection.ltr,
        index: 2,
        onSwitch: (i) => index = i,
      ));
      await tester.fling(find.byType(ListView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(index, 3, reason: 'LTR: the tab on the right is index + 1');

      await tester.pumpWidget(_host(
        direction: TextDirection.ltr,
        index: 2,
        onSwitch: (i) => index = i,
      ));
      await tester.fling(find.byType(ListView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(index, 1, reason: 'LTR: the tab on the left is index - 1');
    });

    test('adjacentTabIndex is pure and clamps at both ends', () {
      int? at(int i, bool left, TextDirection d) => adjacentTabIndex(
            currentIndex: i,
            tabCount: 4,
            towardLeft: left,
            direction: d,
          );
      // RTL: index grows leftward, so the tab on the right is index - 1.
      expect(at(1, true, TextDirection.rtl), 0);
      expect(at(1, false, TextDirection.rtl), 2);
      expect(at(0, true, TextDirection.rtl), isNull);
      expect(at(3, false, TextDirection.rtl), isNull);
      // LTR: index grows rightward, so the tab on the right is index + 1.
      expect(at(1, true, TextDirection.ltr), 2);
      expect(at(1, false, TextDirection.ltr), 0);
      expect(at(0, false, TextDirection.ltr), isNull);
      expect(at(3, true, TextDirection.ltr), isNull);
    });
  });

  group('thresholds', () {
    testWidgets('a deliberate slow drag switches', (tester) async {
      var index = -1;
      await tester.pumpWidget(_host(
        direction: TextDirection.rtl,
        index: 1,
        onSwitch: (i) => index = i,
      ));
      // 260 of 400 logical pixels, with no fling velocity at all.
      await _slowDrag(tester, -260);
      expect(index, 0);
    });

    testWidgets('a small slip does not switch', (tester) async {
      var switched = false;
      await tester.pumpWidget(_host(
        direction: TextDirection.rtl,
        index: 1,
        onSwitch: (_) => switched = true,
      ));
      await _slowDrag(tester, -40);
      expect(switched, isFalse);
    });

    testWidgets('the edge does not switch past the first or last tab',
        (tester) async {
      var index = 0;
      await tester.pumpWidget(_host(
        direction: TextDirection.rtl,
        index: 0,
        onSwitch: (i) => index = i,
      ));
      // In RTL index 0 is the rightmost tab, and a leftward swipe reaches
      // for the tab on the right — there is nothing there.
      await tester.fling(find.byType(ListView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(index, 0);
    });
  });

  group('staying out of the way', () {
    testWidgets('vertical scrolling in the body still works', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var switched = false;
      await tester.pumpWidget(_host(
        direction: TextDirection.rtl,
        index: 1,
        onSwitch: (_) => switched = true,
        scroll: scroll,
      ));
      await tester.fling(find.byType(ListView), const Offset(0, -400), 1000);
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(switched, isFalse);
    });

    testWidgets('an inner horizontal scroller keeps its own gesture',
        (tester) async {
      final inner = ScrollController();
      addTearDown(inner.dispose);
      var switched = false;

      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: SwipeTabs(
            currentIndex: 1,
            tabCount: 4,
            onSwitch: (_) => switched = true,
            child: Center(
              child: SizedBox(
                height: 80,
                child: ListView.builder(
                  controller: inner,
                  scrollDirection: Axis.horizontal,
                  itemCount: 40,
                  itemBuilder: (_, i) =>
                      SizedBox(width: 80, child: Text('day $i')),
                ),
              ),
            ),
          ),
        ),
      ));

      // A day strip, a chart, a carousel: the innermost claimant wins the
      // arena, so the page must not move underneath it. In RTL a
      // horizontal list advances as the finger travels right, and that is
      // also a direction the outer detector would have accepted (a
      // rightward swipe from index 1 reaches المخزن), so this is the case
      // that would break if the outer ever stopped yielding.
      await tester.fling(find.byType(ListView), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(inner.offset, greaterThan(0));
      expect(switched, isFalse);
    });

    testWidgets('disabled means no gesture at all', (tester) async {
      var switched = false;
      await tester.pumpWidget(_host(
        direction: TextDirection.rtl,
        index: 1,
        onSwitch: (_) => switched = true,
        enabled: false,
      ));
      await tester.fling(find.byType(ListView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(switched, isFalse);
    });
  });
}
