import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../demo/presentation/demo_trial_bar.dart';
import '../../core/access/admin_experience.dart';
import '../../core/access/capability_guard.dart';
import '../../core/motion/transitions.dart';
import '../../core/widgets/glass_bottom_nav.dart';
import '../../core/widgets/swipe_tabs.dart';
import '../../l10n/strings.dart';
import '../tenant_feature/data/tenant_feature_providers.dart';
import '../tenant_feature/domain/tenant_feature_models.dart';

// `FloatingNavPadding` moved to `core/widgets/shell_insets.dart` when the
// platform shell started sharing the settings screens that use it: the amount
// of room to leave is a property of the shell, and the platform one docks its
// bar rather than floating it. Re-exported here because twenty screens import
// it from this file and none of them has an opinion about where it lives.
export '../../core/widgets/shell_insets.dart' show FloatingNavPadding;

/// Hosts the four bottom-nav branches. The glass bar floats above content.
///
/// **One shell, one router, adapted destinations.** The four branches always
/// exist — there is no second navigation graph for a scoped administrator, and
/// no branch is created or destroyed as a grant changes. What adapts is which
/// destinations are *offered*, so a session with nothing to do in a module is
/// not handed a tab into it. Removing the row is decluttering, never
/// authorization: each destination behind it keeps its own route guard, so a
/// deep link past a hidden tab is refused by the router, not by the bar.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  /// The four branch root locations, in branch order.
  ///
  /// Swiping between branches is only offered while one of these is the current
  /// page. Drilled in — a detachment group's detachments, a member form, the
  /// profile page — a horizontal swipe would jump the user out of the stack
  /// they are working in, which is not what the gesture means anywhere else in
  /// the app.
  ///
  /// `/detachment` sits beside `/detachment-groups` because the second branch
  /// has two roots depending on the session: a session that may not stand
  /// containers up is redirected past the detachment group list to its own
  /// detachments, and that page is then its branch root in every sense that
  /// matters here.
  static const _branchRoots = [
    '/home',
    '/detachment-groups',
    '/detachment',
    '/workshop',
    '/more',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(adminViewProvider);
    final workshopsEnabled = ref.watch(
      tenantFeatureAvailableProvider(TenantFeatureKey.workshops),
    );
    final branchIndex = navigationShell.currentIndex;

    // Branch order is fixed; visibility is not. A branch the session is
    // *currently standing in* is always offered, so a grant that narrows
    // mid-session cannot leave the bar with no row selected.
    final visibleBranches = <int>[
      0,
      1,
      // Workshops are organisation-level and hold no detachment scope, so the
      // question is simply whether this session has any workshop work at all.
      // Viewing a workshop needs no capability (`workshop.view` was dropped on
      // 2026-09-02 for gating nothing) — which is exactly why the tab, and not
      // the route, is what goes away.
      if (workshopsEnabled && view.workshops) 2,
      3,
    ];

    final destinations = [
      for (final branch in visibleBranches)
        GlassNavDestination(
          icon: _icons[branch]!,
          label: _labelFor(branch, view),
        ),
    ];

    // Display position of the branch the user is in. A branch that is somehow
    // not in the list falls back to the first row rather than to -1, which the
    // bar would render as "nothing selected".
    final index = visibleBranches.indexOf(branchIndex).clamp(0, 1 << 30);
    final atBranchRoot =
        _branchRoots.contains(GoRouterState.of(context).uri.path);

    void goTo(int displayIndex) {
      final branch = visibleBranches[displayIndex];
      navigationShell.goBranch(branch, initialLocation: branch == branchIndex);
    }

    return Scaffold(
      // The nav floats above the body via a Stack, not the classic
      // bottomNavigationBar slot, so it doesn't push content up.
      //
      // The demo bar is the one thing above the pages rather than inside
      // them: it belongs to the session, not to a screen, and it renders as
      // nothing at all for every real session.
      body: Column(children: [
        const DemoTrialBar(),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                // Same gesture and the same direction rule as the detail-shell
                // tabs. A detail shell nested inside a branch has its own
                // SwipeTabs, and being deeper in the tree it wins the gesture
                // arena — so swiping a detachment's tabs never also moves the
                // bottom nav.
                child: SwipeTabs(
                  currentIndex: index,
                  tabCount: destinations.length,
                  enabled: atBranchRoot,
                  onSwitch: goTo,
                  child: TabSwitchTransition(
                    index: branchIndex,
                    child: navigationShell,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: GlassBottomNav(
                  destinations: destinations,
                  currentIndex: index,
                  onDestinationSelected: goTo,
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  static const _icons = <int, IconData>{
    0: Icons.home_rounded,
    1: Icons.flag_rounded,
    2: Icons.school_rounded,
    3: Icons.more_horiz_rounded,
  };

  /// The second branch is named for what it opens on. A session that may create
  /// containers lands on the detachment group list and the row says so; every
  /// other session is redirected past it to its own detachments, and a row
  /// labelled "الجهات" that opens a list of detachments would be a small lie
  /// told on every screen.
  static String _labelFor(int branch, AdminView view) => switch (branch) {
        0 => S.navHome,
        1 => view.createsContainers
            ? S.navDetachmentGroups
            : S.detachmentListTitle,
        2 => S.navWorkshop,
        _ => S.navMore,
      };
}
