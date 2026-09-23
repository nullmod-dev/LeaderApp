import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/problem/problem.dart';
import 'auth_providers.dart';

/// What a revoke attempt actually did — the answer the Security screen turns
/// into one short line for the admin.
///
/// Every value below says whether anything changed, because that is the
/// question a failed security action has to answer. Only [revoked] and
/// [alreadyGone] change the session list; nothing else touches it.
enum SessionRevokeOutcome {
  /// The server confirmed it. The list is re-read.
  revoked,

  /// The server says that session does not exist — revoked from another
  /// device, or expired on its own, between the list being read and the
  /// button being tapped. Nothing was changed by this request, but the list
  /// on screen is stale, so it is re-read.
  alreadyGone,

  /// `not_permitted`. Nothing changed.
  notPermitted,

  /// `authentication_expired` — the session making the request is itself no
  /// longer valid. Nothing changed, and the account read is invalidated so
  /// the router's auth gate takes the app out of the authenticated stack.
  sessionExpired,

  /// Nothing reached the server. Nothing changed, and nothing is queued: a
  /// session revocation is not an outbox operation.
  offline,

  /// Anything else. Nothing is known to have changed.
  failed,
}

/// The single owner of "end another session".
///
/// Exists for the same reason [SignOutController] does: the request has a
/// duplicate-tap guard, a rule about when the list may be refreshed, and a
/// rule about what an expired session means — and none of those survive being
/// written inline in a widget's callback. A second tap on the same row, or on
/// a row rebuilt underneath the first tap, is dropped rather than sent.
///
/// The state is the set of session ids with a request in flight, so a row can
/// show its own progress without a widget holding a flag the controller
/// cannot see.
///
/// **Not queued when offline.** Revoking a session is a server-side security
/// act; deferring it into the sync outbox would tell the admin a device was
/// locked out while it was still signed in. The offline answer is honest and
/// terminal — see `MTM-Front-Back` §13.
class SessionRevokeController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  bool isRevoking(String id) => state.contains(id);

  /// Ends the session with [id].
  ///
  /// Returns `null` when a request for that same session was already in
  /// flight — the second call is dropped, not queued.
  Future<SessionRevokeOutcome?> revoke(String id) async {
    if (state.contains(id)) return null;
    state = {...state, id};
    try {
      final result = await ref.read(authRepositoryProvider).revokeSession(id);
      final outcome = result.when(
        success: (_, {stale = false}) => SessionRevokeOutcome.revoked,
        // Branching on the code, never the message — the server's text is
        // never read by the app and never shown to the user.
        failure: (_, code) => switch (ProblemCode.parse(code)) {
          ProblemCode.notFound => SessionRevokeOutcome.alreadyGone,
          ProblemCode.notPermitted => SessionRevokeOutcome.notPermitted,
          ProblemCode.authenticationExpired =>
            SessionRevokeOutcome.sessionExpired,
          _ => SessionRevokeOutcome.failed,
        },
        offline: (_) => SessionRevokeOutcome.offline,
      );

      switch (outcome) {
        // The list is re-read only once the server has confirmed the row is
        // gone. A failed revoke leaves the session exactly where it was.
        case SessionRevokeOutcome.revoked:
        case SessionRevokeOutcome.alreadyGone:
          ref.invalidate(sessionsProvider);
        // The base session read, not the derived view — re-reading it is what
        // flips `authGateProvider` and closes every protected route.
        case SessionRevokeOutcome.sessionExpired:
          ref.invalidate(currentUserResultProvider);
        case SessionRevokeOutcome.notPermitted:
        case SessionRevokeOutcome.offline:
        case SessionRevokeOutcome.failed:
          break;
      }
      return outcome;
    } finally {
      state = {...state}..remove(id);
    }
  }
}

final sessionRevokeControllerProvider =
    NotifierProvider<SessionRevokeController, Set<String>>(
  SessionRevokeController.new,
);
