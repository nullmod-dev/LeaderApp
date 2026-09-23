import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/pricing/domain/coupon_code.dart';

void main() {
  test('normalizes trim, whitespace and ASCII case', () {
    expect(normalizeCouponCode('  try 2 '), 'TRY2');
    expect(normalizeCouponCode('TEAM-20'), 'TEAM-20');
  });

  test('enforces length bounds', () {
    expect(normalizeCouponCode('A1'), isNull);
    expect(normalizeCouponCode('A' * 24), 'A' * 24);
    expect(normalizeCouponCode('A' * 25), isNull);
  });

  test('rejects non-ASCII lookalikes', () {
    expect(normalizeCouponCode('TRY٢'), isNull);
    expect(normalizeCouponCode('АBC'), isNull); // Cyrillic A.
    expect(normalizeCouponCode('TEAM‐20'), isNull); // Unicode hyphen.
  });
}
