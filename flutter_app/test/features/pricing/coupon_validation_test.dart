import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/pricing/data/pricing_catalog.dart';
import 'package:mtm/features/pricing/domain/billing_option.dart';
import 'package:mtm/features/pricing/domain/coupon_validation.dart';
import 'package:mtm/features/pricing/domain/money.dart';
import 'package:mtm/features/pricing/domain/promotion.dart';

void main() {
  final now = DateTime.utc(2026, 9, 16);

  Coupon coupon({
    String code = 'LEADER10',
    bool enabled = true,
    BillingOptionId target = BillingOptionId.monthly,
    Discount discount = const PercentageDiscount(10),
    CouponAssignment assignment = const CouponAssignmentPublic(),
    DateTime? expiresAt,
  }) =>
      Coupon(
        id: code,
        code: code,
        enabled: enabled,
        target: target,
        discount: discount,
        assignment: assignment,
        createdAt: now,
        expiresAt: expiresAt,
      );

  Result<CouponResolution> validate(
    List<Coupon> coupons, {
    String raw = 'leader10',
    String account = 'acc_1',
    BillingOptionId selected = BillingOptionId.monthly,
  }) =>
      validateCoupon(
        coupons: coupons,
        catalog: kLeaderPricingCatalog,
        rawCode: raw,
        accountId: account,
        selectedOption: selected,
        now: now,
      );

  String? code(Result<CouponResolution> result) =>
      (result as Failure<CouponResolution>).code;

  test('malformed and unknown codes fail as not found', () {
    expect(code(validate([], raw: '؟')), CouponValidationCodes.couponNotFound);
    expect(
        code(validate([], raw: 'ABC')), CouponValidationCodes.couponNotFound);
  });

  test('state checks are ordered before assignment and eligibility', () {
    final disabled = coupon(
      enabled: false,
      assignment: const CouponAssignmentAccount('someone_else'),
      target: BillingOptionId.sixMonths,
    );
    expect(code(validate([disabled])), CouponValidationCodes.couponDisabled);

    final expired = coupon(
      expiresAt: now,
      assignment: const CouponAssignmentAccount('someone_else'),
    );
    expect(code(validate([expired])), CouponValidationCodes.couponExpired);
  });

  test('targeted coupon accepts only its account identity', () {
    final targeted = coupon(
      assignment: const CouponAssignmentAccount('acc_right'),
    );
    expect(
      code(validate([targeted], account: 'acc_wrong')),
      CouponValidationCodes.couponNotAssigned,
    );
    expect(validate([targeted], account: 'acc_right'),
        isA<Success<CouponResolution>>());
  });

  test('ineligible target and invalid price keep distinct domain codes', () {
    expect(
      code(validate([coupon(target: BillingOptionId.sixMonths)])),
      CouponValidationCodes.couponNotEligible,
    );
    expect(
      code(validate([
        coupon(discount: const FixedFinalPriceDiscount(Money.zero)),
      ])),
      CouponValidationCodes.couponInvalidPrice,
    );
  });

  test('valid result is normalized and calculates but never mutates', () {
    final item = coupon();
    final result =
        validate([item], raw: ' leader 10 ') as Success<CouponResolution>;
    expect(result.data.finalPrice, const Money.cents(540));
    expect(result.data.savings, const Money.cents(60));
    expect(item.enabled, isTrue);
  });

  test('seven rules collapse to approved user message categories', () {
    expect(
      couponValidationMessage(
          validate([], raw: 'ABC'), BillingOptionId.monthly),
      CouponValidationMessage.invalidOrUnavailable,
    );
    final valid = validate([coupon()]);
    expect(
      couponValidationMessage(valid, BillingOptionId.threeMonths),
      CouponValidationMessage.validForAnotherDuration,
    );
    expect(
      couponValidationMessage(valid, BillingOptionId.monthly),
      CouponValidationMessage.valid,
    );
  });
}
