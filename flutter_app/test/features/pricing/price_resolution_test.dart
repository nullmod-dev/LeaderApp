import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/pricing/data/pricing_catalog.dart';
import 'package:mtm/features/pricing/domain/billing_option.dart';
import 'package:mtm/features/pricing/domain/coupon_validation.dart';
import 'package:mtm/features/pricing/domain/money.dart';
import 'package:mtm/features/pricing/domain/price_quote.dart';
import 'package:mtm/features/pricing/domain/promotion.dart';

void main() {
  final now = DateTime.utc(2026, 9, 16);

  GlobalOffer offer(Discount discount, {BillingOptionId? target}) =>
      GlobalOffer(
        id: 'offer',
        enabled: true,
        target: target ?? BillingOptionId.monthly,
        discount: discount,
        createdAt: now,
        title: 'عرض خاص',
      );

  CouponResolution coupon(Money price) {
    final item = Coupon(
      id: 'coupon',
      code: 'TRY2',
      enabled: true,
      target: BillingOptionId.monthly,
      discount: FixedFinalPriceDiscount(price),
      assignment: const CouponAssignmentPublic(),
      createdAt: now,
    );
    return CouponResolution(
      coupon: item,
      target: BillingOptionId.monthly,
      basePrice: const Money.cents(600),
      finalPrice: price,
    );
  }

  PriceQuote monthly(PricingResolution resolution) => resolution.quotes
      .firstWhere((q) => q.option.id == BillingOptionId.monthly);

  test('no promotion produces plain base quotes', () {
    final result = resolvePriceQuotes(
      catalog: kLeaderPricingCatalog,
      liveGlobalOffers: const {},
    );
    expect(
        result.quotes.map((q) => q.finalPrice.cents), [600, 1400, 2400, 4000]);
    expect(result.quotes.every((q) => q.promotion == null), isTrue);
  });

  test('no stacking: best final price wins', () {
    final result = resolvePriceQuotes(
      catalog: kLeaderPricingCatalog,
      liveGlobalOffers: {
        BillingOptionId.monthly: offer(const PercentageDiscount(10)),
      },
      coupon: coupon(const Money.cents(200)),
    );
    expect(monthly(result).finalPrice, const Money.cents(200));
    expect(monthly(result).promotion!.source, PromotionSource.coupon);
    expect(result.couponOutcome, CouponPriceOutcome.applied);
  });

  test('global offer wins a tie and reports a worse coupon state', () {
    for (final price in [540, 550]) {
      final result = resolvePriceQuotes(
        catalog: kLeaderPricingCatalog,
        liveGlobalOffers: {
          BillingOptionId.monthly: offer(const PercentageDiscount(10)),
        },
        coupon: coupon(Money.cents(price)),
      );
      expect(monthly(result).finalPrice, const Money.cents(540));
      expect(monthly(result).promotion!.source, PromotionSource.globalOffer);
      expect(result.couponOutcome, CouponPriceOutcome.globalOfferIsBetter);
    }
  });

  test('ineligible durations cannot be discounted', () {
    final result = resolvePriceQuotes(
      catalog: kLeaderPricingCatalog,
      liveGlobalOffers: {
        BillingOptionId.sixMonths: offer(
          const PercentageDiscount(20),
          target: BillingOptionId.sixMonths,
        ),
      },
    );
    final six = result.quotes
        .firstWhere((q) => q.option.id == BillingOptionId.sixMonths);
    expect(six.finalPrice, six.basePrice);
    expect(six.promotion, isNull);
  });
}
