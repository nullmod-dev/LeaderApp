import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/domain/auth_models.dart';
import '../domain/platform_break_glass_models.dart';
import '../domain/platform_break_glass_repository.dart';
import '../domain/saas_tenant_models.dart';
import 'mock_platform_break_glass_repository.dart';
import 'platform_break_glass_fixtures.dart';
import 'saas_tenant_providers.dart';
import 'tenant_lifecycle_providers.dart';

/// Development/test knobs for the mock. A real build replaces
/// [platformBreakGlassRepositoryProvider] and ignores this.
@immutable
class BreakGlassMockConfig {
  const BreakGlassMockConfig({
    this.mode = MockBreakGlassMode.loaded,
    this.seed = BreakGlassFixtureScenario.none,
    this.latency = const Duration(milliseconds: 280),
  });

  final MockBreakGlassMode mode;
  final BreakGlassFixtureScenario seed;
  final Duration latency;
}

final breakGlassMockConfigProvider = Provider<BreakGlassMockConfig>(
  (ref) => const BreakGlassMockConfig(),
);

/// Session-bound: the repository is rebuilt whenever the signed-in account
/// changes (sign-out, sign-in, another account), so no grant survives the
/// session that obtained it. Nothing here is persisted to device storage; an
/// app restart re-reads the backend and, offline, gets no usable authority.
final platformBreakGlassRepositoryProvider =
    Provider<PlatformBreakGlassRepository>((ref) {
  final session = ref.watch(currentUserProvider.select((value) {
    final user = value.valueOrNull;
    return (id: user?.id, name: user?.name, role: user?.role);
  }));
  final config = ref.watch(breakGlassMockConfigProvider);
  final actor = session.role == AuthRole.superAdmin && session.id != null
      ? BreakGlassInitiator(
          accountId: session.id!,
          displayName: session.name!,
        )
      : null;
  return MockPlatformBreakGlassRepository(
    store: ref.watch(platformTenantStoreProvider),
    clock: ref.watch(clockProvider),
    actor: actor,
    mode: config.mode,
    seed: config.seed,
    latency: config.latency,
  );
});

final breakGlassCurrentProvider =
    FutureProvider<Result<BreakGlassSnapshot>>((ref) {
  return ref.watch(platformBreakGlassRepositoryProvider).loadCurrent();
});

/// Active Platform tenants eligible to appear in the request picker.
///
/// This uses only the Platform tenant catalogue. It never initializes a
/// tenant-operational repository, and it applies the settled lifecycle policy
/// again even if a stale backend page contains an ineligible record.
final breakGlassEligibleTenantsProvider = FutureProvider.autoDispose
    .family<Result<List<SaasTenant>>, String>((ref, search) async {
  final repository = ref.watch(saasTenantRepositoryProvider);
  final collected = <SaasTenant>[];
  String? cursor;
  var sawStale = false;

  do {
    final result = await repository.list(SaasTenantQuery(
      search: search,
      cursor: cursor,
      limit: 100,
    ));
    final stop = result.when(
      success: (page, {stale = false}) {
        collected.addAll(page.items.where(
          (tenant) =>
              BreakGlassPolicy.tenantEligibility(tenant.tenantStatus) ==
              BreakGlassTenantEligibility.eligible,
        ));
        cursor = page.nextCursor;
        if (stale) sawStale = true;
        return false;
      },
      failure: (message, code) {
        cursor = null;
        return true;
      },
      offline: (page) {
        if (page != null) {
          collected.addAll(page.items.where(
            (tenant) =>
                BreakGlassPolicy.tenantEligibility(tenant.tenantStatus) ==
                BreakGlassTenantEligibility.eligible,
          ));
        }
        cursor = null;
        return true;
      },
    );
    if (stop) {
      return result.when(
        success: (_, {stale = false}) => Success(
          List<SaasTenant>.unmodifiable(collected),
          stale: sawStale,
        ),
        failure: (message, code) => Failure(message, code: code),
        offline: (_) => Offline(
          cached: collected.isEmpty
              ? null
              : List<SaasTenant>.unmodifiable(collected),
        ),
      );
    }
  } while (cursor != null);

  return Success(List<SaasTenant>.unmodifiable(collected), stale: sawStale);
});

/// The one derived answer Point 12B reads for the active-context indicator
/// and for any control that would exercise a grant.
///
/// It is evaluated at build time against `clockProvider`; it does not tick.
/// A consumer that must react to expiry schedules a one-shot rebuild at
/// `expiresAt` (and at the near-expiry threshold) — never a polling loop.
final breakGlassAccessProvider = Provider<BreakGlassAccessDecision>((ref) {
  ref.watch(tenantLifecycleRevisionProvider);
  final role = ref.watch(authRoleProvider);
  final current = ref.watch(breakGlassCurrentProvider).valueOrNull;
  if (current == null) return BreakGlassAccessDecision.none;

  final (grant, confirmed) = current.when(
    success: (snapshot, {stale = false}) => (snapshot.grant, !stale),
    failure: (_, __) => (null, false),
    offline: (cached) => (cached?.grant, false),
  );
  final targetStatus = grant == null
      ? null
      : ref
          .watch(platformTenantStoreProvider)
          .lifecycleStatusOf(grant.tenant.tenantId);
  return BreakGlassAccessPolicy.evaluate(
    sessionRole: role,
    grant: grant,
    confirmed: confirmed,
    targetTenantStatus: targetStatus,
    now: ref.watch(clockProvider)(),
  );
});

enum BreakGlassActionKind { activate, end }

@immutable
class BreakGlassActionState {
  const BreakGlassActionState({this.submitting});

  final BreakGlassActionKind? submitting;
  bool get isSubmitting => submitting != null;
}

sealed class BreakGlassActionOutcome {
  const BreakGlassActionOutcome();
}

class BreakGlassActionSucceeded extends BreakGlassActionOutcome {
  const BreakGlassActionSucceeded(this.result);

  final BreakGlassMutationResult result;
}

/// Refused locally — never queued. The caller keeps its draft.
class BreakGlassActionOffline extends BreakGlassActionOutcome {
  const BreakGlassActionOffline();
}

/// Tenant or grant changed since it was reviewed; current state is reloaded.
class BreakGlassActionStale extends BreakGlassActionOutcome {
  const BreakGlassActionStale(this.code);

  final BreakGlassProblemCode code;
}

/// The backend needs a fresh strong sign-in. Flutter verifies nothing itself.
class BreakGlassActionRecentAuthRequired extends BreakGlassActionOutcome {
  const BreakGlassActionRecentAuthRequired();
}

class BreakGlassActionNotPermitted extends BreakGlassActionOutcome {
  const BreakGlassActionNotPermitted();
}

class BreakGlassActionInvalid extends BreakGlassActionOutcome {
  const BreakGlassActionInvalid(this.code, this.message);

  final BreakGlassProblemCode code;
  final String message;
}

class BreakGlassActionFailed extends BreakGlassActionOutcome {
  const BreakGlassActionFailed();
}

/// A second submit while one is in flight.
class BreakGlassActionIgnored extends BreakGlassActionOutcome {
  const BreakGlassActionIgnored();
}

class BreakGlassActionController extends Notifier<BreakGlassActionState> {
  @override
  BreakGlassActionState build() => const BreakGlassActionState();

  Future<BreakGlassActionOutcome> activate(ActivateBreakGlassCommand command) =>
      _run(
        BreakGlassActionKind.activate,
        tenantId: command.tenantId,
        () => ref.read(platformBreakGlassRepositoryProvider).activate(command),
      );

  Future<BreakGlassActionOutcome> end(EndBreakGlassCommand command) => _run(
        BreakGlassActionKind.end,
        () => ref.read(platformBreakGlassRepositoryProvider).end(command),
      );

  Future<BreakGlassActionOutcome> _run(
    BreakGlassActionKind kind,
    Future<Result<BreakGlassMutationResult>> Function() operation, {
    String? tenantId,
  }) async {
    if (state.isSubmitting) return const BreakGlassActionIgnored();
    state = BreakGlassActionState(submitting: kind);
    try {
      final result = await operation();
      return result.when(
        success: (mutation, {stale = false}) {
          ref.invalidate(breakGlassCurrentProvider);
          return BreakGlassActionSucceeded(mutation);
        },
        failure: (message, code) {
          final parsed = BreakGlassProblemCode.parse(code);
          if (parsed == null) return const BreakGlassActionFailed();
          if (_reloadsCurrent(parsed)) {
            ref.invalidate(breakGlassCurrentProvider);
          }
          if (parsed == BreakGlassProblemCode.staleTenant && tenantId != null) {
            ref
              ..invalidate(saasTenantDetailProvider(tenantId))
              ..invalidate(saasTenantListProvider);
          }
          return switch (parsed) {
            BreakGlassProblemCode.staleTenant ||
            BreakGlassProblemCode.staleGrant =>
              BreakGlassActionStale(parsed),
            BreakGlassProblemCode.recentAuthenticationRequired =>
              const BreakGlassActionRecentAuthRequired(),
            BreakGlassProblemCode.notPermitted =>
              const BreakGlassActionNotPermitted(),
            _ => BreakGlassActionInvalid(parsed, message),
          };
        },
        offline: (_) => const BreakGlassActionOffline(),
      );
    } finally {
      state = const BreakGlassActionState();
    }
  }

  static bool _reloadsCurrent(BreakGlassProblemCode code) => switch (code) {
        BreakGlassProblemCode.staleTenant ||
        BreakGlassProblemCode.staleGrant ||
        BreakGlassProblemCode.grantAlreadyActive ||
        BreakGlassProblemCode.grantNotFound ||
        BreakGlassProblemCode.grantNotActive ||
        BreakGlassProblemCode.tenantNotEligible ||
        BreakGlassProblemCode.tenantAlreadyDeleted ||
        BreakGlassProblemCode.tenantNotFound ||
        BreakGlassProblemCode.idempotencyConflict =>
          true,
        BreakGlassProblemCode.invalidReason ||
        BreakGlassProblemCode.invalidScope ||
        BreakGlassProblemCode.recentAuthenticationRequired ||
        BreakGlassProblemCode.notPermitted =>
          false,
      };
}

final breakGlassActionControllerProvider =
    NotifierProvider<BreakGlassActionController, BreakGlassActionState>(
  BreakGlassActionController.new,
);
