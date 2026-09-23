import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/pricing/domain/money.dart';

void main() {
  test('money is integer cents with value equality', () {
    expect(const Money.cents(600), const Money.cents(600));
    expect(const Money.cents(600) - const Money.cents(200),
        const Money.cents(400));
  });

  test('percentage rounding is half-up on the discount', () {
    const cases = [
      (1400, 10, 1260),
      (600, 20, 480),
      (600, 5, 570),
      (1400, 33, 938),
      (600, 1, 594),
    ];
    for (final (base, percent, expected) in cases) {
      expect(percentageDiscount(Money.cents(base), percent).cents, expected);
    }
  });

  test('effective monthly display values are exact', () {
    expect(effectiveMonthlyPrice(const Money.cents(600), 1).cents, 600);
    expect(effectiveMonthlyPrice(const Money.cents(1400), 3).cents, 467);
    expect(effectiveMonthlyPrice(const Money.cents(2400), 6).cents, 400);
    expect(effectiveMonthlyPrice(const Money.cents(4000), 12).cents, 333);
  });

  test('duration savings compare against the monthly base', () {
    expect(
      durationSavings(
        monthlyBase: const Money.cents(600),
        months: 3,
        effectivePrice: const Money.cents(1400),
      ),
      const Money.cents(400),
    );
  });

  test('USD format omits zero cents and carries an LTR isolate', () {
    expect(formatUsd(const Money.cents(600)), '\u2066\$6\u2069');
    expect(formatUsd(const Money.cents(467)), '\u2066\$4.67\u2069');
    expect(formatUsd(const Money.cents(400), isolate: false), '\$4');
    expect(
      formatUsd(
        const Money.cents(600),
        isolate: false,
        forceFractionalDigits: true,
      ),
      '\$6.00',
    );
  });
}
