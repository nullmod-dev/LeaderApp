import '../../../../core/format/app_date.dart';
import '../../../../core/format/app_time.dart';
import '../../../../core/text/bidi.dart';
import '../../../../core/widgets/app_meta.dart';
import '../../../../l10n/strings.dart';

export '../../../../core/widgets/app_meta.dart' show AppMeta, AppMetaText;

/// The Super Admin surface's metadata line — now the shared one.
///
/// Phase 2 built the hairline separator here, for the platform screens. Phase
/// 3A found the tenant surface carrying the worse instances of the same
/// defect and moved the implementation to `core/widgets/app_meta.dart`,
/// because nothing about a 1 dp rule between two facts is platform-specific
/// and because the dependency can only run one way: a tenant screen may never
/// import `features/platform/`.
///
/// These two names stay so the nine platform pages that already read by them
/// keep reading by them. They are aliases, not copies — there is one
/// implementation, and it is in `core/`.
typedef PlatformMeta = AppMeta;
typedef PlatformMetaText = AppMetaText;

/// The Super Admin surface's timestamp vocabulary.
///
/// **Two clocks, said differently, both in the product's own date shape.**
/// Health and Security report the instant a *snapshot* was taken, which is
/// operationally a UTC fact — two operators in two timezones comparing notes
/// need the same number — so those keep UTC and say so in Arabic. Everything
/// else (an audit event, a demo window, a lifecycle date) is read against the
/// operator's own day and stays local.
///
/// The local shapes are [AppTime]'s and are delegated to it: they were never
/// platform-specific. What is kept here is the UTC pair, because *which
/// clock a record is kept on* is a decision about the record, and only this
/// surface has records kept on the other one.
///
/// Nothing here changes a time *semantically*: what was UTC is still UTC,
/// what was local is still local.
abstract final class PlatformTime {
  /// «٨ أيلول ٢٠٢٦» in the operator's own timezone.
  static String date(DateTime value) => AppTime.date(value);

  /// «١٤:٤٢», isolated so the colon cannot be reordered by the Arabic around
  /// it.
  static String time(DateTime value) => AppTime.time(value);

  /// «٩ أيلول ٠٩:٠٠» — a local day and its clock, with **no separator at
  /// all**, because ` · ` immediately before a time beginning «٠» is two
  /// zeros.
  static String dayTime(DateTime value) => AppTime.dayTime(value);

  /// «٨ أيلول ٢٠٢٦» on the UTC calendar.
  static String utcDate(DateTime value) => AppDate.dayMonthYear(value.toUtc());

  /// «١٥:٠٤ بتوقيت UTC» — the same instant the old string carried, named in
  /// the interface's own language instead of trailing a Latin abbreviation.
  ///
  /// Only the clock is isolated. Wrapping the whole phrase would drag
  /// «بتوقيت» into a left-to-right run and print it after the Latin token.
  static String utcTime(DateTime value) =>
      '${Bidi.ltr(AppDate.time(value.toUtc()))} ${S.platformTimeUtc}';

  /// The whole UTC instant as one sentence, for a semantics label or a
  /// single-line caller that cannot lay out two meta parts.
  static String utcSpoken(DateTime value) =>
      '${utcDate(value)} ${utcTime(value)}';
}
