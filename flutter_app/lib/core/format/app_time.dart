import '../text/bidi.dart';
import 'app_date.dart';

/// The app's one timestamp vocabulary.
///
/// **What this owns and what it does not.** [AppDate] knows the *shapes* —
/// which month names, which order, which numerals. `AppTime` knows how those
/// shapes are allowed to appear inside an Arabic sentence: which parts are
/// isolated, and what joins a day to a clock.
///
/// **Presentation only.** Nothing here converts between clocks beyond calling
/// `toLocal()` on a value the caller has already decided is a local instant.
/// A timestamp that is semantically UTC — a snapshot taken for two operators
/// in two timezones to compare — stays UTC and is rendered by the surface
/// that owns that meaning (`PlatformTime.utcDate` / `.utcTime`). An instant
/// is never silently reinterpreted.
///
/// **The separator that is not here.** Nothing in this vocabulary prints a
/// mark between a day and a clock: a ` · ` lands immediately before a time
/// that very often begins with «٠» — the Arabic-Indic zero, which is the
/// same mark (UI audit P1-11). [dayTime] uses a space, and so does
/// `AppDate.dayMonthTime`, which was the last helper still printing the dot
/// until the closure pass. Facts that need a visible break between them use
/// `AppMeta`, which draws a hairline outside the text run rather than
/// printing any character at all.
abstract final class AppTime {
  /// `١٢ أيلول` in the reader's own timezone.
  static String day(DateTime value) => AppDate.dayMonth(value.toLocal());

  /// `١٢ أيلول ٢٠٢٦` — for a record that can be more than a season old.
  static String date(DateTime value) => AppDate.dayMonthYear(value.toLocal());

  /// `السبت ١٢ أيلول` — the weekday and the day, which are one fact and
  /// therefore carry no separator between them.
  static String weekdayDay(DateTime value) {
    final local = value.toLocal();
    return '${AppDate.weekdayOf(local)} ${AppDate.dayMonth(local)}';
  }

  /// `١٤:٣٠`, isolated so the colon cannot be reordered by the Arabic around
  /// it.
  static String time(DateTime value) => Bidi.ltr(AppDate.time(value.toLocal()));

  /// `١٢ أيلول ١٤:٣٠` — a day and its clock, with no separator at all.
  static String dayTime(DateTime value) => '${day(value)} ${time(value)}';

  /// `٠٨:٠٠ – ١٤:٠٠` from two minute offsets, isolated as one span: a range
  /// read right-to-left would put the end time first.
  static String minuteRange(int startMinutes, int endMinutes) =>
      Bidi.ltr(AppDate.minuteRange(startMinutes, endMinutes));

  /// `٠٨:٠٠ – ١٤:٠٠` from two instants, or just the first when the second has
  /// not happened yet. One isolate around the pair, not one around each: two
  /// isolates with a dash between them let the dash resolve against the
  /// Arabic and swap which end of the range it belongs to.
  static String clockRange(DateTime start, DateTime? end) {
    final from = AppDate.time(start.toLocal());
    if (end == null) return Bidi.ltr(from);
    return Bidi.ltr('$from – ${AppDate.time(end.toLocal())}');
  }
}
