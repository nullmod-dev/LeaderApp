import 'dart:math' as math;

/// What a series is measured in — and therefore what scale it may be drawn
/// against.
enum SeriesUnit {
  /// A proportion of a whole that is already known. Its scale is 0–100 and
  /// nothing else.
  percent,

  /// A tally with no natural ceiling — units consumed, shifts worked. Its
  /// scale runs from zero to a stated round number above the peak.
  count,
}

/// A series, its domain, and the readings a caller needs to describe it.
///
/// **The defect this exists to prevent.** The statistics tab drew seven bars
/// whose heights were `value / max(series)`. That is not a chart, it is a
/// ranking: a coverage series of ٤٠/٤٢/٤١٪ drew *identically* to ٩٠/٩٥/٩٢٪,
/// because both were normalised to their own peak. The tallest bar always
/// touched the ceiling, which reads as "full", whatever the number behind it
/// was. The 2026-09-19 UI audit filed it as P1-10 and it is the only finding
/// in this programme about a screen stating something untrue.
///
/// So the domain is decided by the *unit*, never by the data:
///
///  * [SeriesUnit.percent] → **always 0–100.** A percentage compared against
///    anything but the whole it is a percentage of is a different number.
///  * [SeriesUnit.count] → **0 to [niceCeiling] of the peak.** A count has no
///    inherent maximum, so one is chosen — the smallest of 1, 2 or 5 × 10ⁿ
///    that clears the peak — and then it is *printed*, because a bar whose
///    height is a fraction of an unstated ceiling says nothing at all.
///
/// **Two units are never put on one scale.** Coverage and consumption are
/// drawn in two cards with two stated domains. Sharing an axis to make two
/// cards look alike would be the same lie in the other direction.
class SeriesPlot {
  SeriesPlot._({
    required this.values,
    required this.unit,
    required this.domainMax,
  });

  /// Reads [values] as a series in [unit]. Oldest first, which is the order
  /// every repository in this app returns and the order the bars are drawn
  /// in.
  factory SeriesPlot(List<int> values, {required SeriesUnit unit}) {
    final peak = values.isEmpty ? 0 : values.reduce(math.max);
    return SeriesPlot._(
      values: List<int>.unmodifiable(values),
      unit: unit,
      domainMax: switch (unit) {
        SeriesUnit.percent => 100,
        SeriesUnit.count => niceCeiling(peak),
      },
    );
  }

  final List<int> values;
  final SeriesUnit unit;

  /// The top of the scale. The bottom is always zero: a bar chart whose
  /// baseline is not zero exaggerates every difference on it.
  final int domainMax;

  int get domainMin => 0;

  /// False where drawing bars would say more than the data does: fewer than
  /// two readings is not a trend, and seven bars at 2 % height is a picture
  /// of nothing. Both get a sentence instead of a chart.
  bool get isPlottable => values.length >= 2 && !isAllZero;

  bool get isAllZero => values.every((v) => v == 0);

  /// Height of the bar at [index], as a fraction of the plot area. Clamped,
  /// so a value above a percent domain cannot draw outside the card.
  double fractionAt(int index) =>
      domainMax == 0 ? 0 : (values[index] / domainMax).clamp(0.0, 1.0);

  /// The reading the screen is actually about: the most recent one.
  int get latest => values.isEmpty ? 0 : values.last;

  /// The reading before [latest], or null when there is only one.
  int? get previous => values.length < 2 ? null : values[values.length - 2];

  int get high => values.isEmpty ? 0 : values.reduce(math.max);

  int get low => values.isEmpty ? 0 : values.reduce(math.min);

  int get average => values.isEmpty
      ? 0
      : (values.reduce((a, b) => a + b) / values.length).round();

  /// `latest - previous`, or null when there is nothing to compare against.
  /// Said in words by the caller, never by an arrow or a colour alone.
  int? get change {
    final before = previous;
    return before == null ? null : latest - before;
  }
}

/// The smallest of 1, 2 or 5 × 10ⁿ that is greater than or equal to [value].
///
/// The classic axis steps. They are coarse on purpose: a ceiling chosen to
/// sit exactly on the peak is the normalisation this whole file exists to
/// stop.
int niceCeiling(int value) {
  if (value <= 0) return 1;
  var magnitude = 1;
  while (magnitude * 10 <= value) {
    magnitude *= 10;
  }
  for (final step in const [1, 2, 5]) {
    final candidate = step * magnitude;
    if (candidate >= value) return candidate;
  }
  return magnitude * 10;
}
