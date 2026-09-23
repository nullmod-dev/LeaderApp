import 'package:flutter/material.dart';

import '../motion/motion_tokens.dart';
import '../motion/press_scale.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';

/// The one control this app uses to narrow a list.
///
/// **What this is for.** Category A only: *filtering a dataset* — the row of
/// pills above a list that decides which rows are shown. It is deliberately
/// not the component for:
///
///  * a **setting or a form value** (the packaging unit on an inventory item,
///    the audience of an announcement) — those are `ChoiceChip`s in a form
///    and read as a value, not as a view;
///  * a **status action** that changes an entity — those are buttons, and
///    dressing a mutation as a filter is how someone archives a workshop
///    thinking they hid one;
///  * the **multi-select filter sheet** on the Team roster, which keeps
///    Material's checkable `FilterChip`: an additive, several-at-once choice
///    reads differently from an exclusive one and the checkmark is what says
///    so.
///
/// **Why it exists.** The 2026-09-19 UI audit counted ten implementations of
/// "filter this list": `_Filter` ×2 (byte-identical copies in the detachment
/// and workshop lists), `_FilterChip` ×2, `_Chip` ×2, plus Material chips
/// used directly. Two of them disagreed about what *selected* looks like, so
/// a Super Admin moving between the platform and tenant surfaces saw two
/// products.
///
/// **The selected treatment** is the tenant one — a solid `primary` fill with
/// `primaryInk` on it — because it was already the majority and because a
/// filled pill survives the eye-protect wash and all six palettes with the
/// contrast the palette test enforces on a filled button label. State is
/// never colour alone: the chip is announced `selected:` and, when the list
/// shows a disabled option, the label dims *and* the chip stops responding.
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
    this.semanticLabel,
  });

  final String label;
  final bool selected;

  /// Called with the value the chip would take. A single-select bar passes
  /// `true` and ignores it; a toggleable one reads it.
  final ValueChanged<bool> onSelected;

  /// A filter that exists but cannot apply right now — an archived bucket on
  /// a detachment with no archive. Rendered muted and inert rather than
  /// hidden, so the set of filters does not change shape under the user.
  final bool enabled;

  /// Overrides what a screen reader says. The default is [label], which is
  /// almost always right.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final on = selected && enabled;
    final fg = !enabled
        ? c.ink3
        : on
            ? c.primaryInk
            : c.ink2;
    final chip = AnimatedContainer(
      duration: effectiveDuration(context, MotionTokens.short),
      curve: effectiveCurve(context, MotionTokens.standard),
      // 6 vertical on a 13 sp label is a 30 dp pill; the 48 dp target comes
      // from the row it sits in, which gives it `AppSpacing.sm` of slop on
      // every side. Growing the pill instead would make a six-filter row
      // unreadable at a 1.6 text scale.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: on ? c.primary : c.surface,
        border: Border.all(color: on ? c.primary : c.line2),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        // Wraps rather than ellipsises: an Arabic filter label at 1.6× is
        // long, and half a word is not a filter.
        softWrap: true,
        style: TextStyle(
          color: fg,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: semanticLabel ?? label,
      // On the node itself: TalkBack dispatches a semantics action, which
      // never reaches a gesture detector under an `ExcludeSemantics`.
      onTap: enabled ? () => onSelected(!selected) : null,
      child: ExcludeSemantics(
        child: enabled
            ? PressScale(
                onTap: () => onSelected(!selected),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                child: chip,
              )
            : Opacity(opacity: 0.55, child: chip),
      ),
    );
  }
}

/// A row of [AppFilterChip]s that wraps onto a second line.
///
/// Wrapping, not horizontal scrolling: a clipped chip row hides filters with
/// no affordance to reach them — the audit found the platform tenants list
/// losing its sixth chip off the edge — and a wrapped second row costs one
/// line of a screen whose job is to show results.
class AppFilterBar extends StatelessWidget {
  const AppFilterBar({
    super.key,
    required this.children,
    this.semanticLabel,
    this.padding = EdgeInsets.zero,
  });

  final List<Widget> children;

  /// Names the group for a screen reader — «تصفية الفرق». Without it the
  /// chips are announced as loose buttons with no stated purpose.
  final String? semanticLabel;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final bar = Padding(
      padding: padding,
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: children,
      ),
    );
    if (semanticLabel == null) return bar;
    return Semantics(container: true, label: semanticLabel, child: bar);
  }
}
