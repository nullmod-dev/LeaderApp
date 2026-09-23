import 'package:flutter/material.dart';

import '../format/app_date.dart';
import '../format/app_number.dart';
import '../motion/animated_counter.dart';
import '../motion/motion_tokens.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../time/calendar_day.dart';
import '../widgets/app_meta.dart';
import '../widgets/section_header.dart';
import '../../l10n/strings.dart';
import 'series_scale.dart';

/// A daily series, drawn against a stated scale and described in words.
///
/// **What it draws.** One bar per day on a zero baseline, sized by
/// [SeriesPlot.fractionAt] — so the picture is a reading against a fixed
/// domain, not a ranking within the series. A faint rule sits at the top of
/// the plot area so the ceiling is visible as well as printed, and the most
/// recent bar is the one drawn in the full tone: it is the reading the screen
/// is about.
///
/// **What it says.** A chart is never the only carrier. Every card prints the
/// period, the day each bar belongs to, the latest reading, the high, the
/// average, the scale, and the change against the day before **in words**.
/// The whole card also carries one semantics sentence, so a reader who gets
/// no picture at all still gets the metric.
///
/// **What it refuses to draw.** A series with fewer than two readings, or one
/// that is all zeros, gets a sentence. Seven bars at 2 % height is a chart
/// pretending there is data.
class SeriesCard extends StatelessWidget {
  const SeriesCard({
    super.key,
    required this.id,
    required this.title,
    required this.hint,
    required this.plot,
    required this.endsOn,
    this.tone,
  });

  /// A stable name for this series, used for the card's key. It is what a
  /// test reads the spoken description off, and a chart whose text equivalent
  /// cannot be addressed is a chart whose text equivalent nobody checks.
  final String id;

  final String title;

  /// One line saying what the metric counts. A chart that needs the reader to
  /// infer its own definition is a chart that will be read wrongly once.
  final String hint;

  final SeriesPlot plot;

  /// The calendar day the **last** reading belongs to. The series is
  /// documented as consecutive days ending here, which is what lets the bars
  /// carry day numbers without the repository sending dates it does not have.
  final DateTime endsOn;

  /// Overrides the bar colour. Defaults to the brand tone.
  final Color? tone;

  /// The day each reading belongs to, oldest first.
  List<DateTime> get _days => [
        for (var i = 0; i < plot.values.length; i++)
          addDays(endsOn, -(plot.values.length - 1 - i)),
      ];

  String _value(int v) => switch (plot.unit) {
        SeriesUnit.percent => AppNumber.percent(v),
        SeriesUnit.count => AppNumber.count(v),
      };

  String _changeSentence() {
    final delta = plot.change;
    if (delta == null) return S.statsChangeUnknown;
    if (delta == 0) return S.statsChangeNone;
    // The magnitude carries no percent sign even on a percent series. A move
    // from ٩٠٪ to ٩٢٪ is two points on a 0–100 scale, not a two-per-cent
    // change, and «٢٪» is the shorter of those two readings — so the figure
    // is printed bare, beside a latest value and a scale that both say what
    // it is measured against.
    final magnitude = AppNumber.count(delta.abs());
    return (delta > 0 ? S.statsChangeUp : S.statsChangeDown)
        .replaceFirst('%s', magnitude);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final days = _days;
    final period = days.isEmpty
        ? ''
        : '${AppDate.dayMonth(days.first)} – ${AppDate.dayMonth(days.last)}';
    final scale = '${S.statsScale} '
        '${AppNumber.range(plot.domainMin, plot.domainMax)}'
        '${plot.unit == SeriesUnit.percent ? S.percentSign : ''}';
    final latest = '${S.statsLatest} ${_value(plot.latest)}';

    final spoken = S.statsSeriesSemantics
        .replaceFirst('%title%', title)
        .replaceFirst('%period%', period)
        .replaceFirst('%latest%', latest)
        .replaceFirst('%high%', _value(plot.high))
        .replaceFirst('%avg%', _value(plot.average))
        .replaceFirst('%scale%', scale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: title),
        Semantics(
          key: Key('series-$id'),
          container: true,
          label: plot.isPlottable
              ? '$spoken ${_changeSentence()}.'
              : '$title. ${plot.isAllZero ? S.statsSeriesAllZero : S.statsSeriesTooShort}',
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The period, before the picture. "Seven bars" with no
                  // stated range is a chart of an unknown week.
                  AppMeta(parts: [
                    AppMetaText(period),
                    AppMetaText(hint),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  if (!plot.isPlottable)
                    Text(
                      plot.isAllZero
                          ? S.statsSeriesAllZero
                          : S.statsSeriesTooShort,
                      style: TextStyle(color: c.ink3, fontSize: 13),
                    )
                  else ...[
                    _Plot(plot: plot, days: days, tone: tone ?? c.primary),
                    const SizedBox(height: AppSpacing.md),
                    // The reading, then the context for it. The old card led
                    // with «الأعلى» — the one number nobody opened the screen
                    // to find out.
                    Text(
                      latest,
                      style: AppTypography.digits(c.ink, size: 20),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _changeSentence(),
                      style: TextStyle(color: c.ink2, fontSize: 12),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppMeta(parts: [
                      AppMetaText('${S.highest} ${_value(plot.high)}'),
                      AppMetaText('${S.average} ${_value(plot.average)}'),
                      AppMetaText(scale),
                    ]),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Plot extends StatelessWidget {
  const _Plot({required this.plot, required this.days, required this.tone});

  final SeriesPlot plot;
  final List<DateTime> days;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // Fixed, and deliberately not scaled with the text: a bar's height
    // carries a value, so scaling the plot area would scale the reading. The
    // day numbers under it grow on their own, which is the part that has to
    // stay legible at 1.6×.
    const height = 88.0;

    return Column(
      children: [
        SizedBox(
          height: height,
          // The ceiling, drawn as well as printed. Without it a bar at 60 %
          // of the domain looks like a bar at 100 % of an unknown one.
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < plot.values.length; i++) ...[
                  Expanded(
                    child: _Bar(
                      fraction: plot.fractionAt(i),
                      // The most recent reading in the full tone; the days
                      // behind it a step back, because they are context.
                      color: i == plot.values.length - 1
                          ? tone
                          : tone.withValues(alpha: 0.45),
                    ),
                  ),
                  if (i != plot.values.length - 1) const SizedBox(width: 6),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        // A day number under every bar. Without them a reader cannot tell
        // which end of the row is today — and in Arabic the row runs
        // right-to-left, so guessing is a coin toss.
        Row(
          children: [
            for (var i = 0; i < days.length; i++) ...[
              Expanded(
                child: Center(
                  child: TabularDigits(
                    AppNumber.count(days[i].day),
                    style: AppTypography.digits(
                      i == days.length - 1 ? c.ink2 : c.ink3,
                      size: 10,
                      weight: i == days.length - 1
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
              if (i != days.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: fraction.clamp(0, 1)),
      duration: effectiveValueDuration(context, MotionTokens.progressFill),
      curve: effectiveCurve(context, MotionTokens.enter),
      builder: (context, v, _) => Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          // A genuine zero keeps a visible 2 % stub so the day is not
          // mistaken for a missing reading — the series as a whole is
          // refused when *every* day is zero.
          heightFactor: v == 0 ? 0.02 : v,
          child: Container(
            decoration: BoxDecoration(
              color: v == 0 ? c.surface3 : color,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
          ),
        ),
      ),
    );
  }
}
