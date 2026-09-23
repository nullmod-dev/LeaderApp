import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../../demo/data/demo_control_plane.dart';
import 'auth_providers.dart';
import 'onboarding_controller.dart';

/// Whether a sign-out is in flight. The one piece of state a sign-out has.
enum SignOutPhase { idle, inProgress }

/// The single owner of sign-out.
///
/// Sign-out is offered from two places — the Settings hub and the account
/// screen — and both must behave identically: one request per gesture, the
/// session providers cleared only on a real success, and the failure handed
/// back to the caller rather than swallowed. Duplicating that in two widgets
/// is how the two drift, so neither widget owns it.
///
/// The duplicate-tap guard lives here rather than in a widget's `setState`
/// because a second tap can arrive from the *other* entry point, or from a
/// rebuilt widget, and a guard held in one widget's state cannot see it.
class SignOutController extends Notifier<SignOutPhase> {
  @override
  SignOutPhase build() => SignOutPhase.idle;

  /// Signs the session out.
  ///
  /// Returns the repository's answer, or `null` when a sign-out was already
  /// running — the second call is dropped, not queued. On success the session
  /// providers are invalidated, which is what actually clears the
  /// authenticated state: `capabilitiesProvider` falls back to
  /// `Capabilities.none` and the router's auth gate turns the app's protected
  /// routes off.
  Future<Result<void>?> signOut() async {
    if (state == SignOutPhase.inProgress) return null;
    state = SignOutPhase.inProgress;
    try {
      // A trial the holder walks out of is a trial that ended early, and the
      // operator's list is where that is visible. Done before the request so
      // the record closes even if the sign-out itself fails; a trial nobody is
      // in has no reason to stay open. `null` for every non-demo session, and
      // the control plane ignores an id it no longer holds.
      final demoSessionId = ref.read(activeDemoSessionIdProvider);
      if (demoSessionId != null) {
        ref
            .read(demoControlPlaneProvider.notifier)
            .endOwnSession(demoSessionId);
        ref.read(activeDemoSessionIdProvider.notifier).state = null;
      }
      // Point 17A — a pre-session identity (pending verification or a
      // restricted onboarding session) has no full session to revoke. The
      // same sign-out ends *its* journey instead, so every holding screen
      // keeps exactly one exit.
      if (ref.read(authEntryStateProvider).isActive) {
        return await ref.read(onboardingControllerProvider.notifier).abandon();
      }
      final result = await ref.read(authRepositoryProvider).signOut();
      // The session read is cleared on success — and also when the server
      // says the token was already invalid. A `401` here means the session
      // this request carried is gone server-side; leaving the app looking
      // authenticated afterwards is the one outcome that must not happen, so
      // the gate is let take over rather than the failure being reported as
      // "still signed in".
      final expired = result.when(
        success: (_, {stale = false}) => false,
        failure: (_, code) =>
            ProblemCode.parse(code) == ProblemCode.authenticationExpired,
        offline: (_) => false,
      );
      if (result.isSuccess || expired) {
        // The base, not the derived view — see `currentUserResultProvider`.
        ref.invalidate(currentUserResultProvider);
        ref.invalidate(sessionsProvider);
        // Session state, not just the account. A forced lifecycle state is
        // part of *this* session and must not outlive it: leaving it set
        // would hand the next sign-in a suspended or expired-demo verdict
        // that belongs to nobody. Always `null` outside a debug build — see
        // `sessionAccessOverrideProvider`.
        ref.invalidate(sessionAccessOverrideProvider);
      }
      return result;
    } finally {
      state = SignOutPhase.idle;
    }
  }
}

final signOutControllerProvider =
    NotifierProvider<SignOutController, SignOutPhase>(SignOutController.new);
