/// Integer-minor-unit money used by the local pricing preview.
///
/// Commercial source values are always cents. Formatting is deliberately kept
/// beside the value so widgets never perform price arithmetic.
final class Money implements Comparable<Money> {
  const Money.cents(this.cents) : assert(cents >= 0);

  final int cents;

  static const zero = Money.cents(0);

  Money operator -(Money other) => Money.cents(cents - other.cents);

  bool operator <(Money other) => cents < other.cents;
  bool operator <=(Money other) => cents <= other.cents;
  bool operator >(Money other) => cents > other.cents;
  bool operator >=(Money other) => cents >= other.cents;

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => 'Money.cents($cents)';
}

/// Applies the approved half-up percentage algorithm to the discount itself.
Money percentageDiscount(Money base, int percent) {
  final discountCents = ((base.cents * percent) + 50) ~/ 100;
  return Money.cents(base.cents - discountCents);
}

/// Display-only monthly equivalent, rounded half-up to the nearest cent.
Money effectiveMonthlyPrice(Money total, int months) {
  assert(months > 0);
  return Money.cents((total.cents + (months ~/ 2)) ~/ months);
}

/// Savings versus paying the monthly base price for the same duration.
Money durationSavings({
  required Money monthlyBase,
  required int months,
  required Money effectivePrice,
}) {
  final cents = (monthlyBase.cents * months) - effectivePrice.cents;
  return Money.cents(cents < 0 ? 0 : cents);
}

/// Formats USD with Western digits and isolates it from surrounding RTL text.
String formatUsd(
  Money money, {
  bool isolate = true,
  bool forceFractionalDigits = false,
}) {
  final dollars = money.cents ~/ 100;
  final remainder = money.cents % 100;
  final value = remainder == 0 && !forceFractionalDigits
      ? '\$$dollars'
      : '\$$dollars.${remainder.toString().padLeft(2, '0')}';
  return isolate ? '\u2066$value\u2069' : value;
}
