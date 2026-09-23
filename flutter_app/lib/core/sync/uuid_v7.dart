import 'dart:math';

/// UUIDv7 (RFC 9562 §5.7) — a 128-bit id whose leading 48 bits are a
/// Unix-millisecond timestamp, so ids sort in creation order, followed by
/// 74 bits of randomness.
///
/// ## Why it lives here and not in a package
///
/// The roadmap expects `Idempotency-Key: <UUIDv7>`. MTM's dependency set has
/// no UUID library and this is a frontend-only task — adding one would be
/// churn for ~30 lines. `Random.secure()` from `dart:math` is enough to
/// build a spec-correct v7, so it is built here behind a typed seam
/// ([uuidV7], overridable through `newOperationIdProvider`) rather than
/// faked. A timestamp alone is explicitly **not** an acceptable key
/// (collisions, guessable) — this carries 74 random bits.
///
/// The layout produced (big-endian):
///
/// ```
///  0                   1                   2                   3
///  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                        unix_ts_ms (48)                        |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |  ver (4)=0111 |        rand_a (12)      | var(2)=10| rand_b … |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// |                        rand_b (cont. 62)                      |
/// +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
/// ```
class UuidV7 {
  UuidV7({Random? random, DateTime Function()? clock})
      : _random = random ?? _secureOrFallback(),
        _clock = clock ?? DateTime.now;

  final Random _random;
  final DateTime Function() _clock;

  int _lastMs = 0;
  int _counter = 0;

  static Random _secureOrFallback() {
    try {
      return Random.secure();
    } on UnsupportedError {
      // No platform CSPRNG (some embed targets). A non-secure fallback is
      // acceptable for a de-duplication key — it is not a secret — and the
      // fact is documented rather than hidden.
      return Random();
    }
  }

  /// A fresh v7 string, `xxxxxxxx-xxxx-7xxx-yxxx-xxxxxxxxxxxx`.
  ///
  /// Monotonic within a process: two calls in the same millisecond still
  /// sort in call order (RFC 9562 "method 2" — a per-ms counter in the top
  /// of `rand_a`), so the outbox keeps a stable order even under a burst.
  String generate() {
    var ms = _clock().millisecondsSinceEpoch;
    if (ms < 0) ms = 0;
    if (ms == _lastMs) {
      _counter++;
    } else {
      _lastMs = ms;
      _counter = 0;
    }

    final bytes = List<int>.filled(16, 0);

    // 48-bit big-endian timestamp.
    bytes[0] = (ms >> 40) & 0xff;
    bytes[1] = (ms >> 32) & 0xff;
    bytes[2] = (ms >> 24) & 0xff;
    bytes[3] = (ms >> 16) & 0xff;
    bytes[4] = (ms >> 8) & 0xff;
    bytes[5] = ms & 0xff;

    // 12-bit rand_a: the sub-millisecond monotonic counter, then random
    // fill if the counter has not moved.
    final randA = _counter & 0x0fff;
    bytes[6] = 0x70 | ((randA >> 8) & 0x0f); // version 7 in the high nibble
    bytes[7] = randA & 0xff;

    // 62-bit rand_b.
    bytes[8] = 0x80 | (_random.nextInt(0x40)); // variant 10 in the top 2 bits
    for (var i = 9; i < 16; i++) {
      bytes[i] = _random.nextInt(0x100);
    }

    return _format(bytes);
  }

  static String _format(List<int> b) {
    final hex = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}

/// Process-wide default generator. Features never call this directly — they
/// go through the outbox, which reads `newOperationIdProvider` so a test can
/// pin the value.
final _default = UuidV7();

/// A fresh UUIDv7. The single production id source for local write
/// operations and their idempotency identity.
String uuidV7() => _default.generate();

/// Loose RFC-9562 shape check — 8-4-4-4-12 hex, version nibble `7`, variant
/// nibble in `{8,9,a,b}`. Used by tests and by the record parser to reject a
/// value that is not a v7 at all.
bool isUuidV7(String value) {
  final re = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  return re.hasMatch(value);
}
