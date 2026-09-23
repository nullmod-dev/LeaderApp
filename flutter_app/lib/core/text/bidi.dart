/// Directional isolation for values that carry their own order.
///
/// **Why this exists.** The product is Arabic-first, so every paragraph is a
/// right-to-left run. Some of the values inside those runs are not: a clock
/// (`١٤:٣٠`), a reference code, an email address, a money amount, a version
/// string, a `UTC` label. Left on their own, the Unicode bidirectional
/// algorithm resolves them against the surrounding Arabic and can reorder
/// their parts — a time printed beside a count changes which number the colon
/// belongs to, and a code ending in a digit moves its digit to the other end.
///
/// The fix is an **isolate**, not a `Directionality` override. An override
/// changes the direction of a whole subtree and drags the Arabic around the
/// value out of place with it; `U+2066 LEFT-TO-RIGHT ISOLATE` … `U+2069 POP
/// DIRECTIONAL ISOLATE` scopes the change to the value itself and leaves the
/// sentence it sits in exactly where it was. It is the narrower tool of the
/// two, which is why the rule is "isolate the value, never the row".
abstract final class Bidi {
  static const String _lri = '\u2066';
  static const String _pdi = '\u2069';

  /// Wraps [value] so it keeps its own left-to-right order inside Arabic
  /// text. Returns the empty string untouched — an isolate around nothing is
  /// two invisible characters a screen reader still walks over.
  static String ltr(String value) =>
      value.isEmpty ? value : '$_lri$value$_pdi';

  /// True when [value] has already been isolated, so a helper that composes
  /// two isolated parts does not nest them pointlessly.
  static bool isIsolated(String value) =>
      value.startsWith(_lri) && value.endsWith(_pdi);
}
