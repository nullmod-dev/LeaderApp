/// The Customer Demo control plane, as this build models it.
///
/// ## DEVELOPMENT AND TEST ONLY — this is not production persistence
///
/// Every session record and policy edit below lives in **process memory** and
/// is gone when the process is. That is not a limitation to be fixed here: it
/// is the honest shape of a client-side stand-in, and naming it is what stops
/// the rest of the app being written as though a device could be authoritative
/// about other people's trials.
///
/// Nothing here may be read as a production guarantee. In particular a
/// restart, a reinstall or a second device **re-derives none of this**, so an
/// operator's "terminate" that only happened here did not happen. A production
/// build overrides [demoControlPlaneProvider] with an adapter over the real
/// endpoints (`BACKEND-HANDOFF.md` §12) and this file survives as the
/// deterministic fake the tests and the development build run against.
///
/// It is deliberately *not* persisted to `LocalStore` for the same reason:
/// persisting it would let an operator's "terminate" be undone by reinstalling
/// the app, and would put a list of other people's sessions in this device's
/// storage.
///
/// **One object, because there is one question.** Whether a trial may start,
/// how long it runs, and which trials are running are the same fact seen from
/// three sides — a login screen asks the first, a Super Admin administers all
/// three, and a running trial is retired by the third. Splitting them across a
/// policy provider and a session registry would let the login screen and the
/// operator disagree about whether the offer exists.
///
/// **Server time is the authority, not this clock.** [clockProvider] here
/// decides what a *development* build renders and what a test pins; it is a
/// display and simulation clock. The invariant that matters in production is
/// upstream of it, in `sessionAccessProvider`: a backend envelope that says
/// `expired` is never overturned locally, and the control-plane verdict may
/// only narrow an active demo to expired — never the reverse. No local clock
/// change can therefore extend a trial.
///
/// **It imports no authentication.** The account id and display name arrive as
/// arguments, and every administrative mutation demands a [DemoPolicyActor]
/// the caller had to be authorized to build. That is what keeps this file out
/// of an import cycle with `features/auth`, which is where the session that
/// *starts* a trial lives.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../auth/domain/session_access.dart' show DemoMode;
import '../domain/demo_policy.dart';

/// Everything the control plane knows: the policy, and every session record it
/// still holds.
@immutable
class DemoControlPlaneState {
  const DemoControlPlaneState({required this.policy, required this.sessions});

  final DemoPolicy policy;

  /// Newest first — the order an operator reads a session list in.
  final List<DemoSession> sessions;

  DemoSession? sessionById(String id) {
    for (final session in sessions) {
      if (session.demoSessionId == id) return session;
    }
    return null;
  }

  /// The trial [accountId] is already inside as of [now], if any.
  ///
  /// One identity has at most one running trial — see
  /// [DemoControlPlane.startSession]. This is how that is checked.
  DemoSession? activeSessionFor(String accountId, DateTime now) {
    for (final session in sessions) {
      if (session.accountId == accountId && session.isActiveAt(now)) {
        return session;
      }
    }
    return null;
  }

  /// Sessions whose window is still open **as of [now]**.
  List<DemoSession> activeAt(DateTime now) =>
      sessions.where((s) => s.isActiveAt(now)).toList(growable: false);

  int countAt(DateTime now, DemoSessionStatus status) =>
      sessions.where((s) => s.statusAt(now) == status).length;

  DemoControlPlaneState copyWith({
    DemoPolicy? policy,
    List<DemoSession>? sessions,
  }) =>
      DemoControlPlaneState(
        policy: policy ?? this.policy,
        sessions: sessions ?? this.sessions,
      );
}

/// Sessions the control plane already holds when the app starts.
///
/// A development seam, overridden in tests so a count assertion does not
/// depend on fixture data. The default seeds two records — one running, one
/// already expired — because an operations screen whose every list is empty
/// cannot be reviewed for the layout it will actually have.
final demoControlPlaneSeedProvider =
    Provider<List<DemoSession>>((ref) {
  final now = ref.watch(clockProvider)();
  return [
    DemoSession(
      demoSessionId: 'demo_seed_active',
      accountId: 'acc_demo_seed_1',
      demoWorkspaceId: 'dws_seed_1',
      displayName: 'زائر تجربة ١',
      startedAt: now.subtract(const Duration(hours: 3)),
      expiresAt: now.add(const Duration(hours: 21)),
      status: DemoSessionStatus.active,
      policyRevision: 1,
    ),
    DemoSession(
      demoSessionId: 'demo_seed_expired',
      accountId: 'acc_demo_seed_2',
      demoWorkspaceId: 'dws_seed_2',
      displayName: 'زائر تجربة ٢',
      startedAt: now.subtract(const Duration(hours: 30)),
      expiresAt: now.subtract(const Duration(hours: 6)),
      status: DemoSessionStatus.active,
      policyRevision: 1,
    ),
  ];
});

/// Refusal codes. Branch on these, never on a message (`Problem` §code).
abstract final class DemoControlPlaneCodes {
  /// The caller presented no Super Admin authorization.
  static const notAuthorized = 'not_authorized';

  /// The global offer is switched off, so no new trial may start.
  static const demoUnavailable = 'demo_unavailable';

  /// The session id names nothing this control plane holds.
  static const sessionNotFound = 'demo_session_not_found';

  /// The session is already expired or terminated; there is nothing to end.
  static const sessionNotActive = 'demo_session_not_active';
}

class DemoControlPlane extends Notifier<DemoControlPlaneState> {
  /// Makes an id unique when two trials start inside the same millisecond.
  int _sequence = 0;

  @override
  DemoControlPlaneState build() => DemoControlPlaneState(
        policy: DemoPolicy.initial,
        sessions: List.unmodifiable(ref.watch(demoControlPlaneSeedProvider)),
      );

  DateTime get _now => ref.read(clockProvider)();

  /// Switches the offer on or off.
  ///
  /// **Off blocks creation and nothing else.** Every running trial keeps the
  /// window it was given. Ending them is [terminateAllActive] — a separate
  /// action an operator has to choose, because silently signing out everybody
  /// mid-demo is not what "stop offering trials" means to the person who
  /// flipped the switch.
  Result<DemoPolicy> setEnabled(bool enabled, {DemoPolicyActor? actor}) {
    if (actor == null) {
      return const Failure('', code: DemoControlPlaneCodes.notAuthorized);
    }
    if (state.policy.enabled == enabled) return Success(state.policy);
    return Success(_writePolicy(
      state.policy.copyWith(enabled: enabled),
      actor: actor,
    ));
  }

  /// Changes the window **new** trials are stamped with.
  ///
  /// Existing sessions keep their own `expiresAt`: they were authorized under
  /// the revision they record, and rewriting that would move an expiry a user
  /// has already been told about.
  Result<DemoPolicy> setDefaultDuration(
    Duration duration, {
    DemoPolicyActor? actor,
  }) {
    if (actor == null) {
      return const Failure('', code: DemoControlPlaneCodes.notAuthorized);
    }
    final clamped =
        duration < DemoDurationPolicy.minimum ? DemoDurationPolicy.minimum : duration;
    if (state.policy.defaultDuration == clamped) return Success(state.policy);
    return Success(_writePolicy(
      state.policy.copyWith(defaultDuration: clamped),
      actor: actor,
    ));
  }

  DemoPolicy _writePolicy(DemoPolicy next, {required DemoPolicyActor actor}) {
    final written = next.copyWith(
      revision: state.policy.revision + 1,
      updatedBy: actor,
      updatedAt: _now,
    );
    state = state.copyWith(policy: written);
    return written;
  }

  /// Records a trial for [accountId], resumes the one it already has, or
  /// refuses because the offer is off.
  ///
  /// Not an administrative action — this is the user's own start, authorized
  /// by the policy rather than by an actor. The window is stamped here, once,
  /// from the policy in force now.
  ///
  /// **One running trial per identity.** Pressing Start twice — a double tap,
  /// a retry after a dropped response, a second device — **resumes the running
  /// session** rather than creating a second one. Duplicates would give one
  /// person two windows to spend and would make the operator's list count
  /// people wrong, and there is no product requirement that an identity hold
  /// two trials at once. Resuming answers [Success] with the *existing*
  /// record, so the caller cannot tell the paths apart and does not have to.
  ///
  /// **Resuming is not starting**, so it is checked before [DemoPolicy.enabled]
  /// and is allowed while the offer is switched off: disabling blocks *new*
  /// trials and leaves running ones alone (see [setEnabled]), and refusing to
  /// hand somebody back the trial they are already inside would be terminating
  /// it by another name.
  Result<DemoSession> startSession({
    required String accountId,
    String? displayName,
  }) {
    final resumed = state.activeSessionFor(accountId, _now);
    if (resumed != null) return Success(resumed);
    if (!state.policy.enabled) {
      return const Failure('', code: DemoControlPlaneCodes.demoUnavailable);
    }
    final now = _now;
    final id = 'demo_${now.millisecondsSinceEpoch}_${_sequence++}';
    final session = DemoSession(
      demoSessionId: id,
      accountId: accountId,
      demoWorkspaceId: 'dws_$id',
      displayName: displayName,
      startedAt: now,
      expiresAt: now.add(state.policy.defaultDuration),
      status: DemoSessionStatus.active,
      policyRevision: state.policy.revision,
    );
    state = state.copyWith(
      sessions: List.unmodifiable([session, ...state.sessions]),
    );
    return Success(session);
  }

  /// Ends the trial **its own holder** is sitting in — the «إنهاء التجربة»
  /// button, not an operator's action.
  ///
  /// It needs no [DemoPolicyActor] for the same reason [startSession] does
  /// not: the person ending their own trial is authorized by holding it. The
  /// record lands in the operator's list as
  /// [DemoSessionStatus.terminated] — *not* a fourth "self-ended" state,
  /// because from every reader's side "this trial stopped early" is one fact
  /// however it was asked for. Who asked is recorded as
  /// [DemoSessionTerminationReason.userEnded].
  void endOwnSession(String sessionId) =>
      _end(sessionId, _now, DemoSessionTerminationReason.userEnded);

  /// Drops the record of a trial whose start did not complete.
  ///
  /// The control plane records a session *before* the session exists, so that
  /// a window is stamped by the authority that granted it. When the rest of
  /// the start then fails, the trial never began: it is not a trial that ended
  /// early, and leaving a `terminated` record would put a session on the
  /// operator's list that nobody was ever in. Removing it is what makes the
  /// start atomic from the application's side.
  ///
  /// Only ever the caller's *own* just-created record, and only while it is
  /// still active — a session that has run cannot be un-run this way.
  void discardFailedStart(String sessionId) {
    final existing = state.sessionById(sessionId);
    if (existing == null || !existing.isActiveAt(_now)) return;
    state = state.copyWith(
      sessions: List.unmodifiable([
        for (final s in state.sessions)
          if (s.demoSessionId != sessionId) s,
      ]),
    );
  }

  /// Ends one running trial early.
  Result<DemoSession> terminate(String sessionId, {DemoPolicyActor? actor}) {
    if (actor == null) {
      return const Failure('', code: DemoControlPlaneCodes.notAuthorized);
    }
    final now = _now;
    final existing = state.sessionById(sessionId);
    if (existing == null) {
      return const Failure('', code: DemoControlPlaneCodes.sessionNotFound);
    }
    if (!existing.isActiveAt(now)) {
      return const Failure('', code: DemoControlPlaneCodes.sessionNotActive);
    }
    return Success(
      _end(sessionId, now, DemoSessionTerminationReason.superAdminTerminated)!,
    );
  }

  /// Marks one session terminated, or answers `null` when there is nothing
  /// running under that id. Shared by the operator's action and the holder's.
  DemoSession? _end(
    String sessionId,
    DateTime now,
    DemoSessionTerminationReason reason,
  ) {
    final existing = state.sessionById(sessionId);
    if (existing == null || !existing.isActiveAt(now)) return null;
    final ended = existing.copyWith(
      status: DemoSessionStatus.terminated,
      endedAt: now,
      terminationReason: reason,
    );
    state = state.copyWith(
      sessions: List.unmodifiable([
        for (final s in state.sessions)
          s.demoSessionId == sessionId ? ended : s,
      ]),
    );
    return ended;
  }

  /// Ends every trial whose window is still open. Answers how many.
  Result<int> terminateAllActive({DemoPolicyActor? actor}) {
    if (actor == null) {
      return const Failure('', code: DemoControlPlaneCodes.notAuthorized);
    }
    final now = _now;
    var ended = 0;
    final next = [
      for (final session in state.sessions)
        if (session.isActiveAt(now))
          () {
            ended++;
            return session.copyWith(
              status: DemoSessionStatus.terminated,
              endedAt: now,
              terminationReason: DemoSessionTerminationReason.terminateAll,
            );
          }()
        else
          session,
    ];
    if (ended == 0) return const Success(0);
    state = state.copyWith(sessions: List.unmodifiable(next));
    return Success(ended);
  }

  /// Drops the **operational** records of trials that have already closed by
  /// time.
  ///
  /// **This is not a history delete, and must never become one.** Two
  /// different things are being kept about a finished trial and only the first
  /// is touched here:
  ///
  /// 1. the *operational* record — the row an operator reads to decide what to
  ///    do about running trials. Once a trial has closed it decides nothing,
  ///    and a list that only grows is a list that stops being read.
  /// 2. the *Audit* record — `customer_demo_session_started` /
  ///    `_terminated` / `_expired`, backend-authored and immutable
  ///    (`BACKEND-HANDOFF.md` §10, §12). **This action does not reach it.**
  ///    Audit is retained under the backend's retention rules, and no operator
  ///    gesture in this product erases it.
  ///
  /// So the worst an over-eager cleanup can cost is an operator's convenience,
  /// never the evidence that a trial existed. A production adapter that
  /// implemented `POST …/sessions/cleanup` as a history purge would be
  /// implementing a different operation than the one this button offers.
  ///
  /// Terminated records are additionally **kept in the operational list**:
  /// somebody decided to end those, and the list is where that decision stays
  /// visible until retention removes it. Expiry is the ordinary end of a trial
  /// and leaves nothing to review. What retention *is* — how long a closed
  /// record lives before the backend drops it on its own — is deployment
  /// policy this client does not invent (`BACKEND-HANDOFF.md` §12).
  Result<int> cleanExpired({DemoPolicyActor? actor}) {
    if (actor == null) {
      return const Failure('', code: DemoControlPlaneCodes.notAuthorized);
    }
    final now = _now;
    final kept = state.sessions
        .where((s) => s.statusAt(now) != DemoSessionStatus.expired)
        .toList(growable: false);
    final removed = state.sessions.length - kept.length;
    if (removed == 0) return const Success(0);
    state = state.copyWith(sessions: List.unmodifiable(kept));
    return Success(removed);
  }
}

final demoControlPlaneProvider =
    NotifierProvider<DemoControlPlane, DemoControlPlaneState>(
  DemoControlPlane.new,
);

/// The control-plane record for the trial **running on this device**, if any.
///
/// Set by `CustomerDemoController` when a trial starts and cleared when the
/// session ends. `null` for every real session, and for a demo whose record
/// the control plane never saw.
final activeDemoSessionIdProvider = StateProvider<String?>((ref) => null);

/// What the control plane says about this device's trial, in the vocabulary
/// the session envelope already speaks.
///
/// This is the **expiry and termination path**: `sessionAccessProvider`
/// overlays it onto the demo envelope, the startup classifier reads the
/// envelope, and `/demo-expired` is where a closed trial lands. It answers
/// [DemoMode.active] when no record is registered, so a session envelope that
/// says "demo" is never retired by a control plane that has never heard of it.
///
/// In production the backend is the authority and says the same thing by
/// refusing the request; this is how a mock build reproduces that without a
/// server.
final demoSessionVerdictProvider = Provider<DemoMode>((ref) {
  final id = ref.watch(activeDemoSessionIdProvider);
  if (id == null) return DemoMode.active;
  final session = ref.watch(demoControlPlaneProvider).sessionById(id);
  // A record the control plane has dropped is not a licence to keep going.
  if (session == null) return DemoMode.expired;
  final now = ref.watch(clockProvider)();
  return session.isActiveAt(now) ? DemoMode.active : DemoMode.expired;
});
