import 'package:flutter/material.dart';

import '../format/app_number.dart';
import '../format/app_time.dart';
import '../text/bidi.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

/// A line of facts, and the separator it does **not** print.
///
/// **Why this exists.** The 2026-09-19 UI audit (P1-11) found the app joining
/// facts with a literal ` · ` in 115 places across 55 files while rendering
/// every number with `toArabicIndic`, where zero is `٠` (U+0660) — a raised
/// dot. On the Main Admin dashboard the context line read
/// «السبت ٠ ١٢ أيلول ٠ اللاذقية»: the separators and a digit are the same
/// mark. On the statistics tab a member's record read «إجمالي الحضور ١ ٠
/// إجمالي الغياب ٠ ٠ الحضور المكتمل ١» — a run of five identical dots of
/// which three are values.
///
/// Replacing the character with another character only moves the problem to
/// whatever mark comes next: a painted dot still sits beside «٠» and reads as
/// a second zero. So the separator stops being a *dot* and stops being a
/// *character*. It is a 1 dp vertical hairline drawn outside the text run,
/// with no numeral in the script it could be confused with. It cannot be
/// selected, cannot be copied into a support ticket, and is never announced.
///
/// Its height follows the text scale, so at 1.6× it still reads as a rule
/// between two facts rather than as a speck between two words. The separator
/// attaches to the *following* item rather than being inserted between items,
/// so a wrapped line never begins with an orphan mark.
///
/// **Where it came from.** Phase 2 of the UI quality programme built this for
/// the Super Admin surface as `PlatformMeta`. Nothing about a hairline is
/// platform-specific, and the tenant surface had the worse instances of the
/// same defect, so Phase 3A moved it here. `PlatformMeta` is now an alias of
/// this class, which is the direction the dependency has to run: a tenant
/// screen may never import `features/platform/`.
///
/// **How to use it.** Pass facts, not a joined string. Each fact is an
/// [AppMetaText] — `AppMetaText.day`, `.time`, `.count`, `.percent`, `.code`
/// and `.money` build the structured kinds so no call site composes
/// punctuation by hand. Anything that is ordinary Arabic prose — a duration
/// in words, a status, a place — is the default constructor.
class AppMeta extends StatelessWidget {
  const AppMeta({super.key, required this.parts, this.semanticsLabel});

  /// The facts, in reading order.
  final List<Widget> parts;

  /// Replaces what a screen reader says for the whole line. Pass it where the
  /// parts read as fragments out loud — a name, then a bare time.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final line = Wrap(
      spacing: 0,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < parts.length; i++)
          if (i == 0)
            parts[i]
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Separator(color: c.line2),
                // Flexible, not the bare child: the rule and its fact are one
                // unit so the rule never starts a wrapped line, but a long
                // fact inside a narrow card still has to be allowed to wrap
                // rather than overflow the row it is glued to.
                Flexible(child: parts[i]),
              ],
            ),
      ],
    );
    if (semanticsLabel == null) return line;
    return Semantics(
      container: true,
      label: semanticsLabel,
      child: ExcludeSemantics(child: line),
    );
  }
}

/// One fact on an [AppMeta] line.
///
/// The named constructors are the point: a screen says *what kind of fact*
/// this is and the primitive decides the numerals, the isolation and the
/// shape. A call site that writes `'${x.day}/${x.month} · $count'` has made
/// four decisions the design system was supposed to own.
class AppMetaText extends StatelessWidget {
  const AppMetaText(
    this.value, {
    super.key,
    this.color,
    this.emphasis = false,
    this.ltr = false,
  });

  /// `١٢ أيلول`.
  AppMetaText.day(DateTime value, {super.key, this.color, this.emphasis = false})
      : value = AppTime.day(value),
        ltr = false;

  /// `١٢ أيلول ٢٠٢٦`.
  AppMetaText.date(DateTime value,
      {super.key, this.color, this.emphasis = false})
      : value = AppTime.date(value),
        ltr = false;

  /// `١٤:٣٠`, already isolated by [AppTime].
  AppMetaText.time(DateTime value,
      {super.key, this.color, this.emphasis = false})
      : value = AppTime.time(value),
        ltr = false;

  /// `١٢ أيلول ١٤:٣٠`.
  AppMetaText.dayTime(DateTime value,
      {super.key, this.color, this.emphasis = false})
      : value = AppTime.dayTime(value),
        ltr = false;

  /// `١٢ عضوا` — a figure and the noun it counts, as one fact.
  ///
  /// The figure leads, which is the shape Arabic uses for a counted noun.
  /// [label] may be omitted where the column already names the thing. The two
  /// are one fact and therefore never carry a rule between them.
  AppMetaText.count(int value,
      {super.key, String? label, this.color, this.emphasis = false})
      : value = label == null
            ? AppNumber.count(value)
            : '${AppNumber.count(value)} $label',
        ltr = false;

  /// `إجمالي الحضور ١٢` — a named total.
  ///
  /// The other shape, and a separate constructor rather than a flag: «١٢
  /// إجمالي الحضور» is not Arabic, and a call site choosing between them with
  /// a boolean would get it wrong. A counted noun leads with the figure; a
  /// named total leads with its name.
  AppMetaText.total(String label, int value,
      {super.key, this.color, this.emphasis = false})
      : value = '$label ${AppNumber.count(value)}',
        ltr = false;

  /// `٨٣٪`, or `نسبة الحضور ٨٣٪` with a [label].
  AppMetaText.percent(int value,
      {super.key, String? label, this.color, this.emphasis = false})
      : value = label == null
            ? AppNumber.percent(value)
            : '$label ${AppNumber.percent(value)}',
        ltr = false;

  /// A reference code, an email address, a version, any Latin technical
  /// value. Isolated so Arabic around it cannot move its parts.
  const AppMetaText.code(this.value,
      {super.key, this.color, this.emphasis = false})
      : ltr = true;

  /// An already-formatted money amount. The currency rules stay with whoever
  /// owns the price; this only keeps the amount in its own order.
  const AppMetaText.money(this.value,
      {super.key, this.color, this.emphasis = false})
      : ltr = true;

  final String value;
  final Color? color;

  /// Raises the weight, for the one part of the line that is the reading —
  /// how much of a window is left, a severity word, the latest figure.
  final bool emphasis;

  /// Wraps the value in a left-to-right isolate. See [Bidi.ltr]: an isolate,
  /// never a `Directionality` override, and never applied to a whole row.
  final bool ltr;

  @override
  Widget build(BuildContext context) => Text(
        ltr && !Bidi.isIsolated(value) ? Bidi.ltr(value) : value,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color ?? context.c.ink3,
              fontWeight: emphasis ? FontWeight.w600 : null,
            ),
      );
}

class _Separator extends StatelessWidget {
  const _Separator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: SizedBox(
            width: 1,
            // Tied to the text it separates: a fixed 11 dp rule beside a 19 dp
            // line at a 1.6 text scale reads as a mark rather than a divider.
            height: MediaQuery.textScalerOf(context).scale(11),
            child: ColoredBox(color: color),
          ),
        ),
      );
}
