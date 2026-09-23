import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/motion/transitions.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/shell_insets.dart';
import '../domain/platform_area.dart';
import 'widgets/platform_navigation.dart';
import 'widgets/platform_break_glass_strip.dart';

/// The Super Admin's shell — the SaaS control plane's navigation host.
///
/// **Deliberately not `MainShell`.** They look like the same problem and are
/// not. `MainShell` decides which of its branches to *offer* from the session's
/// capability grant, swipes between them, and floats the tenant app's glass
/// pill over the body. None of that transfers: the platform's four areas are
/// fixed (a control plane's shape must not change under the one operator who
/// knows it), platform authorization is not the tenant capability model at all
/// (`CAPABILITIES.md` §5b), and swiping between control-plane areas is a
/// gesture from the other product. What the two *do* share is the design
/// system underneath — tokens, motion, the status primitives — which is the
/// sharing `§8` of the brief asks for and the sharing that costs nothing.
///
/// **The shell reads one Platform seam and no tenant repository.** Its only
/// read is the break-glass strip's `breakGlassAccessProvider` (Point 12B) —
/// the session-bound `PlatformBreakGlassRepository`, never tenant data. Its
/// overview child owns the one aggregate `PlatformOverviewRepository`; neither
/// the shell nor any platform page imports a tenant-operational repository.
/// That keeps the control-plane boundary true by construction rather than by
/// a hidden widget.
///
/// **Adaptation is by available width, never by device.** The `LayoutBuilder`
/// measures what this shell was actually given, so a foldable, a split-screen
/// window and a rotated tablet each get the layout their *width* deserves and
/// no `Platform.isTablet` is consulted anywhere.
class PlatformShell extends ConsumerWidget {
  const PlatformShell({super.key, required this.navigationShell});

  /// The shell's own root location. Declared here, spelled once in
  /// `domain/platform_area.dart`, and shared with the startup classifier —
  /// which is the reason `kPlatformRoot` is a constant rather than a literal
  /// in three files.
  static const String location = kPlatformRoot;

  /// Where the rail takes over from the bar.
  ///
  /// 600 logical pixels: the width Flutter's own adaptive guidance names as
  /// the compact/medium boundary, and the point at which a 96 dp rail stops
  /// costing the content more than it gives back. The repository had no
  /// existing breakpoint to reuse — nothing in `core/` branched on width
  /// before this — so this is the app's first one, and it is stated here so
  /// the next surface reuses it rather than inventing 640.
  static const double expandedBreakpoint = 600;

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = navigationShell.currentIndex;

    void goTo(int branch) {
      // `initialLocation: true` only when the branch is already selected, so
      // tapping the current destination returns to its root and tapping
      // another restores where that one was left — the branch-state promise
      // in `§13`.
      navigationShell.goBranch(branch, initialLocation: branch == index);
    }

    // One shared body for both layouts: the same `navigationShell`, the same
    // indexed stack, the same widget identities. Resizing across the
    // breakpoint therefore re-parents the navigation control and nothing else
    // — the selected destination and every branch's stack survive it.
    final branchBody = ShellBottomInset(
      // The platform bar is docked in the `Scaffold` slot rather than floating
      // over the body, so a screen inside this shell reserves nothing for it.
      // The shared settings screens read this instead of the tenant constant.
      inset: 0,
      child: TabSwitchTransition(index: index, child: navigationShell),
    );
    final body = Column(
      children: [
        const PlatformBreakGlassStrip(),
        Expanded(child: PlatformBreakGlassBodyInset(child: branchBody)),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= expandedBreakpoint) {
          return Scaffold(
            backgroundColor: context.c.bg,
            body: Row(
              // Stretch, not the default centre: the rail sizes itself from
              // four items, and a centred rail floats as a short panel in the
              // middle of the edge instead of reading as the side of the
              // window. Its own scroll view then works inside the full height.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // First child, so `Row` under the app's RTL `Directionality`
                // puts the rail on the right where an Arabic reader starts.
                PlatformNavigationRail(currentIndex: index, onSelected: goTo),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: context.c.bg,
          body: body,
          bottomNavigationBar: PlatformNavigationBar(
            currentIndex: index,
            onSelected: goTo,
          ),
        );
      },
    );
  }
}
