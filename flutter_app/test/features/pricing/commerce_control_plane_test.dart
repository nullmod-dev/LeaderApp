import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/pricing/data/commerce_control_plane.dart';
import 'package:mtm/features/pricing/domain/billing_option.dart';
import 'package:mtm/features/pricing/domain/money.dart';
import 'package:mtm/features/pricing/domain/promotion.dart';

void main() {
  final now = DateTime.utc(2026, 9, 16, 12);
  const actor = CommerceActor(accountId: 'sa_1', displayName: 'Super Admin');

  ProviderContainer container({CommerceState? seed}) {
    final result = ProviderContainer(overrides: [
      clockProvider.overrideWithValue(() => now),
      if (seed != null)
        commerceControlPlaneSeedProvider.overrideWithValue(seed),
    ]);
    addTearDown(result.dispose);
    return result;
  }

  const empty = CommerceState(offers: [], coupons: []);

  test('default seed is reviewable but entirely disabled', () {
    final state = container().read(commerceControlPlaneProvider);
    expect(state.offers, isNotEmpty);
    expect(state.coupons.length, greaterThanOrEqualTo(2));
    expect(state.offers.every((offer) => !offer.enabled), isTrue);
    expect(state.coupons.every((coupon) => !coupon.enabled), isTrue);
  });

  test('every mutation refuses a missing actor without changing state', () {
    final scope = container(seed: empty);
    final plane = scope.read(commerceControlPlaneProvider.notifier);
    final before = scope.read(commerceControlPlaneProvider);
    final results = <Result<Object?>>[
      plane.createOffer(
        target: BillingOptionId.monthly,
        discount: const PercentageDiscount(10),
      ),
      plane.updateOffer(
        'missing',
        target: BillingOptionId.monthly,
        discount: const PercentageDiscount(10),
        enabled: false,
      ),
      plane.setOfferEnabled('missing', true),
      plane.removeOffer('missing'),
      plane.createCoupon(
        code: 'CODE10',
        target: BillingOptionId.monthly,
        discount: const PercentageDiscount(10),
        assignment: const CouponAssignmentPublic(),
      ),
      plane.updateCoupon(
        'missing',
        code: 'CODE10',
        target: BillingOptionId.monthly,
        discount: const PercentageDiscount(10),
        assignment: const CouponAssignmentPublic(),
        enabled: false,
      ),
      plane.setCouponEnabled('missing', true),
      plane.removeCoupon('missing'),
    ];
    for (final result in results) {
      expect((result as Failure<Object?>).code, CommerceCodes.notAuthorized);
    }
    expect(scope.read(commerceControlPlaneProvider).offers, before.offers);
    expect(scope.read(commerceControlPlaneProvider).coupons, before.coupons);
  });

  test('offers create, edit, enable, disable and remove', () {
    final scope = container(seed: empty);
    final plane = scope.read(commerceControlPlaneProvider.notifier);
    final created = plane.createOffer(
      target: BillingOptionId.monthly,
      discount: const FixedFinalPriceDiscount(Money.cents(200)),
      title: ' عرض خاص ',
      actor: actor,
    ) as Success<GlobalOffer>;
    expect(created.data.title, 'عرض خاص');
    expect(created.data.enabled, isFalse);

    expect(plane.setOfferEnabled(created.data.id, true, actor: actor).isSuccess,
        isTrue);
    final edited = plane.updateOffer(
      created.data.id,
      target: BillingOptionId.threeMonths,
      discount: const PercentageDiscount(20),
      enabled: false,
      actor: actor,
    ) as Success<GlobalOffer>;
    expect(edited.data.target, BillingOptionId.threeMonths);
    expect(plane.removeOffer(created.data.id, actor: actor).isSuccess, isTrue);
    expect(scope.read(commerceControlPlaneProvider).offers, isEmpty);
  });

  test('a second live offer for one option is refused, not swapped', () {
    final scope = container(seed: empty);
    final plane = scope.read(commerceControlPlaneProvider.notifier);
    plane.createOffer(
      target: BillingOptionId.monthly,
      discount: const PercentageDiscount(10),
      enabled: true,
      actor: actor,
    );
    final second = plane.createOffer(
      target: BillingOptionId.monthly,
      discount: const PercentageDiscount(20),
      enabled: true,
      actor: actor,
    ) as Failure<GlobalOffer>;
    expect(second.code, CommerceCodes.offerConflict);
    expect(scope.read(commerceControlPlaneProvider).offers, hasLength(1));
  });

  test('coupons normalize, edit, toggle and remove', () {
    final scope = container(seed: empty);
    final plane = scope.read(commerceControlPlaneProvider.notifier);
    final created = plane.createCoupon(
      code: ' team 20 ',
      target: BillingOptionId.monthly,
      discount: const PercentageDiscount(20),
      assignment: const CouponAssignmentAccount('account_1'),
      actor: actor,
    ) as Success<Coupon>;
    expect(created.data.code, 'TEAM20');
    expect(created.data.assignment, isA<CouponAssignmentAccount>());

    expect(
        plane.setCouponEnabled(created.data.id, true, actor: actor).isSuccess,
        isTrue);
    final edited = plane.updateCoupon(
      created.data.id,
      code: 'LEADER10',
      target: BillingOptionId.threeMonths,
      discount: const PercentageDiscount(10),
      assignment: const CouponAssignmentPublic(),
      enabled: true,
      note: ' internal ',
      actor: actor,
    ) as Success<Coupon>;
    expect(edited.data.code, 'LEADER10');
    expect(edited.data.note, 'internal');
    expect(plane.removeCoupon(created.data.id, actor: actor).isSuccess, isTrue);
    expect(scope.read(commerceControlPlaneProvider).coupons, isEmpty);
  });

  test('duplicate and malformed coupon codes are refused', () {
    final scope = container(seed: empty);
    final plane = scope.read(commerceControlPlaneProvider.notifier);
    plane.createCoupon(
      code: 'LEADER10',
      target: BillingOptionId.monthly,
      discount: const PercentageDiscount(10),
      assignment: const CouponAssignmentPublic(),
      actor: actor,
    );
    final duplicate = plane.createCoupon(
      code: ' leader 10 ',
      target: BillingOptionId.monthly,
      discount: const PercentageDiscount(10),
      assignment: const CouponAssignmentPublic(),
      actor: actor,
    ) as Failure<Coupon>;
    expect(duplicate.code, CommerceCodes.couponCodeTaken);

    final malformed = plane.createCoupon(
      code: '؟',
      target: BillingOptionId.monthly,
      discount: const PercentageDiscount(10),
      assignment: const CouponAssignmentPublic(),
      actor: actor,
    ) as Failure<Coupon>;
    expect(malformed.code, CommerceCodes.couponCodeInvalid);
  });

  test('invalid targets and discounts never enter state', () {
    final scope = container(seed: empty);
    final plane = scope.read(commerceControlPlaneProvider.notifier);
    final invalidOffer = plane.createOffer(
      target: BillingOptionId.sixMonths,
      discount: const PercentageDiscount(20),
      actor: actor,
    ) as Failure<GlobalOffer>;
    expect(invalidOffer.code, CommerceCodes.promotionInvalid);

    final invalidCoupon = plane.createCoupon(
      code: 'FREE',
      target: BillingOptionId.monthly,
      discount: const FixedFinalPriceDiscount(Money.zero),
      assignment: const CouponAssignmentPublic(),
      actor: actor,
    ) as Failure<Coupon>;
    expect(invalidCoupon.code, CommerceCodes.promotionInvalid);
  });
}
