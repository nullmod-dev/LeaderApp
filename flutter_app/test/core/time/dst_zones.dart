/// Finds the daylight-saving transitions of the timezone the test process
/// was started in, without adding a timezone package.
///
/// Dart's `DateTime` already knows the host zone's rules; what it does not
/// offer is "when does the offset change". Walking a few years of local
/// midnights and comparing consecutive UTC offsets answers that with no new
/// dependency, and it means the DST tests exercise whatever zone CI or a
/// developer happens to run under rather than a hard-coded pair of dates that
/// would silently stop being transitions when the rules change.
library;

/// Local midnights of the days on which the local UTC offset changes,
/// between [fromYear] and [toYear] inclusive. Empty in a zone with no
/// daylight saving (UTC, Asia/Baghdad, Asia/Damascus since 2022).
///
/// Both kinds are reported: spring-forward (a 23-hour day) and fall-back (a
/// 25-hour day).
List<DateTime> localDstTransitions({
  int fromYear = 2025,
  int toYear = 2028,
}) {
  final out = <DateTime>[];
  var day = DateTime(fromYear);
  final end = DateTime(toYear + 1);
  var offset = day.timeZoneOffset;
  while (day.isBefore(end)) {
    final next = DateTime(day.year, day.month, day.day + 1);
    final nextOffset = next.timeZoneOffset;
    if (nextOffset != offset) {
      // The change happens during `day` (a spring-forward local midnight can
      // itself be skipped in a handful of zones; `DateTime` still resolves
      // it, and the day either side is what the schedule cares about).
      out.add(day);
      offset = nextOffset;
    }
    day = next;
  }
  return out;
}

/// The whole-hour span of the local day beginning at [day], in hours.
/// 23 on a spring-forward day, 25 on a fall-back day, 24 otherwise.
int localDayHours(DateTime day) => DateTime(day.year, day.month, day.day + 1)
    .difference(DateTime(day.year, day.month, day.day))
    .inHours;

/// One spring-forward day and one fall-back day, when the local zone has
/// them — the two representative boundaries, rather than every transition in
/// a four-year window.
///
/// The repository under test simulates network latency, so a loop over a
/// dozen transitions is a minute of wall clock for no extra coverage: the
/// rule being tested has exactly two shapes.
List<DateTime> representativeDstTransitions() {
  DateTime? forward;
  DateTime? back;
  for (final day in localDstTransitions()) {
    final hours = localDayHours(day);
    if (hours < 24) forward ??= day;
    if (hours > 24) back ??= day;
    if (forward != null && back != null) break;
  }
  return [if (forward != null) forward, if (back != null) back];
}
