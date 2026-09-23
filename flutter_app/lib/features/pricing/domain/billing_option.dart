import 'money.dart';

enum BillingOptionId {
  monthly('monthly', 1),
  threeMonths('three_months', 3),
  sixMonths('six_months', 6),
  twelveMonths('twelve_months', 12);

  const BillingOptionId(this.wire, this.months);

  final String wire;
  final int months;

  static BillingOptionId? tryParse(String wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return null;
  }

  bool get promotionEligible => kPromotionEligibleOptions.contains(this);
}

const Set<BillingOptionId> kPromotionEligibleOptions = {
  BillingOptionId.monthly,
  BillingOptionId.threeMonths,
};

final class BillingOption {
  const BillingOption({required this.id, required this.basePrice});

  final BillingOptionId id;
  final Money basePrice;

  int get months => id.months;

  /// Duration changes time only; every option grants the same full product.
  bool get grantsFullLeaderAccess => true;
}

BillingOption? billingOptionById(
  List<BillingOption> catalog,
  BillingOptionId id,
) {
  for (final option in catalog) {
    if (option.id == id) return option;
  }
  return null;
}
