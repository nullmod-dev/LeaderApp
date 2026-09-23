import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/chart/series_scale.dart';

/// The scale policy, as arithmetic.
///
/// UI audit P1-10: the statistics tab drew each series normalised to its own
/// maximum, so a coverage series of 40/42/41 % produced exactly the same
/// picture as 90/95/92 %. These tests are the guard on that never coming
/// back — they are about the *domain* a series is drawn against, which is the
/// part a widget test cannot see.
void main() {
  group('percentages are always drawn against 0–100', () {
    test('a low, flat series stays low', () {
      final plot = SeriesPlot(const [40, 42, 41], unit: SeriesUnit.percent);
      expect(plot.domainMin, 0);
      expect(plot.domainMax, 100);
      expect(plot.fractionAt(0), closeTo(0.40, 0.001));
      expect(plot.fractionAt(1), closeTo(0.42, 0.001));
      expect(plot.fractionAt(2), closeTo(0.41, 0.001));
    });

    test('a high series and a low one do not draw alike — the whole point',
        () {
      final low = SeriesPlot(const [40, 42, 41], unit: SeriesUnit.percent);
      final high = SeriesPlot(const [90, 95, 92], unit: SeriesUnit.percent);
      // Under the old `value / max(series)` rule these two were pixel
      // identical: 0.95/0.99/0.97 in both cases.
      for (var i = 0; i < 3; i++) {
        expect(
          (high.fractionAt(i) - low.fractionAt(i)).abs(),
          greaterThan(0.4),
          reason: 'bar $i must differ by roughly the 50 points between them',
        );
      }
      // And neither one's peak touches the ceiling, because neither is 100 %.
      expect(low.fractionAt(1), lessThan(0.5));
      expect(high.fractionAt(1), lessThan(1.0));
    });

    test('a percentage above the domain is clamped, never drawn outside it',
        () {
      final plot = SeriesPlot(const [0, 140], unit: SeriesUnit.percent);
      expect(plot.fractionAt(1), 1.0);
    });
  });

  group('counts are drawn against a stated round ceiling', () {
    test('the ceiling clears the peak and is a round number', () {
      final plot =
          SeriesPlot(const [12, 18, 9, 22, 15, 30, 24], unit: SeriesUnit.count);
      expect(plot.domainMax, 50);
      // The peak is 30 of 50 — it does not touch the top, which is what
      // "normalised to its own maximum" always made it do.
      expect(plot.fractionAt(5), closeTo(0.6, 0.001));
      expect(plot.high, 30);
      expect(plot.latest, 24);
      expect(plot.average, 19);
    });

    test('niceCeiling walks 1 / 2 / 5 × 10ⁿ', () {
      expect(niceCeiling(0), 1);
      expect(niceCeiling(1), 1);
      expect(niceCeiling(2), 2);
      expect(niceCeiling(3), 5);
      expect(niceCeiling(8), 10);
      expect(niceCeiling(12), 20);
      expect(niceCeiling(24), 50);
      expect(niceCeiling(30), 50);
      expect(niceCeiling(51), 100);
      expect(niceCeiling(140), 200);
      expect(niceCeiling(999), 1000);
    });
  });

  group('a series that cannot be drawn honestly is not drawn', () {
    test('all zeros is refused rather than drawn as seven stubs', () {
      final plot =
          SeriesPlot(const [0, 0, 0, 0, 0, 0, 0], unit: SeriesUnit.count);
      expect(plot.isAllZero, isTrue);
      expect(plot.isPlottable, isFalse);
    });

    test('one reading is not a trend', () {
      expect(SeriesPlot(const [40], unit: SeriesUnit.percent).isPlottable,
          isFalse);
      expect(
          SeriesPlot(const [], unit: SeriesUnit.percent).isPlottable, isFalse);
    });
  });

  group('the readings a card describes in words', () {
    test('change is against the day before, and null when there is none', () {
      expect(SeriesPlot(const [90, 92], unit: SeriesUnit.percent).change, 2);
      expect(SeriesPlot(const [30, 24], unit: SeriesUnit.count).change, -6);
      expect(SeriesPlot(const [7, 7], unit: SeriesUnit.count).change, 0);
      expect(SeriesPlot(const [7], unit: SeriesUnit.count).change, isNull);
    });

    test('the baseline is zero, so a flat series is flat', () {
      final plot = SeriesPlot(const [80, 80, 80], unit: SeriesUnit.percent);
      expect(plot.fractionAt(0), plot.fractionAt(2));
      expect(plot.domainMin, 0);
    });
  });
}
