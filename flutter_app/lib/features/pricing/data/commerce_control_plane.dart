/// DEVELOPMENT AND TEST ONLY commercial control plane.
///
/// State lives only in process memory. It is not production persistence,
/// payment authority, coupon redemption, or subscription activation. A future
/// backend adapter replaces this provider wholesale.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../domain/billing_option.dart';
import '../domain/coupon_code.dart';
import '../domain/money.dart';
import '../domain/promotion.dart';
import 'pricing_catalog.dart';

final class CommerceActor {
  const CommerceActor({required this.accountId, required this.displayName});

  final String accountId;
  final String displayName;
}

final class CommerceState {
  const CommerceState({required this.offers, required this.coupons});

  final List<GlobalOffer> offers;
  final List<Coupon> coupons;

  GlobalOffer? offerById(String id) {
    for (final offer in offers) {
      if (offer.id == id) return offer;
    }
    return null;
  }

  GlobalOffer? liveOfferFor(BillingOptionId option, DateTime now) {
    for (final offer in offers) {
      if (offer.target == option && offer.isLiveAt(now)) return offer;
    }
    return null;
  }

  Coupon? couponById(String id) {
    for (final coupon in coupons) {
      if (coupon.id == id) return coupon;
    }
    return null;
  }

  Coupon? couponByCode(String normalizedCode) {
    for (final coupon in coupons) {
      if (coupon.code == normalizedCode) return coupon;
    }
    return null;
  }

  CommerceState copyWith({
    List<GlobalOffer>? offers,
    List<Coupon>? coupons,
  }) =>
      CommerceState(
        offers: offers ?? this.offers,
        coupons: coupons ?? this.coupons,
      );
}

abstract final class CommerceCodes {
  static const notAuthorized = 'not_authorized';
  static const offerNotFound = 'offer_not_found';
  static const offerConflict = 'offer_conflict';
  static const couponNotFound = 'coupon_not_found';
  static const couponCodeTaken = 'coupon_code_taken';
  static const couponCodeInvalid = 'coupon_code_invalid';
  static const promotionInvalid = 'promotion_invalid';
}

final commerceControlPlaneSeedProvider = Provider<CommerceState>((ref) {
  final now = ref.watch(clockProvider)().toUtc();
  return CommerceState(
    offers: List.unmodifiable([
      GlobalOffer(
        id: 'offer_seed_try2',
        enabled: false,
        target: BillingOptionId.monthly,
        discount: const FixedFinalPriceDiscount(Money.cents(200)),
        createdAt: now.subtract(const Duration(days: 3)),
        title: 'جرّب أول شهر بـ \$2',
      ),
    ]),
    coupons: List.unmodifiable([
      Coupon(
        id: 'coupon_seed_public',
        code: 'LEADER10',
        enabled: false,
        target: BillingOptionId.threeMonths,
        discount: const PercentageDiscount(10),
        assignment: const CouponAssignmentPublic(),
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      Coupon(
        id: 'coupon_seed_targeted',
        code: 'TRY2',
        enabled: false,
        target: BillingOptionId.monthly,
        discount: const FixedFinalPriceDiscount(Money.cents(200)),
        assignment: const CouponAssignmentAccount('u_demo_main'),
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    ]),
  );
});

class CommerceControlPlane extends Notifier<CommerceState> {
  int _sequence = 0;

  @override
  CommerceState build() {
    final seed = ref.watch(commerceControlPlaneSeedProvider);
    return CommerceState(
      offers: List.unmodifiable(seed.offers),
      coupons: List.unmodifiable(seed.coupons),
    );
  }

  DateTime get _now => ref.read(clockProvider)().toUtc();
  List<BillingOption> get _catalog => ref.read(pricingCatalogProvider);

  Result<GlobalOffer> createOffer({
    required BillingOptionId target,
    required Discount discount,
    bool enabled = false,
    String? title,
    DateTime? endsAt,
    CommerceActor? actor,
  }) {
    if (actor == null) return _unauthorized();
    final invalid = _validatePromotion<GlobalOffer>(target, discount);
    if (invalid != null) return invalid;
    if (enabled && state.liveOfferFor(target, _now) != null) {
      return const Failure('', code: CommerceCodes.offerConflict);
    }
    final offer = GlobalOffer(
      id: 'offer_${_now.microsecondsSinceEpoch}_${_sequence++}',
      enabled: enabled,
      target: target,
      discount: discount,
      createdAt: _now,
      title: _cleanOptional(title),
      endsAt: endsAt?.toUtc(),
    );
    state = state.copyWith(offers: List.unmodifiable([offer, ...state.offers]));
    return Success(offer);
  }

  Result<GlobalOffer> updateOffer(
    String id, {
    required BillingOptionId target,
    required Discount discount,
    required bool enabled,
    String? title,
    DateTime? endsAt,
    CommerceActor? actor,
  }) {
    if (actor == null) return _unauthorized();
    final existing = state.offerById(id);
    if (existing == null) {
      return const Failure('', code: CommerceCodes.offerNotFound);
    }
    final invalid = _validatePromotion<GlobalOffer>(target, discount);
    if (invalid != null) return invalid;
    if (enabled && _hasOtherLiveOffer(target, id)) {
      return const Failure('', code: CommerceCodes.offerConflict);
    }
    final updated = GlobalOffer(
      id: existing.id,
      enabled: enabled,
      target: target,
      discount: discount,
      createdAt: existing.createdAt,
      title: _cleanOptional(title),
      endsAt: endsAt?.toUtc(),
    );
    state = state.copyWith(
      offers: List.unmodifiable([
        for (final offer in state.offers)
          if (offer.id == id) updated else offer,
      ]),
    );
    return Success(updated);
  }

  Result<GlobalOffer> setOfferEnabled(
    String id,
    bool enabled, {
    CommerceActor? actor,
  }) {
    if (actor == null) return _unauthorized();
    final existing = state.offerById(id);
    if (existing == null) {
      return const Failure('', code: CommerceCodes.offerNotFound);
    }
    if (enabled && _hasOtherLiveOffer(existing.target, id)) {
      return const Failure('', code: CommerceCodes.offerConflict);
    }
    return updateOffer(
      id,
      target: existing.target,
      discount: existing.discount,
      enabled: enabled,
      title: existing.title,
      endsAt: existing.endsAt,
      actor: actor,
    );
  }

  Result<GlobalOffer> removeOffer(String id, {CommerceActor? actor}) {
    if (actor == null) return _unauthorized();
    final existing = state.offerById(id);
    if (existing == null) {
      return const Failure('', code: CommerceCodes.offerNotFound);
    }
    state = state.copyWith(
      offers: List.unmodifiable(state.offers.where((offer) => offer.id != id)),
    );
    return Success(existing);
  }

  Result<Coupon> createCoupon({
    required String code,
    required BillingOptionId target,
    required Discount discount,
    required CouponAssignment assignment,
    bool enabled = false,
    String? note,
    DateTime? expiresAt,
    CommerceActor? actor,
  }) {
    if (actor == null) return _unauthorized();
    final normalized = normalizeCouponCode(code);
    if (normalized == null) {
      return const Failure('', code: CommerceCodes.couponCodeInvalid);
    }
    if (state.couponByCode(normalized) != null) {
      return const Failure('', code: CommerceCodes.couponCodeTaken);
    }
    final invalid = _validatePromotion<Coupon>(target, discount);
    if (invalid != null) return invalid;
    if (assignment is CouponAssignmentAccount &&
        assignment.accountId.trim().isEmpty) {
      return const Failure('', code: CommerceCodes.promotionInvalid);
    }
    final coupon = Coupon(
      id: 'coupon_${_now.microsecondsSinceEpoch}_${_sequence++}',
      code: normalized,
      enabled: enabled,
      target: target,
      discount: discount,
      assignment: assignment,
      createdAt: _now,
      note: _cleanOptional(note),
      expiresAt: expiresAt?.toUtc(),
    );
    state =
        state.copyWith(coupons: List.unmodifiable([coupon, ...state.coupons]));
    return Success(coupon);
  }

  Result<Coupon> updateCoupon(
    String id, {
    required String code,
    required BillingOptionId target,
    required Discount discount,
    required CouponAssignment assignment,
    required bool enabled,
    String? note,
    DateTime? expiresAt,
    CommerceActor? actor,
  }) {
    if (actor == null) return _unauthorized();
    final existing = state.couponById(id);
    if (existing == null) {
      return const Failure('', code: CommerceCodes.couponNotFound);
    }
    final normalized = normalizeCouponCode(code);
    if (normalized == null) {
      return const Failure('', code: CommerceCodes.couponCodeInvalid);
    }
    final sameCode = state.couponByCode(normalized);
    if (sameCode != null && sameCode.id != id) {
      return const Failure('', code: CommerceCodes.couponCodeTaken);
    }
    final invalid = _validatePromotion<Coupon>(target, discount);
    if (invalid != null) return invalid;
    if (assignment is CouponAssignmentAccount &&
        assignment.accountId.trim().isEmpty) {
      return const Failure('', code: CommerceCodes.promotionInvalid);
    }
    final updated = Coupon(
      id: existing.id,
      code: normalized,
      enabled: enabled,
      target: target,
      discount: discount,
      assignment: assignment,
      createdAt: existing.createdAt,
      note: _cleanOptional(note),
      expiresAt: expiresAt?.toUtc(),
    );
    state = state.copyWith(
      coupons: List.unmodifiable([
        for (final coupon in state.coupons)
          if (coupon.id == id) updated else coupon,
      ]),
    );
    return Success(updated);
  }

  Result<Coupon> setCouponEnabled(
    String id,
    bool enabled, {
    CommerceActor? actor,
  }) {
    if (actor == null) return _unauthorized();
    final existing = state.couponById(id);
    if (existing == null) {
      return const Failure('', code: CommerceCodes.couponNotFound);
    }
    return updateCoupon(
      id,
      code: existing.code,
      target: existing.target,
      discount: existing.discount,
      assignment: existing.assignment,
      enabled: enabled,
      note: existing.note,
      expiresAt: existing.expiresAt,
      actor: actor,
    );
  }

  Result<Coupon> removeCoupon(String id, {CommerceActor? actor}) {
    if (actor == null) return _unauthorized();
    final existing = state.couponById(id);
    if (existing == null) {
      return const Failure('', code: CommerceCodes.couponNotFound);
    }
    state = state.copyWith(
      coupons:
          List.unmodifiable(state.coupons.where((coupon) => coupon.id != id)),
    );
    return Success(existing);
  }

  bool _hasOtherLiveOffer(BillingOptionId target, String id) =>
      state.offers.any((offer) =>
          offer.id != id && offer.target == target && offer.isLiveAt(_now));

  Failure<T>? _validatePromotion<T>(
    BillingOptionId target,
    Discount discount,
  ) {
    final option = billingOptionById(_catalog, target);
    if (!target.promotionEligible ||
        option == null ||
        !isSaneFor(discount, option.basePrice)) {
      return const Failure('', code: CommerceCodes.promotionInvalid);
    }
    return null;
  }

  Failure<T> _unauthorized<T>() =>
      const Failure('', code: CommerceCodes.notAuthorized);

  String? _cleanOptional(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }
}

final commerceControlPlaneProvider =
    NotifierProvider<CommerceControlPlane, CommerceState>(
  CommerceControlPlane.new,
);
