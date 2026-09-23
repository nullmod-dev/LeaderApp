import 'billing_option.dart';
import 'money.dart';

sealed class Discount {
  const Discount();
}

final class PercentageDiscount extends Discount {
  const PercentageDiscount(this.percent);

  final int percent;

  @override
  bool operator ==(Object other) =>
      other is PercentageDiscount && other.percent == percent;

  @override
  int get hashCode => percent.hashCode;
}

final class FixedFinalPriceDiscount extends Discount {
  const FixedFinalPriceDiscount(this.finalPrice);

  final Money finalPrice;

  @override
  bool operator ==(Object other) =>
      other is FixedFinalPriceDiscount && other.finalPrice == finalPrice;

  @override
  int get hashCode => finalPrice.hashCode;
}

Money applyDiscount(Discount discount, Money base) => switch (discount) {
      PercentageDiscount(:final percent) => percentageDiscount(base, percent),
      FixedFinalPriceDiscount(:final finalPrice) => finalPrice,
    };

bool isSaneFor(Discount discount, Money base) {
  if (discount is PercentageDiscount &&
      (discount.percent < 1 || discount.percent > 90)) {
    return false;
  }
  final result = applyDiscount(discount, base);
  return result.cents > 0 && result.cents < base.cents;
}

final class GlobalOffer {
  const GlobalOffer({
    required this.id,
    required this.enabled,
    required this.target,
    required this.discount,
    required this.createdAt,
    this.title,
    this.endsAt,
  });

  final String id;
  final bool enabled;
  final BillingOptionId target;
  final Discount discount;
  final DateTime createdAt;
  final String? title;
  final DateTime? endsAt;

  bool isLiveAt(DateTime now) =>
      enabled && (endsAt == null || now.toUtc().isBefore(endsAt!.toUtc()));

  GlobalOffer copyWith({
    bool? enabled,
    BillingOptionId? target,
    Discount? discount,
    String? title,
    bool clearTitle = false,
    DateTime? endsAt,
    bool clearEndsAt = false,
  }) =>
      GlobalOffer(
        id: id,
        enabled: enabled ?? this.enabled,
        target: target ?? this.target,
        discount: discount ?? this.discount,
        createdAt: createdAt,
        title: clearTitle ? null : title ?? this.title,
        endsAt: clearEndsAt ? null : endsAt ?? this.endsAt,
      );
}

sealed class CouponAssignment {
  const CouponAssignment();
}

final class CouponAssignmentPublic extends CouponAssignment {
  const CouponAssignmentPublic();
}

final class CouponAssignmentAccount extends CouponAssignment {
  const CouponAssignmentAccount(this.accountId);

  final String accountId;
}

final class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    required this.enabled,
    required this.target,
    required this.discount,
    required this.assignment,
    required this.createdAt,
    this.note,
    this.expiresAt,
  });

  final String id;
  final String code;
  final bool enabled;
  final BillingOptionId target;
  final Discount discount;
  final CouponAssignment assignment;
  final DateTime createdAt;
  final String? note;
  final DateTime? expiresAt;

  bool isLiveAt(DateTime now) =>
      enabled &&
      (expiresAt == null || now.toUtc().isBefore(expiresAt!.toUtc()));

  Coupon copyWith({
    String? code,
    bool? enabled,
    BillingOptionId? target,
    Discount? discount,
    CouponAssignment? assignment,
    String? note,
    bool clearNote = false,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
  }) =>
      Coupon(
        id: id,
        code: code ?? this.code,
        enabled: enabled ?? this.enabled,
        target: target ?? this.target,
        discount: discount ?? this.discount,
        assignment: assignment ?? this.assignment,
        createdAt: createdAt,
        note: clearNote ? null : note ?? this.note,
        expiresAt: clearExpiresAt ? null : expiresAt ?? this.expiresAt,
      );
}
