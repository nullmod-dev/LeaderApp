import 'billing_option.dart';
import 'coupon_validation.dart';
import 'money.dart';
import 'promotion.dart';

enum PromotionSource { globalOffer, coupon }

final class AppliedPromotion {
  const AppliedPromotion({
    required this.source,
    required this.displayLabel,
    this.code,
  });

  final PromotionSource source;
  final String displayLabel;
  final String? code;
}

final class PriceQuote {
  const PriceQuote({
    required this.option,
    required this.basePrice,
    required this.finalPrice,
    required this.durationSavings,
    this.promotion,
  });

  final BillingOption option;
  final Money basePrice;
  final Money finalPrice;
  final AppliedPromotion? promotion;
  final Money durationSavings;

  Money get promotionSavings => basePrice - finalPrice;
  Money get effectiveMonthly =>
      effectiveMonthlyPrice(finalPrice, option.months);
}

enum CouponPriceOutcome { none, applied, globalOfferIsBetter }

final class PricingResolution {
  const PricingResolution({required this.quotes, required this.couponOutcome});

  final List<PriceQuote> quotes;
  final CouponPriceOutcome couponOutcome;
}

/// Resolves one quote per option. Promotions are alternatives, never a chain.
PricingResolution resolvePriceQuotes({
  required List<BillingOption> catalog,
  required Map<BillingOptionId, GlobalOffer> liveGlobalOffers,
  CouponResolution? coupon,
}) {
  final monthly = catalog.where((o) => o.id == BillingOptionId.monthly).first;
  var couponOutcome = CouponPriceOutcome.none;
  final quotes = <PriceQuote>[];

  for (final option in catalog) {
    Money finalPrice = option.basePrice;
    AppliedPromotion? applied;

    final offer = liveGlobalOffers[option.id];
    if (offer != null &&
        option.id.promotionEligible &&
        isSaneFor(offer.discount, option.basePrice)) {
      finalPrice = applyDiscount(offer.discount, option.basePrice);
      applied = AppliedPromotion(
        source: PromotionSource.globalOffer,
        displayLabel: offer.title ?? 'global_offer',
      );
    }

    if (coupon != null && coupon.target == option.id) {
      if (applied == null || coupon.finalPrice < finalPrice) {
        finalPrice = coupon.finalPrice;
        applied = AppliedPromotion(
          source: PromotionSource.coupon,
          displayLabel: coupon.coupon.code,
          code: coupon.coupon.code,
        );
        couponOutcome = CouponPriceOutcome.applied;
      } else {
        // Equality deliberately stays with the global offer.
        couponOutcome = CouponPriceOutcome.globalOfferIsBetter;
      }
    }

    quotes.add(PriceQuote(
      option: option,
      basePrice: option.basePrice,
      finalPrice: finalPrice,
      promotion: applied,
      durationSavings: durationSavings(
        monthlyBase: monthly.basePrice,
        months: option.months,
        effectivePrice: finalPrice,
      ),
    ));
  }

  return PricingResolution(
    quotes: List.unmodifiable(quotes),
    couponOutcome: couponOutcome,
  );
}
