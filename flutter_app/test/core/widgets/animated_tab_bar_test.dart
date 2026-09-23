import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/widgets/animated_tab_bar.dart';
import 'package:mtm/core/widgets/swipe_tabs.dart';
import 'package:mtm/l10n/strings.dart';

const _tabs = [
  S.workshopTeam,
  S.workshopMembers,
  S.workshopStats,
];

class _Harness extends StatefulWidget {
  const _Harness({required this.initialIndex});

  final int initialIndex;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late int _index = widget.initialIndex;

  void _select(int value) => setState(() => _index = value);

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 760),
            textScaler: TextScaler.linear(1.6),
          ),
          child: Theme(
            data: AppTheme.light(PaletteId.medical),
            child: Material(
              child: Column(
                children: [
                  AnimatedTabBar(
                    tabs: _tabs,
                    currentIndex: _index,
                    onChanged: _select,
                  ),
                  Expanded(
                    child: SwipeTabs(
                      currentIndex: _index,
                      tabCount: _tabs.length,
                      onSwitch: _select,
                      child: ListView(
                        key: const Key('tab-body'),
                        children: const [SizedBox(height: 900)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

void main() {
  Future<void> pump(WidgetTester tester, {int index = 2}) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_Harness(initialIndex: index));
    await tester.pumpAndSettle();
  }

  testWidgets('320dp at 1.6x keeps the selected RTL tab visible and whole',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    expect(tester.takeException(), isNull);
    final viewport = tester.getRect(
      find.byKey(const Key('animated-tab-strip-scroll')),
    );
    final selected = tester.getRect(find.text(S.workshopStats));
    expect(selected.left, greaterThanOrEqualTo(viewport.left - 0.01));
    expect(selected.right, lessThanOrEqualTo(viewport.right + 0.01));

    final node = tester.getSemantics(
      find.bySemanticsLabel(S.workshopStats),
    );
    expect(node.flagsCollection.isSelected, Tristate.isTrue);
    expect(node.flagsCollection.isButton, isTrue);

    final indicator = tester.getRect(
      find.byKey(const Key('animated-tab-indicator')),
    );
    expect(indicator.center.dx, closeTo(selected.center.dx, 0.5));
    semantics.dispose();
  });

  testWidgets('tap navigation updates selection and reveals the target',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);

    await tester.ensureVisible(find.text(S.workshopMembers));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.workshopMembers));
    await tester.pumpAndSettle();

    expect(
      tester
          .getSemantics(find.bySemanticsLabel(S.workshopMembers))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    final viewport = tester.getRect(
      find.byKey(const Key('animated-tab-strip-scroll')),
    );
    final selected = tester.getRect(find.text(S.workshopMembers));
    expect(selected.left, greaterThanOrEqualTo(viewport.left - 0.01));
    expect(selected.right, lessThanOrEqualTo(viewport.right + 0.01));
    semantics.dispose();
  });

  testWidgets('the body swipe contract is unchanged beside the scroll strip',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, index: 1);

    // In RTL, a leftward swipe from index 1 lands on index 0, exactly as the
    // dedicated SwipeTabs suite specifies.
    await tester.fling(
      find.byKey(const Key('tab-body')),
      const Offset(-300, 0),
      1000,
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSemantics(find.bySemanticsLabel(S.workshopTeam))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    semantics.dispose();
  });
}
