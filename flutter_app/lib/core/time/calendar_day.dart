/// Calendar-day arithmetic.
///
/// **Why this file exists.** A `Duration` is an exact span of absolute time:
/// `Duration(days: 1)` is always 24 hours. A *local calendar day* is not — on
/// the two days a timezone changes offset it is 23 or 25 hours. So
/// `midnight.add(const Duration(days: 7))` does not land on the next week's
/// midnight in a zone with daylight saving; it lands on 23:00 the day before,
/// or 01:00 the day after.
///
/// That matters here because the app's operational dates are *dates*, not
/// instants: a shift's `date` is local midnight, and the whole schedule
/// compares them with `==` (`s.date == day`). A stray hour makes two values
/// that name the same day stop being equal, and the failure is silent — a
/// copied week quietly loses a day, or lands on the wrong one.
///
/// `DateTime`'s constructor normalizes out-of-range field values, so
/// `DateTime(y, m, d + 7)` is the correct construction: it crosses month and
/// year ends, and it asks for *that calendar day's* midnight rather than for
/// a fixed number of hours later.
///
/// These are local dates on purpose. Converting operational dates to UTC to
/// dodge the problem would change what "the 12th" means for the person
/// working the shift.
library;

/// Local midnight of [d] — the canonical form of an operational date.
///
/// Two values naming the same day must compare equal, and a stray hour on a
/// `DateTime` is exactly how that quietly stops being true.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// [d] moved by [days] **calendar** days, at local midnight.
///
/// The replacement for `d.add(Duration(days: n))` wherever `n` counts days on
/// a calendar rather than 24-hour spans. Negative values move backwards.
DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

/// Whole calendar days from [from] to [to]; negative when [to] is earlier.
///
/// Projected onto UTC before subtracting: a UTC day is always 24 hours, so
/// the division is exact even when the local span between the two midnights
/// is 23 or 25 hours. `dateOnly(a).difference(dateOnly(b)).inDays` is the
/// trap this exists to avoid — across a spring-forward boundary it reports
/// six days between two dates that are seven apart.
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;
