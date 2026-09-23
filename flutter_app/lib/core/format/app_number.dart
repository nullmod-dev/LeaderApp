import '../motion/animated_counter.dart';
import '../text/bidi.dart';
import '../../l10n/strings.dart';

/// Figures, in the shape this interface reads them.
///
/// **Why one path.** The app renders every number through [toArabicIndic] and
/// then, for a percentage, appended a bare `'٪'` at the call site —
/// seventeen of them across pricing, the detachment list, the group list, the
/// report builder, the member status page and the statistics tab. One of them
/// reached for Material's `Icons.percent_rounded`, which is the **Latin** `%`
/// letterform, and put it directly above an Arabic `٪`. A percentage is one
/// decision, and it belongs in one place.
///
/// Nothing here rounds, scales or reinterprets a value: `percent(83)` is the
/// number 83 written in Arabic. What the number *means* stays with whoever
/// computed it.
abstract final class AppNumber {
  /// `١٢٣` — any whole figure the interface prints.
  static String count(int value) => toArabicIndic('$value');

  /// `٨٣٪` — the app's one percentage.
  ///
  /// `٪` is U+066A ARABIC PERCENT SIGN, which the bundled family draws and
  /// which the bidirectional algorithm attaches to the Arabic-Indic digits
  /// before it, so the mark lands on the correct side with no isolate. The
  /// Latin `%` is never used, in text or as a glyph.
  static String percent(int value) => '${count(value)}${S.percentSign}';

  /// `٤٠ / ١٠٠` — a part over its whole, isolated so the slash cannot be
  /// pulled to the wrong end of the pair by the Arabic around it.
  static String ratio(int part, int whole) =>
      Bidi.ltr('${count(part)} / ${count(whole)}');

  /// The scale a chart is drawn against, said in words: `٠–١٠٠`.
  ///
  /// Printed beside every series so a reader knows what a full-height bar
  /// means. The dash is U+2013, and the pair is isolated because it is a
  /// numeric range, not a sentence.
  static String range(int from, int to) =>
      Bidi.ltr('${count(from)}–${count(to)}');
}
