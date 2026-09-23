import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/billing_option.dart';
import '../domain/money.dart';

const List<BillingOption> kLeaderPricingCatalog = [
  BillingOption(
    id: BillingOptionId.monthly,
    basePrice: Money.cents(600),
  ),
  BillingOption(
    id: BillingOptionId.threeMonths,
    basePrice: Money.cents(1400),
  ),
  BillingOption(
    id: BillingOptionId.sixMonths,
    basePrice: Money.cents(2400),
  ),
  BillingOption(
    id: BillingOptionId.twelveMonths,
    basePrice: Money.cents(4000),
  ),
];

/// Future backend seam for the authoritative pricing catalog.
final pricingCatalogProvider =
    Provider<List<BillingOption>>((ref) => kLeaderPricingCatalog);
