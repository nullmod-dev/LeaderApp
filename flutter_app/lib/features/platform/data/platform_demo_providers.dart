/// The Super Admin's side of the Customer Demo control plane.
///
/// **This file exists to hold the authorization**, and that is the whole
/// reason it is not in `features/demo`. The control plane itself
/// (`demo_control_plane.dart`) must not import `features/auth` — a trial is
/// started by the session that is *in* it — so every administrative mutation
/// there demands a [DemoPolicyActor] the caller had to be able to build. This
/// is where one is built, and it is built from the platform session or not at
/// all.
///
/// **Authorization, not a role check on a widget.** The page never asks "am I
/// a Super Admin" to decide what to draw. It asks the control plane to do
/// something and is refused with `not_authorized` if the session cannot
/// authorize it — the same shape a backend answers with, and the same shape
/// the page would get if the route were reached some other way.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/domain/auth_models.dart';
import '../../demo/data/demo_control_plane.dart';
import '../../demo/domain/demo_policy.dart';

/// The platform administrator acting on Demo policy, or `null` when this
/// session may not.
///
/// Session-bound by construction: it is derived from the signed-in account, so
/// signing out or switching accounts withdraws it on the next read rather than
/// leaving an authority behind.
final platformDemoActorProvider = Provider<DemoPolicyActor?>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null || user.role != AuthRole.superAdmin) return null;
  return DemoPolicyActor(accountId: user.id, displayName: user.name);
});

/// The policy as the operator sees it.
final demoPolicyProvider = Provider<DemoPolicy>(
  (ref) => ref.watch(demoControlPlaneProvider).policy,
);

/// Session counts as of now, for the summary strip.
///
/// A record's stored status is a claim about when it was written, so every
/// count is evaluated against the clock — see [DemoSession.statusAt].
@immutable
class DemoSessionCounts {
  const DemoSessionCounts({
    required this.active,
    required this.expired,
    required this.terminated,
  });

  final int active;
  final int expired;
  final int terminated;

  int get total => active + expired + terminated;
}

final demoSessionCountsProvider = Provider<DemoSessionCounts>((ref) {
  final state = ref.watch(demoControlPlaneProvider);
  final now = ref.watch(clockProvider)();
  return DemoSessionCounts(
    active: state.countAt(now, DemoSessionStatus.active),
    expired: state.countAt(now, DemoSessionStatus.expired),
    terminated: state.countAt(now, DemoSessionStatus.terminated),
  );
});

/// Every running trial, soonest to expire first.
///
/// That order, not newest-first: the list is read to decide what to do about
/// the trials that are nearly over, and a start time is the one field that
/// never changes what an operator would do next.
final activeDemoSessionsProvider = Provider<List<DemoSession>>((ref) {
  final now = ref.watch(clockProvider)();
  final active = ref.watch(demoControlPlaneProvider).activeAt(now).toList();
  active.sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
  return List.unmodifiable(active);
});

/// The five administrative actions, each carrying its own authorization.
///
/// A plain object rather than a `Notifier`: the control plane is synchronous
/// in this build, so there is no in-flight state to hold and a busy flag no
/// screen could ever observe would be a lie about what the page knows. When a
/// real endpoint replaces the control plane, the asynchrony arrives here — the
/// page already reads every answer as a [Result].
class PlatformDemoActions {
  const PlatformDemoActions(this._ref);

  final Ref _ref;

  DemoControlPlane get _plane => _ref.read(demoControlPlaneProvider.notifier);
  DemoPolicyActor? get _actor => _ref.read(platformDemoActorProvider);

  Result<DemoPolicy> setEnabled(bool enabled) =>
      _plane.setEnabled(enabled, actor: _actor);

  Result<DemoPolicy> setDefaultDuration(Duration duration) =>
      _plane.setDefaultDuration(duration, actor: _actor);

  Result<DemoSession> terminate(String sessionId) =>
      _plane.terminate(sessionId, actor: _actor);

  Result<int> terminateAllActive() => _plane.terminateAllActive(actor: _actor);

  Result<int> cleanExpired() => _plane.cleanExpired(actor: _actor);
}

final platformDemoActionsProvider =
    Provider<PlatformDemoActions>(PlatformDemoActions.new);
