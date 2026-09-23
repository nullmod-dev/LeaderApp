import '../../../core/result/result.dart';
import 'tenant_lifecycle_models.dart';

enum TenantLifecycleProblemCode {
  tenantNotFound('tenant_not_found'),
  invalidTransition('invalid_tenant_transition'),
  invalidReason('invalid_lifecycle_reason'),
  staleTenant('stale_tenant'),
  deletionWindowExpired('deletion_window_expired'),
  deletionNotEffective('deletion_not_effective'),
  tenantAlreadyDeleted('tenant_already_deleted'),
  idempotencyConflict('idempotency_conflict'),
  notPermitted('not_permitted');

  const TenantLifecycleProblemCode(this.wire);

  final String wire;

  static TenantLifecycleProblemCode? parse(String? wire) {
    for (final code in values) {
      if (code.wire == wire) return code;
    }
    return null;
  }
}

/// Dedicated control-plane seam for consequential tenant lifecycle writes.
/// Identity/list/create remain in `SaasTenantRepository`; commercial state and
/// feature state remain in their own repositories.
abstract class TenantLifecycleRepository {
  Future<Result<TenantLifecycleMutationResult>> suspend(
    SuspendTenantCommand command,
  );

  Future<Result<TenantLifecycleMutationResult>> reactivate(
    ReactivateTenantCommand command,
  );

  Future<Result<TenantLifecycleMutationResult>> beginDeletion(
    BeginTenantDeletionCommand command,
  );

  Future<Result<TenantLifecycleMutationResult>> cancelDeletion(
    CancelTenantDeletionCommand command,
  );

  /// Requests the backend-controlled final destructive operation. The client
  /// never deletes storage or destroys encryption keys itself.
  Future<Result<TenantLifecycleMutationResult>> finalizeDeletion(
    FinalizeTenantDeletionCommand command,
  );
}
