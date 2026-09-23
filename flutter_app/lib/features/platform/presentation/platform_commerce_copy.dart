import '../../pricing/domain/money.dart';
import '../../pricing/domain/promotion.dart';

abstract final class PlatformCommerceCopy {
  static String discountValue(Discount discount) => switch (discount) {
        PercentageDiscount(:final percent) => percent.toString(),
        FixedFinalPriceDiscount(:final finalPrice) => finalPrice.cents % 100 ==
                0
            ? (finalPrice.cents ~/ 100).toString()
            : '${finalPrice.cents ~/ 100}.${(finalPrice.cents % 100).toString().padLeft(2, '0')}',
      };

  /// Parses dollars without ever constructing a floating-point value.
  static Money? fixedPrice(String raw) {
    final clean = raw.trim();
    final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(clean);
    if (match == null) return null;
    final dollars = int.tryParse(match.group(1)!);
    if (dollars == null) return null;
    final fraction = match.group(2);
    final cents = fraction == null
        ? 0
        : int.parse(fraction.length == 1 ? '${fraction}0' : fraction);
    return Money.cents(dollars * 100 + cents);
  }
}
