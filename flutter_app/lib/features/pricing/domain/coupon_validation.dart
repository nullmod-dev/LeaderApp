import '../../../core/result/result.dart';
import 'billing_option.dart';
import 'coupon_code.dart';
import 'money.dart';
import 'promotion.dart';

abstract final class CouponValidationCodes {
  static const couponNotFound = 'coupon_not_found';
  static const couponDisabled = 'coupon_disabled';
  static const couponExpired = 'coupon_expired';
  static const couponNotAssigned = 'coupon_not_assigned';
  static const couponNotEligible = 'coupon_not_eligible';
  static const couponInvalidPrice = 'coupon_invalid_price';
}

enum CouponValidationMessage {
  invalidOrUnavailable,
  validForAnotherDuration,
  valid,
}

final class CouponResolution {
  const CouponResolution({
    required this.coupon,
    required this.target,
    required this.basePrice,
    required this.finalPrice,
  });

  final Coupon coupon;
  final BillingOptionId target;
  final Money basePrice;
  final Money finalPrice;

  Money get savings => basePrice - finalPrice;
}

/// Pure validation. Reading a coupon never consumes or mutates anything.
Result<CouponResolution> validateCoupon({
  required List<Coupon> coupons,
  required List<BillingOption> catalog,
  required String rawCode,
  required String accountId,
  required BillingOptionId selectedOption,
  required DateTime now,
}) {
  final normalized = normalizeCouponCode(rawCode);
  if (normalized == null) {
    return const Failure('', code: CouponValidationCodes.couponNotFound);
  }

  Coupon? coupon;
  for (final candidate in coupons) {
    if (candidate.code == normalized) {
      coupon = candidate;
      break;
    }
  }
  if (coupon == null) {
    return const Failure('', code: CouponValidationCodes.couponNotFound);
  }
  if (!coupon.enabled) {
    return const Failure('', code: CouponValidationCodes.couponDisabled);
  }
  if (coupon.expiresAt != null &&
      !now.toUtc().isBefore(coupon.expiresAt!.toUtc())) {
    return const Failure('', code: CouponValidationCodes.couponExpired);
  }
  final assignment = coupon.assignment;
  if (assignment is CouponAssignmentAccount &&
      assignment.accountId != accountId) {
    return const Failure('', code: CouponValidationCodes.couponNotAssigned);
  }
  if (!kPromotionEligibleOptions.contains(coupon.target)) {
    return const Failure('', code: CouponValidationCodes.couponNotEligible);
  }
  final option = billingOptionById(catalog, coupon.target);
  if (option == null || !isSaneFor(coupon.discount, option.basePrice)) {
    return const Failure('', code: CouponValidationCodes.couponInvalidPrice);
  }

  return Success(CouponResolution(
    coupon: coupon,
    target: coupon.target,
    basePrice: option.basePrice,
    finalPrice: applyDiscount(coupon.discount, option.basePrice),
  ));
}

CouponValidationMessage couponValidationMessage(
  Result<CouponResolution> result,
  BillingOptionId selectedOption,
) {
  if (result is! Success<CouponResolution>) {
    return CouponValidationMessage.invalidOrUnavailable;
  }
  return result.data.target == selectedOption
      ? CouponValidationMessage.valid
      : CouponValidationMessage.validForAnotherDuration;
}
