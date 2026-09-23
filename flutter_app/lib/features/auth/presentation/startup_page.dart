import 'package:flutter/material.dart';

import 'leader_intro.dart';

/// `/startup` — the app's `initialLocation`, and the screen a launch belongs
/// to until the classifier can say where it really belongs.
///
/// **The problem it solves.** `initialLocation` used to be `/home`, and the
/// session read is asynchronous, so a cold start rendered the tenant
/// dashboard — its app bar, its bottom nav, its repository reads — for as long
/// as the restore took, and then redirected. For a signed-out person that was
/// a flash of an authenticated screen; for a Super Admin a flash of the wrong
/// product. This is the surface the router holds on instead.
///
/// **What it draws is the Leader intro.** The screen used to be a deliberately
/// plain mark, a sentence and a progress bar, on the reasoning that a local
/// restore usually finishes in a frame or two and a staged animation would
/// turn "already done" into "please wait". That reasoning still holds for the
/// *waiting*, and [LeaderIntro] keeps it: the sentence and the "still working"
/// treatment only appear on a launch that is genuinely slow. What changed is
/// that a cold launch now also gets the product's brand moment, on a ground
/// shared with the sign-in screen it hands over to — see `IntroGate` for why
/// that hold lives in the routing decision and not in a widget's timer.
///
/// **It says nothing about the network**, because the restore does not use
/// one, and it shows no account, organisation or last-opened screen, because a
/// launch that has not established a session must not be able to leak the
/// previous one's.
class StartupPage extends StatelessWidget {
  const StartupPage({super.key});

  /// The app's `initialLocation`.
  ///
  /// Duplicated from `StartupDestination.restoring.location` because a `const`
  /// field cannot read an enum member, and the router needs a const path.
  /// `startup_classifier_test.dart` fails if the two ever disagree — the same
  /// treatment `UpgradeRequiredPage.location` gets.
  static const String location = '/startup';

  @override
  Widget build(BuildContext context) => const LeaderIntro();
}
