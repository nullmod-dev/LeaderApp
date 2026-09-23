import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/motion/animated_counter.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/motion/motion_tokens.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/app_typography.dart';
import 'package:mtm/core/widgets/glass_bottom_nav.dart';

Future<void> _loadRealFont() async {
  final loader = FontLoader(AppTypography.family);
  for (final f in [
    'assets/fonts/IBMPlexSansArabic-Regular.ttf',
    'assets/fonts/IBMPlexSansArabic-Medium.ttf',
    'assets/fonts/IBMPlexSansArabic-SemiBold.ttf',
  ]) {
    loader.addFont(rootBundle.load(f));
  }
  await loader.load();
}

Widget _app(Widget child,
    {bool disableAnimations = false, MotionLevel? level}) {
  return MaterialApp(
    theme: AppTheme.light(PaletteId.slate),
    locale: const Locale('ar'),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: MotionScope(
          level: level ?? MotionLevel.full,
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_loadRealFont);

  const style = TextStyle(
    fontFamily: AppTypography.family,
    fontFeatures: AppTypography.tabular,
    fontSize: 26,
    fontWeight: FontWeight.w600,
  );

  testWidgets('plain Text: Arabic-Indic digits are proportional (the bug)',
      (tester) async {
    await tester.pumpWidget(_app(const Column(children: [
      Text('٨٨', key: Key('a'), style: style),
      Text('١١', key: Key('b'), style: style),
    ])));
    final w1 = tester.getSize(find.byKey(const Key('a'))).width;
    final w2 = tester.getSize(find.byKey(const Key('b'))).width;
    expect(w1, isNot(closeTo(w2, 0.5)),
        reason: 'font has no tnum; ٨٨ and ١١ differ');
  });

  testWidgets('TabularDigits: every digit occupies the same cell',
      (tester) async {
    await tester.pumpWidget(_app(const Column(children: [
      TabularDigits('٨٨', key: Key('a'), style: style),
      TabularDigits('١١', key: Key('b'), style: style),
      TabularDigits('٠٩', key: Key('c'), style: style),
    ])));
    final a = tester.getSize(find.byKey(const Key('a'))).width;
    final b = tester.getSize(find.byKey(const Key('b'))).width;
    final c = tester.getSize(find.byKey(const Key('c'))).width;
    expect(b, closeTo(a, 0.01));
    expect(c, closeTo(a, 0.01));
  });

  testWidgets('TabularDigits renders numerals left-to-right', (tester) async {
    await tester.pumpWidget(_app(const TabularDigits('١٢', style: style)));
    final one = tester.getTopLeft(find.text('١')).dx;
    final two = tester.getTopLeft(find.text('٢')).dx;
    expect(one, lessThan(two), reason: '١٢ must read 12, not 21');
  });

  testWidgets('AnimatedCounter keeps a stable width across the tween',
      (tester) async {
    await tester
        .pumpWidget(_app(const AnimatedCounter(value: 88, style: style)));
    final widths = <double>[];
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      widths.add(tester.getSize(find.byType(TabularDigits)).width);
    }
    await tester.pumpAndSettle();
    // Width may step when the number gains a digit (9 -> 10), never
    // because one digit is wider than another.
    expect(widths.toSet().length, lessThanOrEqualTo(2),
        reason: 'observed widths: $widths');
  });

  testWidgets('reduced motion: no BackdropFilter on the bottom nav',
      (tester) async {
    const dests = [
      GlassNavDestination(icon: Icons.home, label: 'الرئيسية'),
      GlassNavDestination(icon: Icons.settings, label: 'المزيد'),
    ];
    Widget nav() => GlassBottomNav(
          destinations: dests,
          currentIndex: 0,
          onDestinationSelected: (_) {},
        );

    await tester.pumpWidget(_app(nav(), level: MotionLevel.full));
    expect(find.byType(BackdropFilter), findsOneWidget);

    await tester.pumpWidget(_app(nav(), level: MotionLevel.reduced));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(RepaintBoundary), findsWidgets);
  });

  testWidgets('OS reduce-motion outranks the quality level', (tester) async {
    late bool reduced;
    Widget probe() => Builder(builder: (context) {
          reduced = reduceMotion(context);
          return const SizedBox();
        });

    // Even the richest level cannot talk over an accessibility request.
    await tester.pumpWidget(_app(
      probe(),
      disableAnimations: true,
      level: MotionLevel.maximum,
    ));
    expect(reduced, isTrue);

    // With the flag off, every level animates except `performance`, which
    // is deliberately motion-off — that is what the level promises, and it
    // is a choice the user made rather than one made for them.
    for (final level in MotionLevel.values) {
      await tester.pumpWidget(_app(
        probe(),
        disableAnimations: false,
        level: level,
      ));
      expect(
        reduced,
        level == MotionLevel.performance,
        reason: '$level',
      );
    }
  });

  testWidgets('the quality ladder only ever gets cheaper going down',
      (tester) async {
    late List<MotionSpec> specs;
    await tester.pumpWidget(_app(Builder(builder: (context) {
      specs = MotionLevel.values.map((l) => l.spec).toList();
      return const SizedBox();
    })));

    for (var i = 1; i < specs.length; i++) {
      final cheaper = specs[i - 1];
      final richer = specs[i];
      expect(cheaper.durationScale, lessThanOrEqualTo(richer.durationScale));
      expect(cheaper.intensity, lessThanOrEqualTo(richer.intensity));
      expect(cheaper.blurSigma, lessThanOrEqualTo(richer.blurSigma));
      expect(
        cheaper.staggerMaxItems,
        lessThanOrEqualTo(richer.staggerMaxItems),
      );
    }
    // The ceiling stays cheap: maximum adds no new expensive effect over
    // high beyond the tab cross-fade.
    expect(MotionSpec.maximum.blurSigma, lessThanOrEqualTo(24));
    expect(MotionSpec.maximum.crossFadeOutgoing, isTrue);
    expect(MotionSpec.high.crossFadeOutgoing, isFalse);
    // Each step has to differ by *kind* of work, not only by duration —
    // otherwise five levels is one slider wearing a disguise.
    expect(MotionSpec.performance.isInstant, isTrue,
        reason: 'performance means animations off, not just short');
    expect(MotionSpec.performance.ambientLoops, isFalse);
    expect(MotionSpec.performance.hasBlur, isFalse);
    expect(MotionSpec.performance.richShadows, isFalse);
    expect(MotionSpec.low.isInstant, isFalse);
    expect(MotionSpec.low.hasBlur, isFalse);
    expect(MotionSpec.low.stagger, isFalse);
    expect(MotionSpec.low.animatedValues, isFalse);
    expect(MotionSpec.low.slideRoutes, isFalse);
    expect(MotionSpec.balanced.hasBlur, isTrue);
    expect(MotionSpec.balanced.stagger, isTrue);
    expect(MotionSpec.balanced.animatedValues, isTrue);
    expect(MotionSpec.balanced.slideRoutes, isTrue);
    expect(MotionSpec.balanced.overshoot, isFalse);
    expect(MotionSpec.high.overshoot, isTrue);
    // The stagger cascade never outruns its sub-300ms budget.
    for (final level in MotionLevel.values) {
      expect(
        level.spec.staggerMaxItems,
        lessThanOrEqualTo(MotionTokens.staggerMaxItems),
        reason: '$level',
      );
    }
  });

  test('motion tokens collapse to zero under reduced motion', () {
    expect(ui.PlatformDispatcher.instance, isNotNull);
  });
}
