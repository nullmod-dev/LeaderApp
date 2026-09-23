/// Arabic copy for the Customer Demo control plane.
///
/// **Durations are spoken, not printed.** An operator sets a trial window in
/// the units they think in — «يوم واحد», «٤٨ ساعة» — and Arabic marks one, two
/// and few differently from many. Rendering `24h` or «24 ساعات» would be the
/// kind of wrong that reads as machine output; the plural rules below are the
/// whole reason this file exists rather than an interpolation at each call
/// site.
library;

import '../../../core/motion/animated_counter.dart' show toArabicIndic;
import '../../demo/domain/demo_policy.dart';
import '../../../l10n/strings.dart';

abstract final class PlatformDemoCopy {
  /// A window, in the largest unit that divides it exactly.
  ///
  /// 24 hours is «يوم واحد», not «٢٤ ساعة»: the product default is a *day*, and
  /// an operator who set a day should read back a day. Anything not a whole
  /// number of days stays in hours, because «يوم ونصف» is a sentence, not a
  /// value in a stepper.
  static String duration(Duration value) {
    final hours = value.inHours;
    if (hours >= 24 && hours % 24 == 0) return _days(hours ~/ 24);
    return _hours(hours);
  }

  /// How much of a window is left, rounded **down** to a whole unit.
  ///
  /// Down, never up: «ساعة واحدة» on a trial with fifty-nine minutes left is a
  /// promise; «أقل من ساعة» is what is actually true.
  static String remaining(Duration value) {
    if (value <= Duration.zero) return S.platformDemoSessionEndsSoon;
    if (value.inHours < 1) {
      final minutes = value.inMinutes;
      return minutes < 1 ? S.platformDemoSessionEndsSoon : _minutes(minutes);
    }
    return duration(Duration(hours: value.inHours));
  }

  static String sessionStatus(DemoSessionStatus status) => switch (status) {
        DemoSessionStatus.active => S.platformDemoCountActive,
        DemoSessionStatus.expired => S.platformDemoCountExpired,
        DemoSessionStatus.terminated => S.platformDemoCountTerminated,
      };

  /// Arabic counts its first two separately, then splits few from many at
  /// eleven. One helper per unit, because the singular and dual forms are
  /// different words rather than a suffix.
  static String _days(int n) => switch (n) {
        1 => 'يوم واحد',
        2 => 'يومان',
        <= 10 => '${toArabicIndic('$n')} أيام',
        _ => '${toArabicIndic('$n')} يوما',
      };

  static String _hours(int n) => switch (n) {
        1 => 'ساعة واحدة',
        2 => 'ساعتان',
        <= 10 => '${toArabicIndic('$n')} ساعات',
        _ => '${toArabicIndic('$n')} ساعة',
      };

  static String _minutes(int n) => switch (n) {
        1 => 'دقيقة واحدة',
        2 => 'دقيقتان',
        <= 10 => '${toArabicIndic('$n')} دقائق',
        _ => '${toArabicIndic('$n')} دقيقة',
      };

  /// What a bare count chip *means*, for a screen reader.
  ///
  /// The chip itself is a numeral, because a control-panel badge has to stay
  /// narrow enough to sit in a navigation row at a 1.6 text scale. Spoken, a
  /// lone «١» says nothing, so the row supplies this instead.
  static String activeSessions(int n) => switch (n) {
        1 => 'جلسة تجريبية نشطة واحدة',
        2 => 'جلستان تجريبيتان نشطتان',
        <= 10 => '${toArabicIndic('$n')} جلسات تجريبية نشطة',
        _ => '${toArabicIndic('$n')} جلسة تجريبية نشطة',
      };

  /// The same, for the commerce row's count of live offers and coupons.
  static String livePromotions(int n) => switch (n) {
        1 => 'عرض أو كوبون مفعّل واحد',
        2 => 'عرضان أو كوبونان مفعّلان',
        <= 10 => '${toArabicIndic('$n')} عروض أو كوبونات مفعّلة',
        _ => '${toArabicIndic('$n')} عرضا أو كوبونا مفعّلا',
      };

  /// `%d` filled with Arabic-Indic digits, the pattern the rest of the app
  /// already uses for a count inside a sentence.
  static String count(String template, int n) =>
      template.replaceFirst('%d', toArabicIndic('$n'));
}
