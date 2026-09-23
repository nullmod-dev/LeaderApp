import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/widgets/glass_bottom_nav.dart';

/// `MotionTokens.spring` overshoots past its endpoint on purpose. Two of the
/// properties the nav pill animates have a hard floor at zero — the shadow's
/// blur radius and the label's width factor — so an overshoot aimed at zero
/// lands on a negative value and asserts inside `dart:ui`/`Align`. The tab
/// then renders as a red `ErrorWidget`, which in turn blows out the nav's
/// Column. It only fires on the tab that is being DESELECTED, so the app
/// looks fine until the first tab switch.
void main() {
  const destinations = [
    GlassNavDestination(icon: Icons.home_rounded, label: 'الرئيسية'),
    GlassNavDestination(icon: Icons.flag_rounded, label: 'المفارز'),
  ];

  Future<void> pumpNav(WidgetTester tester, MotionLevel level) async {
    tester.view.physicalSize = const Size(1152, 2560);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    var index = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(PaletteId.slate),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: MotionScope(
          level: level,
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: StatefulBuilder(
                builder: (context, setState) => GlassBottomNav(
                  destinations: destinations,
                  currentIndex: index,
                  onDestinationSelected: (i) => setState(() => index = i),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> walkMorphs(WidgetTester tester) async {
    for (final icon in [
      Icons.flag_rounded,
      Icons.home_rounded,
      Icons.flag_rounded,
    ]) {
      await tester.tap(find.byIcon(icon));
      // Frame by frame: the overshoot lives in the back half of the morph,
      // so pumpAndSettle alone would step straight over it.
      for (var elapsed = 0; elapsed <= 320; elapsed += 5) {
        await tester.pump(const Duration(milliseconds: 5));
        expect(tester.takeException(), isNull,
            reason: 'nav pill threw ${elapsed}ms into the morph');
      }
    }
  }

  testWidgets('switching tabs never drives a property below its floor',
      (tester) async {
    await pumpNav(tester, MotionLevel.full);
    await walkMorphs(tester);
  });

  testWidgets('the same holds under reduced motion', (tester) async {
    await pumpNav(tester, MotionLevel.reduced);
    await walkMorphs(tester);
  });

  testWidgets('every destination has one Arabic label and selection state',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpNav(tester, MotionLevel.reduced);

    final home = tester.getSemantics(find.bySemanticsLabel('الرئيسية'));
    expect(home.label, 'الرئيسية');
    expect(home.flagsCollection.isButton, isTrue);
    expect(home.flagsCollection.isSelected, Tristate.isTrue);

    final detachments = tester.getSemantics(find.bySemanticsLabel('المفارز'));
    expect(detachments.label, 'المفارز');
    expect(detachments.flagsCollection.isButton, isTrue);
    expect(detachments.flagsCollection.isSelected, Tristate.isFalse);

    // `ExcludeSemantics` keeps the painted active label from creating a
    // second screen-reader node with the same text.
    expect(find.bySemanticsLabel('الرئيسية'), findsOneWidget);
    expect(find.bySemanticsLabel('المفارز'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('المفارز'));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('المفارز'))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    handle.dispose();
  });
}
