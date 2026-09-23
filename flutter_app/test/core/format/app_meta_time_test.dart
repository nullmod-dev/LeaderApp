import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/format/app_date.dart';
import 'package:mtm/core/format/app_number.dart';
import 'package:mtm/core/format/app_time.dart';
import 'package:mtm/core/text/bidi.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/platform/presentation/widgets/platform_meta.dart';
import 'package:mtm/l10n/strings.dart';

/// The shared metadata and time layer.
///
/// UI audit P1-11: the app joined facts with a literal ` · ` in 115 places
/// while rendering every number in Arabic-Indic, where zero is `٠` — the same
/// mark. Phase 2 fixed it on the platform surface; Phase 3A moved the fix to
/// `core/` so the tenant surface reads by the same one. These tests hold two
/// things: that the separator is never a character, and that a value which
/// carries its own direction keeps it without dragging the Arabic around it
/// out of place.

const _lri = '\u2066';
const _pdi = '\u2069';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(PaletteId.medical),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: child)),
      ),
    ),
  );
}

/// Every string a widget subtree actually paints.
List<String> _painted(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? '')
    .toList();

void main() {
  group('the separator is drawn, never written', () {
    testWidgets('no meta line prints a middle dot', (tester) async {
      await _pump(
        tester,
        AppMeta(parts: [
          const AppMetaText('السبت ١٢ أيلول'),
          const AppMetaText('اللاذقية'),
          AppMetaText.count(4, label: 'مفرزات'),
        ]),
      );

      final painted = _painted(tester);
      expect(painted.length, 3);
      for (final text in painted) {
        expect(text.contains('·'), isFalse, reason: 'no U+00B7 in «$text»');
        expect(text.contains('•'), isFalse);
        expect(text.contains('․'), isFalse);
      }
    });

    testWidgets('the rule is a box, not a glyph, and is never announced',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const AppMeta(parts: [
          AppMetaText('أولى'),
          AppMetaText('ثانية'),
        ]),
      );
      // One rule for two facts, attached to the second so a wrapped line
      // never opens with an orphan mark.
      expect(
        find.descendant(
          of: find.byType(AppMeta),
          matching: find.byType(ColoredBox),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.byType(AppMeta)).label.contains('|'),
        isFalse,
      );
      handle.dispose();
    });

    testWidgets('a number-only line stays legible beside Arabic-Indic zero',
        (tester) async {
      await _pump(
        tester,
        AppMeta(parts: [
          AppMetaText.count(0, label: 'موقوف'),
          AppMetaText.count(0, label: 'بانتظار الحذف'),
          AppMetaText.count(1, label: 'سماح'),
        ]),
      );
      // The audit's worst case — «١ سماح · ٠ موقوف · ٠ بانتظار الحذف», five
      // identical dots of which three were values. Now every «٠» on the line
      // is a number.
      final painted = _painted(tester).join(' ');
      expect(painted.contains('·'), isFalse);
      expect(painted.contains('٠'), isTrue);
    });
  });

  group('values that carry their own direction', () {
    test('a clock is isolated, and the isolate wraps the whole range', () {
      final time = AppTime.time(DateTime(2026, 9, 12, 8, 5));
      expect(time, '$_lri٠٨:٠٥$_pdi');

      final range = AppTime.clockRange(
        DateTime(2026, 9, 12, 8, 0),
        DateTime(2026, 9, 12, 14, 0),
      );
      // One isolate around the pair, not one around each: two isolates with a
      // dash between them let the dash resolve against the Arabic and swap
      // which end of the range it belongs to.
      expect(range, '$_lri٠٨:٠٠ – ١٤:٠٠$_pdi');
      expect(range.split(_lri).length, 2);

      // An open-ended range is the start alone, still isolated.
      expect(AppTime.clockRange(DateTime(2026, 9, 12, 8, 0), null),
          '$_lri٠٨:٠٠$_pdi');
    });

    test('an empty value is not wrapped in two invisible characters', () {
      expect(Bidi.ltr(''), '');
      expect(Bidi.isIsolated(Bidi.ltr('HILAL')), isTrue);
      expect(Bidi.isIsolated('HILAL'), isFalse);
    });

    testWidgets('an id, an email and a money amount keep their own order',
        (tester) async {
      await _pump(
        tester,
        const AppMeta(parts: [
          AppMetaText.code('MTM-2026-04'),
          AppMetaText.code('admin@leader.example'),
          AppMetaText.money(r'$14.00'),
        ]),
      );
      for (final text in _painted(tester)) {
        expect(text.startsWith(_lri), isTrue, reason: text);
        expect(text.endsWith(_pdi), isTrue, reason: text);
      }
    });

    testWidgets('an already-isolated value is not isolated twice',
        (tester) async {
      await _pump(
        tester,
        AppMetaText.code(AppTime.time(DateTime(2026, 9, 12, 8, 5))),
      );
      final painted = _painted(tester).single;
      expect(painted.split(_lri).length, 2, reason: 'one isolate, not two');
    });

    testWidgets('the row itself is never forced left-to-right',
        (tester) async {
      await _pump(
        tester,
        const AppMeta(parts: [
          AppMetaText('مفرزة الساحل'),
          AppMetaText.code('HILAL'),
        ]),
      );
      // An isolate is the narrow tool; a `Directionality` override would drag
      // the Arabic beside the code out of place.
      final overrides = tester
          .widgetList<Directionality>(find.descendant(
            of: find.byType(AppMeta),
            matching: find.byType(Directionality),
          ))
          .where((d) => d.textDirection == TextDirection.ltr);
      expect(overrides, isEmpty);
    });
  });

  group('dates and numerals', () {
    test('the app date shapes are Arabic-Indic and in the product order', () {
      final day = DateTime(2026, 9, 12, 14, 30);
      expect(AppTime.day(day), '١٢ أيلول');
      expect(AppTime.date(day), '١٢ أيلول ٢٠٢٦');
      expect(AppTime.weekdayDay(day), 'السبت ١٢ أيلول');
      // A day and a clock, joined by a space — never by a dot immediately
      // before a time that begins «٠».
      expect(AppTime.dayTime(DateTime(2026, 9, 12, 9, 0)),
          '١٢ أيلول $_lri٠٩:٠٠$_pdi');
      expect(AppTime.dayTime(day).contains('·'), isFalse);
    });

    test('one percentage path, and it is the Arabic sign', () {
      expect(AppNumber.percent(83), '٨٣${S.percentSign}');
      expect(AppNumber.percent(83).contains('%'), isFalse);
      expect(AppNumber.count(1204), '١٢٠٤');
      expect(AppNumber.ratio(3, 7), '$_lri٣ / ٧$_pdi');
      expect(AppNumber.range(0, 100), '$_lri٠–١٠٠$_pdi');
    });
  });

  group('the platform surface reads the shared implementation', () {
    test('PlatformMeta is an alias, not a second copy', () {
      const meta = PlatformMeta(parts: []);
      expect(meta, isA<AppMeta>());
      const text = PlatformMetaText('س');
      expect(text, isA<AppMetaText>());
    });

    test('the local shapes are delegated and unchanged', () {
      final t = DateTime(2026, 9, 8, 15, 4);
      expect(PlatformTime.date(t), AppTime.date(t));
      expect(PlatformTime.time(t), AppTime.time(t));
      expect(PlatformTime.dayTime(t), AppTime.dayTime(t));
    });

    test('UTC stays UTC — this phase changed presentation, not an instant',
        () {
      final utc = DateTime.utc(2026, 9, 8, 15, 4);
      expect(PlatformTime.utcTime(utc), '$_lri١٥:٠٤$_pdi ${S.platformTimeUtc}');
      expect(PlatformTime.utcDate(utc), '٨ أيلول ٢٠٢٦');
      // Only the clock is isolated: wrapping the phrase would drag «بتوقيت»
      // into a left-to-right run and print it after the Latin token.
      expect(PlatformTime.utcTime(utc).endsWith(S.platformTimeUtc), isTrue);
    });
  });

  group('the last helper that still printed the mark', () {
    // `AppDate.dayMonthTime` joined a day to a clock with ` · ` long after
    // the rest of the product had stopped: Organization's «آخر قراءة», the
    // SaaS tenant detail, the lifecycle section, the feature-availability
    // report and the attendance PDF all read it. Phase 3C took the mark out
    // rather than migrating six call sites onto a seventh spelling.
    test('a day and a clock are joined by a space, not a dot', () {
      final t = DateTime(2026, 9, 12, 9, 5);
      expect(AppDate.dayMonthTime(t).contains('·'), isFalse);
      expect(AppDate.dayMonthTime(t), '١٢ أيلول ٠٩:٠٥');
    });

    test('it agrees with AppTime.dayTime on everything but the isolate', () {
      final t = DateTime(2026, 9, 12, 9, 5);
      final withoutIsolate =
          AppTime.dayTime(t).replaceAll(_lri, '').replaceAll(_pdi, '');
      expect(withoutIsolate, AppDate.dayMonthTime(t));
    });
  });
}
