import '../../../core/format/app_date.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../l10n/strings.dart';

/// Shared wording for device trust: a moment, and a count of days.
abstract final class DeviceTrustCopy {
  /// `١٢ أيلول ١٤:٣٠`, local time; the clock isolated left-to-right.
  static String moment(DateTime value) {
    final local = value.toLocal();
    return '${AppDate.dayMonth(local)} \u2066${AppDate.time(local)}\u2069';
  }

  /// «أقل من يوم» · «يوم واحد» · «يومان» · «٣ أيام» … — whole days left,
  /// counted down from [remaining].
  static String days(Duration remaining) {
    final days = remaining.inDays;
    if (days <= 0) return S.daysLessThanOne;
    if (days == 1) return S.daysOne;
    if (days == 2) return S.daysTwo;
    return S.daysFew.replaceFirst('%s', toArabicIndic('$days'));
  }
}
