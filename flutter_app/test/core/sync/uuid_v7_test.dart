import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/sync/uuid_v7.dart';

void main() {
  group('UuidV7', () {
    test('has the RFC 9562 v7 shape: version nibble 7, variant 10', () {
      final gen = UuidV7(random: Random(1));
      for (var i = 0; i < 200; i++) {
        final id = gen.generate();
        expect(isUuidV7(id), isTrue, reason: id);
        // 15th hex char (index 14) is the version nibble.
        expect(id[14], '7', reason: id);
        // 20th hex char (index 19) is the variant nibble: 8,9,a,b.
        expect('89ab'.contains(id[19]), isTrue, reason: id);
        expect(id.length, 36);
      }
    });

    test('is unique across a burst', () {
      final gen = UuidV7(random: Random(7));
      final seen = <String>{};
      for (var i = 0; i < 5000; i++) {
        expect(seen.add(gen.generate()), isTrue);
      }
    });

    test('sorts in creation order, even within one millisecond', () {
      var ms = 1700000000000;
      final gen = UuidV7(
          random: Random(3),
          clock: () => DateTime.fromMillisecondsSinceEpoch(ms));
      final a = gen.generate();
      final b =
          gen.generate(); // same ms — monotonic counter must break the tie
      ms += 5;
      final c = gen.generate();
      final list = [c, a, b]..sort();
      expect(list, [a, b, c]);
    });

    test('the leading 48 bits are the millisecond timestamp', () {
      const ms = 0x0123456789AB;
      final gen = UuidV7(
        random: Random(9),
        clock: () => DateTime.fromMillisecondsSinceEpoch(ms),
      );
      final id = gen.generate();
      final hex = id.replaceAll('-', '');
      expect(hex.substring(0, 12), '0123456789ab');
    });

    test('the module-level uuidV7() produces valid v7 ids', () {
      expect(isUuidV7(uuidV7()), isTrue);
      expect(uuidV7(), isNot(uuidV7()));
    });

    test('isUuidV7 rejects a v4 and other noise', () {
      expect(isUuidV7('550e8400-e29b-41d4-a716-446655440000'), isFalse);
      expect(isUuidV7('not-a-uuid'), isFalse);
      expect(isUuidV7(''), isFalse);
    });
  });
}
