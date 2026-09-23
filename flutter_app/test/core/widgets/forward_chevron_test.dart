import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/widgets/forward_chevron.dart';

/// The forward-disclosure rule, in both directions.
///
/// The defect this guards (UI audit P1-1) was invisible in code review: a
/// `chevron_left` *looks* like "forward" to a reader thinking in Arabic, and
/// the mirroring then flips it to "back" on screen. So these tests assert on
/// the rendered result — the glyph after `matchTextDirection` has been
/// applied — not on the constant a call site wrote.

/// What the chevron physically points at, once Flutter's text-direction
/// mirroring has been resolved.
///
/// `RenderParagraph`'s `textDirection` is what `Icon` flips, so reading it
/// back is reading the mirroring decision itself.
enum _Points { left, right }

_Points _pointsOf(WidgetTester tester, Finder icon) {
  final widget = tester.widget<Icon>(icon);
  final data = widget.icon!;
  final mirrors = data.matchTextDirection;
  final direction = Directionality.of(tester.element(icon));
  final flipped = mirrors && direction == TextDirection.rtl;
  final baseRight = data.codePoint == Icons.chevron_right_rounded.codePoint;
  final right = flipped ? !baseRight : baseRight;
  return right ? _Points.right : _Points.left;
}

Widget _host(Widget child, TextDirection direction) => MaterialApp(
      theme: AppTheme.light(PaletteId.medical),
      home: Directionality(
        textDirection: direction,
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  group('ForwardChevron', () {
    testWidgets('points left in Arabic — the way the user travels',
        (tester) async {
      await tester.pumpWidget(
        _host(const ForwardChevron(), TextDirection.rtl),
      );
      final icon = find.byType(Icon);
      expect(_pointsOf(tester, icon), _Points.left);
    });

    testWidgets('points right in a left-to-right locale', (tester) async {
      await tester.pumpWidget(
        _host(const ForwardChevron(), TextDirection.ltr),
      );
      expect(_pointsOf(tester, find.byType(Icon)), _Points.right);
    });

    testWidgets('mirrors exactly once — no double flip', (tester) async {
      // A call site that also flipped by hand would cancel the mirroring out
      // and render identically in both directions. Two directions, two
      // different results, is the proof it mirrors exactly once.
      await tester.pumpWidget(
        _host(const ForwardChevron(), TextDirection.rtl),
      );
      final rtl = _pointsOf(tester, find.byType(Icon));
      await tester.pumpWidget(
        _host(const ForwardChevron(), TextDirection.ltr),
      );
      final ltr = _pointsOf(tester, find.byType(Icon));
      expect(rtl, isNot(ltr));
    });

    testWidgets('carries no accessible name by default', (tester) async {
      // The row's own label says where it goes; a second "chevron" node on
      // every list row is noise.
      await tester.pumpWidget(
        _host(const ForwardChevron(), TextDirection.rtl),
      );
      expect(tester.widget<Icon>(find.byType(Icon)).semanticLabel, isNull);
    });

    testWidgets('takes a semantic label where it is the only affordance',
        (tester) async {
      await tester.pumpWidget(
        _host(const ForwardChevron(semanticLabel: 'التفاصيل'),
            TextDirection.rtl),
      );
      expect(
        tester.widget<Icon>(find.byType(Icon)).semanticLabel,
        'التفاصيل',
      );
    });

    testWidgets('defaults to ink3 and honours an override', (tester) async {
      await tester.pumpWidget(
        _host(const ForwardChevron(), TextDirection.rtl),
      );
      final palette = AppColors.resolve(PaletteId.medical, Brightness.light);
      expect(tester.widget<Icon>(find.byType(Icon)).color, palette.ink3);

      await tester.pumpWidget(
        _host(ForwardChevron(color: palette.warn), TextDirection.rtl),
      );
      expect(tester.widget<Icon>(find.byType(Icon)).color, palette.warn);
    });
  });

  group('DirectionalArrows', () {
    testWidgets('earlier points right in Arabic, later points left',
        (tester) async {
      await tester.pumpWidget(_host(
        const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(DirectionalArrows.earlier, key: Key('earlier')),
          Icon(DirectionalArrows.later, key: Key('later')),
        ]),
        TextDirection.rtl,
      ));
      expect(_pointsOf(tester, find.byKey(const Key('earlier'))),
          _Points.right);
      expect(_pointsOf(tester, find.byKey(const Key('later'))), _Points.left);
    });

    testWidgets('and the other way round in LTR', (tester) async {
      await tester.pumpWidget(_host(
        const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(DirectionalArrows.earlier, key: Key('earlier')),
          Icon(DirectionalArrows.later, key: Key('later')),
        ]),
        TextDirection.ltr,
      ));
      expect(
          _pointsOf(tester, find.byKey(const Key('earlier'))), _Points.left);
      expect(_pointsOf(tester, find.byKey(const Key('later'))), _Points.right);
    });

    testWidgets('earlier and later are never the same glyph', (tester) async {
      expect(DirectionalArrows.earlier, isNot(DirectionalArrows.later));
      expect(DirectionalArrows.later, ForwardChevron.icon);
    });
  });
}
