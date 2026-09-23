import '../../../core/result/result.dart';
import 'saas_subscription_models.dart';

enum SubscriptionProblemCode {
  subscriptionNotFound('subscription_not_found'),
  invalidTransition('invalid_subscription_transition'),
  invalidTrialExtension('invalid_trial_extension'),
  planNotFound('plan_not_found'),
  planUnavailable('plan_unavailable'),
  limitInvalid('limit_invalid'),
  staleSubscription('stale_subscription');

  const SubscriptionProblemCode(this.wire);
  final String wire;

  static SubscriptionProblemCode? parse(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return null;
  }
}

/// Dedicated commercial seam. Tenant identity/list CRUD stays in
/// `SaasTenantRepository`; platform subscription writes do not bloat it and a
/// future tenant-side read-only adapter can reuse the models without exposing
/// these Super Admin operations.
abstract class TenantSubscriptionRepository {
  Future<Result<TenantSubscriptionDetails>> getSubscription(String tenantId);
  Future<Result<List<SaasPlan>>> listPlans();
  Future<Result<TenantLimitsSnapshot>> getLimits(String tenantId);

  Future<Result<TenantSubscriptionDetails>> activate(
    ActivateSubscriptionCommand command,
  );
  Future<Result<TenantSubscriptionDetails>> extendTrial(
    ExtendTrialCommand command,
  );
  Future<Result<TenantSubscriptionDetails>> endTrial(
    SubscriptionVersionedCommand command,
  );
  Future<Result<TenantSubscriptionDetails>> moveToGrace(
    SubscriptionVersionedCommand command,
  );
  Future<Result<TenantSubscriptionDetails>> changePlan(
    ChangePlanCommand command,
  );
  Future<Result<TenantLimitsSnapshot>> updateLimitOverride(
    UpdateLimitOverrideCommand command,
  );
}
