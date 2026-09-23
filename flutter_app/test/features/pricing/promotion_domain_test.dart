import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/pricing/domain/money.dart';
import 'package:mtm/features/pricing/domain/promotion.dart';

void main() {
  test('percentage and fixed-final-price discounts apply', () {
    expect(
      applyDiscount(const PercentageDiscount(20), const Money.cents(600)),
      const Money.cents(480),
    );
    expect(
      applyDiscount(
        const FixedFinalPriceDiscount(Money.cents(200)),
        const Money.cents(600),
      ),
      const Money.cents(200),
    );
  });

  test('sanity rejects zero, non-discounts and invalid percentages', () {
    const base = Money.cents(600);
    expect(isSaneFor(const FixedFinalPriceDiscount(Money.zero), base), isFalse);
    expect(isSaneFor(const FixedFinalPriceDiscount(base), base), isFalse);
    expect(isSaneFor(const FixedFinalPriceDiscount(Money.cents(700)), base),
        isFalse);
    expect(isSaneFor(const PercentageDiscount(0), base), isFalse);
    expect(isSaneFor(const PercentageDiscount(100), base), isFalse);
    expect(isSaneFor(const PercentageDiscount(20), base), isTrue);
  });
}
