import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/build_mode.dart';
import '../../../core/result/result.dart';
import '../domain/auth_models.dart';
import 'auth_providers.dart';
import 'demo_personas.dart';
import 'mock_auth_repository.dart';

/// Which persona sign-in is in flight, or `null` when none is.
///
/// The state is the persona rather than a bare bool so tests can identify the
/// in-flight fixture and prove a second request is dropped. No Login widget
/// exposes this controller.
typedef DemoSignInPhase = DemoPersona?;

/// The single owner of development persona sign-in.
///
/// **It does not bypass the session pipeline.** A persona lands in exactly
/// the same place a typed credential does — `MockAuthRepository`'s session —
/// and then this invalidates `currentUserResultProvider`, which is what
/// re-derives `currentUserProvider`, `capabilitiesProvider`,
/// `adminViewProvider`, `authRoleProvider` and the router's gates. There is no
/// second session, no second capability source and no second sign-out: the
/// ordinary `SignOutController` ends a persona session like any other.
///
/// **Both release gates are checked here**, before the repository is even
/// looked at. [demoAccountsAllowed] is `const false` in a shipping artefact,
/// so [signInAs] compiles down to its refusal and everything it would have
/// reached — `DemoPersona`, the fixtures, `signInAsPersona` — is tree-shaken.
class DemoSignInController extends Notifier<DemoSignInPhase> {
  @override
  DemoSignInPhase build() => null;

  /// Authenticates as [persona].
  ///
  /// Returns the repository's answer, or `null` when a persona sign-in was
  /// already running — a second test-only request is dropped, not queued.
  Future<Result<AuthUser>?> signInAs(DemoPersona persona) async {
    if (!demoAccountsAllowed || !ref.read(demoAccountsEnabledProvider)) {
      return const Failure('غير متاح.', code: 'not_permitted');
    }
    if (state != null) return null;
    final repository = ref.read(authRepositoryProvider);
    if (repository is! MockAuthRepository) {
      // A build wired to a real repository has no demo accounts to offer,
      // whatever the flags say. Refused rather than asserted: this is the
      // seam a shipping build overrides, and it must fail closed.
      return const Failure('غير متاح.', code: 'not_permitted');
    }
    state = persona;
    try {
      final result = await repository.signInAsPersona(persona);
      if (result.isSuccess) {
        // The base, not the derived view — see `currentUserResultProvider`.
        // This is what turns the new account into the app's session.
        ref.invalidate(currentUserResultProvider);
        ref.invalidate(sessionsProvider);
        // And this is what makes it *observable* before the caller navigates.
        // Invalidating only schedules the re-read; the router's auth gate is
        // still answering `signedOut` until it lands, so a `context.go` fired
        // straight after would be redirected back to the login screen and
        // then left there — the gate opening a frame later moves nobody.
        await ref.read(currentUserResultProvider.future);
      }
      return result;
    } finally {
      state = null;
    }
  }
}

final demoSignInControllerProvider =
    NotifierProvider<DemoSignInController, DemoSignInPhase>(
  DemoSignInController.new,
);
