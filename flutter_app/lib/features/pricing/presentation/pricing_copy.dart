import '../../../core/format/app_number.dart';
import '../../../l10n/strings.dart';
import '../domain/billing_option.dart';
import '../domain/promotion.dart';

abstract final class PricingCopy {
  static String duration(BillingOptionId id) => switch (id) {
        BillingOptionId.monthly => S.pricingOneMonth,
        BillingOptionId.threeMonths => S.pricingThreeMonths,
        BillingOptionId.sixMonths => S.pricingSixMonths,
        BillingOptionId.twelveMonths => S.pricingTwelveMonths,
      };

  static String promotion(Discount discount, {String? title}) {
    final clean = title?.trim();
    if (clean != null && clean.isNotEmpty) return clean;
    return switch (discount) {
      PercentageDiscount(:final percent) => AppNumber.percent(percent),
      FixedFinalPriceDiscount() => S.pricingSpecialOffer,
    };
  }
}
