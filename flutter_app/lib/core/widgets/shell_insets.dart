import 'package:flutter/material.dart';

/// How much room a scrolling screen has to leave under its content for the
/// shell it is hosted in.
///
/// **Why this became a lookup instead of a constant.** The tenant shell floats
/// its glass pill *above* the body — nothing insets the content, so every
/// scrolling screen adds the room itself, and 96 was that number written into
/// [FloatingNavPadding]. The platform shell docks its bar in the `Scaffold`
/// slot instead, which insets the body already; the same 96 there is a dead
/// band at the bottom of every screen the two surfaces share (Profile,
/// Security, Themes, Eye Protection, About).
///
/// The fix that is *not* right is a second copy of each of those screens. So
/// the number moved to where the answer is actually known — the shell — and
/// the screens keep asking one question they already asked.
///
/// A screen outside any shell (a state screen, a full-screen form) finds no
/// scope and gets [kFloatingNavInset], which is what it had before.
class ShellBottomInset extends InheritedWidget {
  const ShellBottomInset({
    super.key,
    required this.inset,
    required super.child,
  });

  /// Extra space to leave below scrolling content, on top of whatever system
  /// inset the screen still carries.
  ///
  /// `0` for a shell whose navigation is docked: `Scaffold` has already made
  /// room for the bar *and* removed the bottom system padding from the body,
  /// so both terms are zero and the content ends where the bar begins.
  final double inset;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellBottomInset>()?.inset ??
      kFloatingNavInset;

  @override
  bool updateShouldNotify(ShellBottomInset oldWidget) =>
      inset != oldWidget.inset;
}

/// The room the tenant shell's floating glass bar needs. The default, because
/// it is what every screen written before the platform surface assumed.
const double kFloatingNavInset = 96;

/// Bottom padding for a scrolling screen, so the shell's navigation never
/// covers the last row of content.
class FloatingNavPadding extends StatelessWidget {
  const FloatingNavPadding({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inset = ShellBottomInset.of(context);
    return Padding(
      // The system inset is added only when the bar floats. A docked bar's
      // `Scaffold` has already removed it from the body's `MediaQuery`, so
      // this reads 0 there and the two cases need no `if`.
      padding: EdgeInsets.only(
        bottom: inset + MediaQuery.of(context).padding.bottom,
      ),
      child: child,
    );
  }
}
