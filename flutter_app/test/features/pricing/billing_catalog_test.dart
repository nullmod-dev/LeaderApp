import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/pricing/data/pricing_catalog.dart';
import 'package:mtm/features/pricing/domain/billing_option.dart';

void main() {
  test('catalog has the four approved prices and durations', () {
    expect(
      kLeaderPricingCatalog.map((option) => option.basePrice.cents),
      [600, 1400, 2400, 4000],
    );
    expect(
      kLeaderPricingCatalog.map((option) => option.months),
      [1, 3, 6, 12],
    );
  });

  test('every duration grants the same full Leader product', () {
    expect(
      kLeaderPricingCatalog.every((option) => option.grantsFullLeaderAccess),
      isTrue,
    );
  });

  test('only one and three months are promotion eligible', () {
    expect(kPromotionEligibleOptions, {
      BillingOptionId.monthly,
      BillingOptionId.threeMonths,
    });
    expect(BillingOptionId.sixMonths.promotionEligible, isFalse);
    expect(BillingOptionId.twelveMonths.promotionEligible, isFalse);
  });

  test('wire parsing fails closed', () {
    expect(
        BillingOptionId.tryParse('three_months'), BillingOptionId.threeMonths);
    expect(BillingOptionId.tryParse('premium'), isNull);
  });
}
