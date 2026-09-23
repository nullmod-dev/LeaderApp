import 'package:flutter/material.dart';

/// How wide content is allowed to run — four stops on one scale, not four
/// systems.
///
/// The app already spelled these by hand in different places: 420 in four
/// dialogs, 440 on the Login form, 520 on the session-state screens, 720 on
/// every platform page. They are named here so a screen picks a *measure*
/// rather than a number, and so a wide window gains margins instead of
/// stretching a phone layout across it.
///
/// The rule for choosing:
///
///  * [kDialogMaxWidth] — the body of a dialog, which already sits inside
///    Material's own inset and should not run wider than a sentence.
///  * [kFormMaxWidth] — one column of inputs the user fills in. Beyond this a
///    text field becomes a line you lose your place on.
///  * [kReadingMaxWidth] — a page of label↔value rows, facts and cards. This
///    is the tenant default, because a settings row puts its label at the
///    start and its value at the end, and a 900 dp row is a label and a value
///    with half a screen of nothing between them — exactly what the
///    2026-09-19 UI audit caught on the Plan page at 600 dp.
///  * [kContentMaxWidth] — a working column that holds lists, grouped cards
///    and paragraphs. The platform measure.
///
/// None of these belongs on an inherently wide surface: a dense operational
/// table or a data grid reflows, it does not get squeezed into a prose
/// column.
///
/// ## Which measure a tenant screen takes (Phase 3A)
///
/// Phase 1 named the measures. What it did not say is which screens take
/// which, and the answer is not "cap everything at 520" — a week schedule
/// squeezed into a reading column is worse than one that stretches. Four
/// classes, decided by what the screen is *for*:
///
/// **A · Reading and form surfaces** — a page of label↔value rows, a
/// settings group, a form, a single record. `ReadingColumn` at the default
/// [kReadingMaxWidth], or [kFormMaxWidth] when it is one column of inputs.
/// *Settings, Themes, Organization, Plan, Pricing, Sync, Needs Review, every
/// edit page.* Already applied.
///
/// **B · Operational lists and landings** — a scrollable column of grouped
/// cards, rows and sections that a person works down. `ReadingColumn` at
/// [kContentMaxWidth]: wide enough for a row with a leading glyph, a two-line
/// title and a trailing affordance, narrow enough that the trailing
/// affordance stays in the same eye-movement as the title. *Home,
/// Statistics, Detachments, Team, Inventory, Workshops, Workshop register,
/// Notifications.* Home and Statistics are done; the rest are the next pass.
///
/// **C · Schedule and data-dense views** — a week grid, a dense comparison
/// table, anything whose *columns* are the information. These take the width
/// they are given and reflow inside it; capping them hides data that the
/// extra width exists to show. *The shifts week view, and a future
/// attendance matrix.* They still need a maximum eventually — but it is the
/// grid's own, expressed in columns, not a prose measure.
///
/// **D · Responsive two-column** — only where two groups are genuinely
/// consulted together and the second is not a footnote to the first. It is
/// not a way to fill a wide window: Home deliberately stays one column at
/// 900 dp, because its sections are a *reading order* — what needs attention,
/// then today, then the facts — and putting "today" beside "attention" is
/// exactly the hierarchy the redesign removed. Decide it from the width the
/// content has after its cap, with a `LayoutBuilder`, never from a global
/// breakpoint constant that means something different on every screen.
///
/// A grid *inside* one of these columns (a row of metric tiles, a set of
/// shortcuts) picks its column count from its own `LayoutBuilder` and the
/// text scale, not from the window: at 1.6× a four-up row of tiles truncates
/// its labels into «أدوية…» long before the window is narrow.
const double kDialogMaxWidth = 420;
const double kFormMaxWidth = 440;
const double kReadingMaxWidth = 520;
const double kContentMaxWidth = 720;

/// Caps [child] at a measure and centres it once the window is wider.
///
/// Top-aligned, so a short page sits under its header rather than floating in
/// the middle of a tall window; centred horizontally, so a tablet gains
/// margins. Below the cap nothing happens at all — a phone gets the layout it
/// always had.
///
/// Wraps a scrolling child happily: the `ListView` inside keeps its own
/// padding and scrolls the full height, it is only narrower.
class ReadingColumn extends StatelessWidget {
  const ReadingColumn({
    super.key,
    required this.child,
    this.maxWidth = kReadingMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}
