import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the cold-launch brand intro has got to.
enum IntroPhase {
  /// This process is not playing one. Every widget test, every render
  /// harness and every re-entry to `/startup` after the first launch sits
  /// here, and the startup classifier behaves exactly as it did before the
  /// intro existed.
  idle,

  /// The intro is on screen and the app is being held on `/startup` for it.
  holding,

  /// It has played. The classifier is free again, and nothing re-arms it for
  /// the life of the process.
  done,
}

/// The one thing that decides whether a launch shows the Leader intro.
///
/// **Why a gate and not a timer inside the screen.** The router moves off
/// `/startup` the instant the session classifier changes its mind, and on a
/// warm device that is frame two — so an intro that merely animated would be
/// cut off mid-entrance and the launch would flash. The hold has to live
/// where the routing decision is made, which is why [IntroPhase.holding] is
/// an *input to* `resolveStartup` rather than a delay bolted onto a screen.
///
/// **It is cold launch only, by construction.** `main()` arms it once, before
/// `runApp`; [build] consumes that arming the first time the provider is
/// read, and nothing can set it again. Signing out, switching tabs, returning
/// from the background or landing back on `/startup` for any other reason
/// therefore cannot replay it — there is no persisted "seen the intro" flag
/// anywhere, because process lifetime is exactly the right scope for this and
/// storing it would be a durable record of something that does not matter
/// tomorrow.
///
/// **It cannot stick.** Arming starts a [ceiling] timer that finishes the
/// gate whatever the screen does, so a disposed, never-mounted or crashed
/// intro widget costs at most that long — it can never strand the app on the
/// launch surface.
///
/// **It delays; it never decides.** The only outcome it can produce is
/// `restoring`, which is the surface the app already shows while it works out
/// where a launch belongs. Every real answer below it — the upgrade gate, the
/// session, the tenant lifecycle — is unchanged and applies the moment the
/// gate releases.
class IntroGate extends Notifier<IntroPhase> {
  /// The longest the gate will hold on its own. Comfortably above the
  /// intro's own length, so in practice the screen always releases it first.
  static const Duration ceiling = Duration(milliseconds: 2900);

  static bool _armed = false;

  /// Called once from `main()`, before `runApp`, so the very first read of
  /// this provider already reports [IntroPhase.holding]. Arming *inside*
  /// `initState` would write provider state while GoRouter's
  /// `refreshListenable` is still mounting, which is the reentrant
  /// rebuild-during-mount `main.dart` already documents avoiding.
  static void armColdLaunch() => _armed = true;

  /// Undo an arming that no launch consumed. Only a test needs this.
  @visibleForTesting
  static void resetForTest() => _armed = false;

  Timer? _ceiling;

  @override
  IntroPhase build() {
    if (!_armed) return IntroPhase.idle;
    // One process, one intro: consumed here rather than on completion, so a
    // provider container rebuilt for any reason cannot start a second one.
    _armed = false;
    _ceiling = Timer(ceiling, finish);
    ref.onDispose(() => _ceiling?.cancel());
    return IntroPhase.holding;
  }

  /// The intro has finished its sequence (or the ceiling ran out). Idempotent,
  /// and it can never move the gate back into a hold.
  void finish() {
    _ceiling?.cancel();
    _ceiling = null;
    if (state == IntroPhase.holding) state = IntroPhase.done;
  }
}

final introGateProvider =
    NotifierProvider<IntroGate, IntroPhase>(IntroGate.new);
