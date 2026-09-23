import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../auth/data/auth_providers.dart';
import '../domain/billing_option.dart';
import '../domain/coupon_validation.dart';
import '../domain/price_quote.dart';
import '../domain/promotion.dart';
import 'commerce_control_plane.dart';
import 'pricing_catalog.dart';

final liveGlobalOffersProvider =
    Provider<Map<BillingOptionId, GlobalOffer>>((ref) {
  final state = ref.watch(commerceControlPlaneProvider);
  final now = ref.watch(clockProvider)();
  return Map.unmodifiable({
    for (final option in kPromotionEligibleOptions)
      if (state.liveOfferFor(option, now) case final offer?) option: offer,
  });
});

enum CouponPhase { idle, validating, done }

final class CouponEntryState {
  const CouponEntryState({
    this.input = '',
    this.phase = CouponPhase.idle,
    this.last,
  });

  final String input;
  final CouponPhase phase;
  final Result<CouponResolution>? last;

  CouponEntryState copyWith({
    String? input,
    CouponPhase? phase,
    Result<CouponResolution>? last,
    bool clearLast = false,
  }) =>
      CouponEntryState(
        input: input ?? this.input,
        phase: phase ?? this.phase,
        last: clearLast ? null : last ?? this.last,
      );
}

class CouponEntry extends Notifier<CouponEntryState> {
  @override
  CouponEntryState build() => const CouponEntryState();

  void setInput(String input) {
    state = CouponEntryState(input: input);
  }

  void clear() => state = const CouponEntryState();

  Future<void> validate() async {
    if (state.input.trim().isEmpty || state.phase == CouponPhase.validating) {
      return;
    }
    state = state.copyWith(phase: CouponPhase.validating, clearLast: true);
    // Preserve an observable validating frame. The future backend adapter will
    // naturally occupy this seam without changing the widget state machine.
    await Future<void>.delayed(Duration.zero);
    final user = ref.read(currentUserProvider).valueOrNull;
    final result = validateCoupon(
      coupons: ref.read(commerceControlPlaneProvider).coupons,
      catalog: ref.read(pricingCatalogProvider),
      rawCode: state.input,
      accountId: user?.id ?? '',
      selectedOption: ref.read(selectedBillingOptionProvider),
      now: ref.read(clockProvider)(),
    );
    state = state.copyWith(phase: CouponPhase.done, last: result);
  }
}

final couponEntryProvider =
    NotifierProvider<CouponEntry, CouponEntryState>(CouponEntry.new);

final selectedBillingOptionProvider =
    StateProvider<BillingOptionId>((ref) => BillingOptionId.twelveMonths);

final pricingResolutionProvider = Provider<PricingResolution>((ref) {
  final entry = ref.watch(couponEntryProvider);
  final last = entry.last;
  final coupon = last is Success<CouponResolution> ? last.data : null;
  return resolvePriceQuotes(
    catalog: ref.watch(pricingCatalogProvider),
    liveGlobalOffers: ref.watch(liveGlobalOffersProvider),
    coupon: coupon,
  );
});

final priceQuotesProvider = Provider<List<PriceQuote>>(
  (ref) => ref.watch(pricingResolutionProvider).quotes,
);
