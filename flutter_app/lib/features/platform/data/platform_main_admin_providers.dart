import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/platform_main_admin_models.dart';
import '../domain/platform_main_admin_repository.dart';
import 'mock_platform_main_admin_repository.dart';
import 'saas_tenant_providers.dart';
import 'tenant_lifecycle_providers.dart';

/// Development/test knobs for the mock. A real build replaces
/// [platformMainAdminRepositoryProvider] and ignores this.
@immutable
class MainAdminMockConfig {
  const MainAdminMockConfig({
    this.mode = MockMainAdminMode.loaded,
    this.latency = const Duration(milliseconds: 280),
    this.scenarios = true,
  });

  final MockMainAdminMode mode;
  final Duration latency;
  final bool scenarios;
}

final mainAdminMockConfigProvider = Provider<MainAdminMockConfig>(
  (ref) => const MainAdminMockConfig(),
);

/// One control-plane seam per app. The session's surface is asked on every
/// call (the backend's job in production), so signing in as a tenant role
/// never reaches seat data and the mock's state is not reset by a sign-in.
final platformMainAdminRepositoryProvider =
    Provider<PlatformMainAdminRepository>((ref) {
  final config = ref.watch(mainAdminMockConfigProvider);
  return MockPlatformMainAdminRepository(
    store: ref.watch(platformTenantStoreProvider),
    clock: ref.watch(clockProvider),
    permitted: () => ref.read(authRoleProvider) == AuthRole.superAdmin,
    mode: config.mode,
    latency: config.latency,
    scenarios: config.scenarios,
  );
});

/// One tenant's Main Admin seat, re-read when its page opens and whenever a
/// Point 9 lifecycle change lands (the tenant-lifecycle rule depends on it).
final mainAdminAccountProvider = FutureProvider.autoDispose
    .family<Result<MainAdminAccountSnapshot>, String>((ref, tenantId) {
  ref.watch(tenantLifecycleRevisionProvider);
  return ref.watch(platformMainAdminRepositoryProvider).load(tenantId);
});

/// The one derived answer Point 14B reads to decide what the page may offer.
///
/// `null` while there is no snapshot to describe (loading, failure,
/// offline without cache) — those states come from [mainAdminAccountProvider]
/// itself. Stale and offline snapshots are shown read-only.
final mainAdminManagementProvider = Provider.autoDispose
    .family<MainAdminManagementView?, String>((ref, tenantId) {
  final result = ref.watch(mainAdminAccountProvider(tenantId)).valueOrNull;
  if (result == null) return null;
  final read = result.when<(MainAdminAccountSnapshot?, MainAdminFreshness)>(
    success: (snapshot, {stale = false}) => (
      snapshot,
      stale ? MainAdminFreshness.stale : MainAdminFreshness.confirmed,
    ),
    failure: (_, __) => (null, MainAdminFreshness.stale),
    offline: (cached) => (cached, MainAdminFreshness.offline),
  );
  final snapshot = read.$1;
  if (snapshot == null) return null;
  return MainAdminManagementPolicy.evaluate(
    sessionRole: ref.watch(authRoleProvider),
    snapshot: snapshot,
    freshness: read.$2,
    now: ref.watch(clockProvider)(),
  );
});

// ---------------------------------------------------------------------------
// Action controller
// ---------------------------------------------------------------------------

@immutable
class MainAdminActionState {
  const MainAdminActionState({this.submitting});

  final MainAdminAction? submitting;
  bool get isSubmitting => submitting != null;
}

sealed class MainAdminActionOutcome {
  const MainAdminActionOutcome();
}

class MainAdminActionSucceeded extends MainAdminActionOutcome {
  const MainAdminActionSucceeded(this.result);

  final MainAdminMutationResult result;
}

/// Refused locally — never queued. The caller keeps its draft.
class MainAdminActionOffline extends MainAdminActionOutcome {
  const MainAdminActionOffline();
}

/// The seat changed since it was reviewed; it has been reloaded.
class MainAdminActionStale extends MainAdminActionOutcome {
  const MainAdminActionStale();
}

/// The backend needs a fresh strong sign-in. Flutter verifies nothing itself;
/// the only honest path today is sign out and sign in again.
class MainAdminActionRecentAuthRequired extends MainAdminActionOutcome {
  const MainAdminActionRecentAuthRequired();
}

class MainAdminActionNotPermitted extends MainAdminActionOutcome {
  const MainAdminActionNotPermitted();
}

/// The tenant is missing, deleted, or its lifecycle forbids the action. The
/// tenant and the seat have been reloaded.
class MainAdminActionTenantUnavailable extends MainAdminActionOutcome {
  const MainAdminActionTenantUnavailable(this.code);

  final MainAdminProblemCode code;
}

/// A typed refusal the page explains in place (invalid reason/identity,
/// identity unavailable, replacement already pending, invalid transition,
/// throttled, idempotency conflict).
class MainAdminActionRejected extends MainAdminActionOutcome {
  const MainAdminActionRejected(this.code, this.message);

  final MainAdminProblemCode code;
  final String message;
}

/// Unknown code or server failure: safe generic copy, nothing replayed.
class MainAdminActionFailed extends MainAdminActionOutcome {
  const MainAdminActionFailed();
}

/// A second submit while one is in flight.
class MainAdminActionIgnored extends MainAdminActionOutcome {
  const MainAdminActionIgnored();
}

/// Single-flight, online-only. Never retries, never queues, never appends
/// Audit. Refreshes the seat, the tenant detail and the tenant list after
/// every success (a replacement changes the contact the list shows).
class MainAdminActionController extends Notifier<MainAdminActionState> {
  @override
  MainAdminActionState build() => const MainAdminActionState();

  PlatformMainAdminRepository get _repository =>
      ref.read(platformMainAdminRepositoryProvider);

  Future<MainAdminActionOutcome> resendSetup(
    ResendMainAdminSetupCommand command,
  ) =>
      _run(command, () => _repository.resendSetup(command));

  Future<MainAdminActionOutcome> suspend(SuspendMainAdminCommand command) =>
      _run(command, () => _repository.suspend(command));

  Future<MainAdminActionOutcome> reactivate(
    ReactivateMainAdminCommand command,
  ) =>
      _run(command, () => _repository.reactivate(command));

  Future<MainAdminActionOutcome> replace(ReplaceMainAdminCommand command) =>
      _run(command, () => _repository.replace(command));

  Future<MainAdminActionOutcome> cancelReplacement(
    CancelMainAdminReplacementCommand command,
  ) =>
      _run(command, () => _repository.cancelReplacement(command));

  Future<MainAdminActionOutcome> _run(
    MainAdminCommand command,
    Future<Result<MainAdminMutationResult>> Function() operation,
  ) async {
    if (state.isSubmitting) return const MainAdminActionIgnored();
    state = MainAdminActionState(submitting: command.action);
    try {
      final result = await operation();
      return result.when(
        success: (mutation, {stale = false}) {
          _refresh(command.tenantId, tenant: true);
          return MainAdminActionSucceeded(mutation);
        },
        failure: (message, code) {
          final parsed = MainAdminProblemCode.parse(code);
          if (parsed == null) return const MainAdminActionFailed();
          switch (parsed) {
            case MainAdminProblemCode.staleMainAdmin:
              _refresh(command.tenantId);
              return const MainAdminActionStale();
            case MainAdminProblemCode.recentAuthenticationRequired:
              return const MainAdminActionRecentAuthRequired();
            case MainAdminProblemCode.notPermitted:
              return const MainAdminActionNotPermitted();
            case MainAdminProblemCode.tenantNotFound ||
                  MainAdminProblemCode.tenantNotEligible ||
                  MainAdminProblemCode.tenantAlreadyDeleted:
              _refresh(command.tenantId, tenant: true);
              return MainAdminActionTenantUnavailable(parsed);
            case MainAdminProblemCode.invalidTransition ||
                  MainAdminProblemCode.replacementAlreadyPending ||
                  MainAdminProblemCode.idempotencyConflict:
              _refresh(command.tenantId);
              return MainAdminActionRejected(parsed, message);
            case MainAdminProblemCode.invalidReason ||
                  MainAdminProblemCode.invalidIdentity ||
                  MainAdminProblemCode.identityUnavailable ||
                  MainAdminProblemCode.setupResendThrottled:
              return MainAdminActionRejected(parsed, message);
          }
        },
        offline: (_) => const MainAdminActionOffline(),
      );
    } finally {
      state = const MainAdminActionState();
    }
  }

  void _refresh(String tenantId, {bool tenant = false}) {
    ref.invalidate(mainAdminAccountProvider(tenantId));
    if (tenant) {
      ref
        ..invalidate(saasTenantDetailProvider(tenantId))
        ..invalidate(saasTenantListProvider);
    }
  }
}

final mainAdminActionControllerProvider =
    NotifierProvider<MainAdminActionController, MainAdminActionState>(
  MainAdminActionController.new,
);
