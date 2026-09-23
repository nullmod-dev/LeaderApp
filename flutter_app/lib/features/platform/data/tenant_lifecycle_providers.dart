import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../auth/data/auth_providers.dart';
import '../../auth/data/mock_auth_repository.dart';
import '../../auth/domain/auth_models.dart';
import '../../auth/domain/session_access.dart';
import '../../tenant_feature/data/tenant_feature_providers.dart';
import '../domain/tenant_lifecycle_models.dart';
import '../domain/tenant_lifecycle_repository.dart';
import 'mock_tenant_lifecycle_repository.dart';
import 'platform_overview_providers.dart';
import 'saas_subscription_providers.dart';
import 'saas_tenant_providers.dart';

final tenantLifecycleRepositoryProvider =
    Provider<TenantLifecycleRepository>((ref) {
  return MockTenantLifecycleRepository(
    store: ref.watch(platformTenantStoreProvider),
    clock: ref.watch(clockProvider),
  );
});

/// Cheap router/startup invalidation token. The canonical state remains in the
/// store; this only asks live consumers to classify it again.
class TenantLifecycleRevisionController extends Notifier<int> {
  @override
  int build() => 0;

  void changed() => state++;
}

final tenantLifecycleRevisionProvider =
    NotifierProvider<TenantLifecycleRevisionController, int>(
  TenantLifecycleRevisionController.new,
);

/// Combines the future server session envelope with the process-memory tenant
/// store only for the development mock repository. A production auth
/// repository remains authoritative and supplies lifecycle through
/// [sessionAccessProvider].
final effectiveSessionAccessProvider = Provider<SessionAccess>((ref) {
  ref.watch(tenantLifecycleRevisionProvider);
  final base = ref.watch(sessionAccessProvider);
  if (base.isDemo) return base;

  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null || user.role == AuthRole.superAdmin) return base;

  // This runtime composition exists only to let the canonical mock store drive
  // a signed-in development persona. A real backend reissues/revalidates the
  // session and rejects protected requests regardless of this client gate.
  if (ref.watch(authRepositoryProvider) is! MockAuthRepository) return base;

  final tenantId = user.saasTenantId;
  if (tenantId == null) return base;
  final status =
      ref.watch(platformTenantStoreProvider).lifecycleStatusOf(tenantId);
  return status == null ? base : base.copyWith(tenant: status);
});

enum TenantLifecycleActionStateKind {
  suspend,
  reactivate,
  beginDeletion,
  cancelDeletion,
  finalizeDeletion,
}

class TenantLifecycleActionState {
  const TenantLifecycleActionState({this.submitting});

  final TenantLifecycleActionStateKind? submitting;
  bool get isSubmitting => submitting != null;
}

sealed class TenantLifecycleActionOutcome {
  const TenantLifecycleActionOutcome();
}

class TenantLifecycleActionSucceeded extends TenantLifecycleActionOutcome {
  const TenantLifecycleActionSucceeded(this.result);

  final TenantLifecycleMutationResult result;
}

class TenantLifecycleActionOffline extends TenantLifecycleActionOutcome {
  const TenantLifecycleActionOffline();
}

class TenantLifecycleActionStale extends TenantLifecycleActionOutcome {
  const TenantLifecycleActionStale();
}

class TenantLifecycleActionInvalid extends TenantLifecycleActionOutcome {
  const TenantLifecycleActionInvalid(this.code, this.message);

  final TenantLifecycleProblemCode code;
  final String message;
}

class TenantLifecycleActionNotPermitted extends TenantLifecycleActionOutcome {
  const TenantLifecycleActionNotPermitted();
}

class TenantLifecycleActionFailed extends TenantLifecycleActionOutcome {
  const TenantLifecycleActionFailed();
}

class TenantLifecycleActionIgnored extends TenantLifecycleActionOutcome {
  const TenantLifecycleActionIgnored();
}

class TenantLifecycleActionController
    extends Notifier<TenantLifecycleActionState> {
  @override
  TenantLifecycleActionState build() => const TenantLifecycleActionState();

  Future<TenantLifecycleActionOutcome> suspend(SuspendTenantCommand command) =>
      _run(
        TenantLifecycleActionStateKind.suspend,
        command.tenantId,
        () => ref.read(tenantLifecycleRepositoryProvider).suspend(command),
      );

  Future<TenantLifecycleActionOutcome> reactivate(
    ReactivateTenantCommand command,
  ) =>
      _run(
        TenantLifecycleActionStateKind.reactivate,
        command.tenantId,
        () => ref.read(tenantLifecycleRepositoryProvider).reactivate(command),
      );

  Future<TenantLifecycleActionOutcome> beginDeletion(
    BeginTenantDeletionCommand command,
  ) =>
      _run(
        TenantLifecycleActionStateKind.beginDeletion,
        command.tenantId,
        () =>
            ref.read(tenantLifecycleRepositoryProvider).beginDeletion(command),
      );

  Future<TenantLifecycleActionOutcome> cancelDeletion(
    CancelTenantDeletionCommand command,
  ) =>
      _run(
        TenantLifecycleActionStateKind.cancelDeletion,
        command.tenantId,
        () =>
            ref.read(tenantLifecycleRepositoryProvider).cancelDeletion(command),
      );

  Future<TenantLifecycleActionOutcome> finalizeDeletion(
    FinalizeTenantDeletionCommand command,
  ) =>
      _run(
        TenantLifecycleActionStateKind.finalizeDeletion,
        command.tenantId,
        () => ref
            .read(tenantLifecycleRepositoryProvider)
            .finalizeDeletion(command),
      );

  Future<TenantLifecycleActionOutcome> _run(
    TenantLifecycleActionStateKind kind,
    String tenantId,
    Future<Result<TenantLifecycleMutationResult>> Function() operation,
  ) async {
    if (state.isSubmitting) return const TenantLifecycleActionIgnored();
    state = TenantLifecycleActionState(submitting: kind);
    try {
      final result = await operation();
      return result.when(
        success: (mutation, {stale = false}) {
          _invalidate(tenantId);
          ref.read(tenantLifecycleRevisionProvider.notifier).changed();
          return TenantLifecycleActionSucceeded(mutation);
        },
        failure: (message, code) {
          final parsed = TenantLifecycleProblemCode.parse(code);
          if (parsed == TenantLifecycleProblemCode.staleTenant) {
            _invalidate(tenantId);
            return const TenantLifecycleActionStale();
          }
          if (parsed == TenantLifecycleProblemCode.notPermitted) {
            return const TenantLifecycleActionNotPermitted();
          }
          if (parsed != null) {
            if (_needsAuthoritativeRefresh(parsed)) _invalidate(tenantId);
            return TenantLifecycleActionInvalid(parsed, message);
          }
          return const TenantLifecycleActionFailed();
        },
        offline: (_) => const TenantLifecycleActionOffline(),
      );
    } finally {
      state = const TenantLifecycleActionState();
    }
  }

  void _invalidate(String tenantId) {
    ref
      ..invalidate(saasTenantDetailProvider(tenantId))
      ..invalidate(deletedTenantTombstoneProvider(tenantId))
      ..invalidate(saasTenantHistoryProvider(tenantId))
      ..invalidate(saasTenantListProvider)
      ..invalidate(platformOverviewProvider)
      ..invalidate(tenantSubscriptionProvider(tenantId))
      ..invalidate(tenantLimitsProvider(tenantId))
      ..invalidate(tenantFeaturesProvider(tenantId));
  }

  static bool _needsAuthoritativeRefresh(TenantLifecycleProblemCode code) =>
      switch (code) {
        TenantLifecycleProblemCode.invalidTransition ||
        TenantLifecycleProblemCode.deletionWindowExpired ||
        TenantLifecycleProblemCode.deletionNotEffective ||
        TenantLifecycleProblemCode.tenantAlreadyDeleted ||
        TenantLifecycleProblemCode.idempotencyConflict ||
        TenantLifecycleProblemCode.tenantNotFound =>
          true,
        TenantLifecycleProblemCode.invalidReason ||
        TenantLifecycleProblemCode.staleTenant ||
        TenantLifecycleProblemCode.notPermitted =>
          false,
      };
}

final tenantLifecycleActionControllerProvider = NotifierProvider<
    TenantLifecycleActionController, TenantLifecycleActionState>(
  TenantLifecycleActionController.new,
);
