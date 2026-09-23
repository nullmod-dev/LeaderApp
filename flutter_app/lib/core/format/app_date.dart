import '../motion/animated_counter.dart';
import '../time/calendar_day.dart';

/// Date and time rendering for an Arabic-first UI.
///
/// Written by hand rather than through `intl`'s `DateFormat` because the
/// Arabic date symbols are only loaded once `initializeDateFormatting` has
/// run, and this app must render correctly on its very first frame with no
/// asynchronous setup. The shapes here are the only ones the UI needs.
abstract final class AppDate {
  static const List<String> _months = [
    'كانون الثاني',
    'شباط',
    'آذار',
    'نيسان',
    'أيار',
    'حزيران',
    'تموز',
    'آب',
    'أيلول',
    'تشرين الأول',
    'تشرين الثاني',
    'كانون الأول',
  ];

  /// `١٢ أيلول`
  static String dayMonth(DateTime d) =>
      '${toArabicIndic(d.day.toString())} ${_months[d.month - 1]}';

  /// `١٢ أيلول ٢٠٢٦`
  ///
  /// The year matters wherever a date can be more than a season old — a
  /// subscriber registered two years ago, a lifecycle event from a previous
  /// contract term. The tenant app's own screens deal in the current week and
  /// use [dayMonth]; this is for the records that do not.
  static String dayMonthYear(DateTime d) =>
      '${dayMonth(d)} ${toArabicIndic(d.year.toString())}';

  /// `١٢ أيلول ١٤:٣٠`
  ///
  /// **No separator between the two.** This joined the day to the clock with
  /// ` · ` until the closure pass, and that dot lands immediately before a
  /// time that very often begins with «٠» — the Arabic-Indic zero, which is
  /// the same mark (UI audit P1-11). A space says exactly the same thing and
  /// cannot be read as a numeral. [AppTime.dayTime] is this shape for a
  /// widget, and also isolates the clock; this one stays a plain string
  /// because the PDF exporter has no isolate support.
  static String dayMonthTime(DateTime d) => '${dayMonth(d)} ${time(d)}';

  /// `١٤:٣٠` — always rendered left-to-right by the caller.
  static String time(DateTime d) =>
      '${toArabicIndic(d.hour.toString().padLeft(2, '0'))}:'
      '${toArabicIndic(d.minute.toString().padLeft(2, '0'))}';

  /// Arabic weekday names indexed by `DateTime.weekday` (1 = Monday).
  static const List<String> _weekdays = [
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  /// `السبت` from a `DateTime.weekday` value.
  static String weekdayName(int weekday) => _weekdays[weekday - 1];

  /// `الأحد` from a date.
  static String weekdayOf(DateTime d) => weekdayName(d.weekday);

  /// The conventional one-letter weekday, indexed like [_weekdays]:
  /// `ن ث ر خ ج س ح`.
  ///
  /// **Why a letter and not a prefix.** The schedule's day strip and the
  /// repeat picker both took `weekdayOf(d).substring(0, 2)` to fit seven
  /// columns — and *every* Arabic weekday begins «ال», so all seven columns
  /// drew the same two characters and the row said nothing (found in the
  /// Phase 3C render review). These are the initials an Arabic calendar
  /// already uses, they are distinct from each other, and one glyph fits any
  /// column at any text scale. The full name is never far: the strip's
  /// selected day is spelled out underneath it.
  static const List<String> _weekdayInitials = [
    'ن', // الإثنين
    'ث', // الثلاثاء
    'ر', // الأربعاء
    'خ', // الخميس
    'ج', // الجمعة
    'س', // السبت
    'ح', // الأحد
  ];

  /// `س` from a `DateTime.weekday` value.
  static String weekdayInitial(int weekday) => _weekdayInitials[weekday - 1];

  /// `ح` from a date.
  static String weekdayInitialOf(DateTime d) => weekdayInitial(d.weekday);

  /// `٠٨:٣٠` from minutes since midnight. Minutes past 24h wrap, so a night
  /// shift's end reads as `٠٢:٠٠` rather than `٢٦:٠٠`.
  static String hm(int minutes) {
    final m = minutes % (24 * 60);
    return '${toArabicIndic((m ~/ 60).toString().padLeft(2, '0'))}:'
        '${toArabicIndic((m % 60).toString().padLeft(2, '0'))}';
  }

  /// `٠٨:٠٠ – ١٤:٠٠` from two minute offsets.
  static String minuteRange(int startMinutes, int endMinutes) =>
      '${hm(startMinutes)} – ${hm(endMinutes)}';

  /// `١٢ أيلول – ١٨ أيلول` for a week beginning at [weekStart].
  static String weekRange(DateTime weekStart) => '${dayMonth(weekStart)} – '
      '${dayMonth(addDays(weekStart, 6))}';

  /// `٠٨:٠٠ – ١٤:٠٠` from two whole hours.
  static String hourRange(int startHour, int endHour) =>
      '${toArabicIndic(startHour.toString().padLeft(2, '0'))}:٠٠ – '
      '${toArabicIndic(endHour.toString().padLeft(2, '0'))}:٠٠';

  /// Whole days between now and [d]; negative when [d] is in the past.
  ///
  /// Counted on the calendar: subtracting two local midnights gives 23 or 25
  /// hours across a daylight-saving change, and `inDays` would then round
  /// «غدا» down to «اليوم».
  static int daysFromNow(DateTime d) => calendarDaysBetween(DateTime.now(), d);

  /// `قبل ٣ أيام` / `بعد ٤ أيام` / `اليوم`.
  static String relativeDays(DateTime d) {
    final n = daysFromNow(d);
    if (n == 0) return 'اليوم';
    if (n == 1) return 'غدا';
    if (n == -1) return 'أمس';
    final abs = toArabicIndic(n.abs().toString());
    return n > 0 ? 'بعد $abs يوما' : 'قبل $abs يوما';
  }
}
