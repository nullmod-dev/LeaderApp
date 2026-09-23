import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../domain/saas_subscription_models.dart';
import '../domain/saas_subscription_repository.dart';
import '../domain/saas_tenant_models.dart';
import 'platform_subscription_fixtures.dart';
import 'platform_tenant_fixtures.dart';
import 'platform_tenant_store.dart';

/// The mock's per-key usage, from the platform aggregates on the tenant
/// record. One derivation shared by the Super Admin limits read and the
/// Point 15 tenant organisation read, so the two can never disagree. `admins`
/// is a fixed 1 until a real admin-count aggregate exists (`DATA-NEEDS.md`).
TenantPlanUsage mockTenantPlanUsage(SaasTenant tenant) => TenantPlanUsage({
      PlanLimitKey.detachmentGroups: tenant.counts.detachmentGroups,
      PlanLimitKey.detachments: tenant.counts.detachments,
      PlanLimitKey.admins: 1,
      PlanLimitKey.members: tenant.counts.members,
      PlanLimitKey.workshops: tenant.counts.workshops,
      PlanLimitKey.storageBytes: tenant.usage.storageUsedBytes,
    });

enum MockTenantSubscriptionMode {
  loaded,
  offline,
  failure,
  subscriptionUnavailable,
  usageUnavailable,
}

class MockTenantSubscriptionRepository implements TenantSubscriptionRepository {
  MockTenantSubscriptionRepository({
    required this.store,
    required DateTime Function() clock,
    this.mode = MockTenantSubscriptionMode.loaded,
    this.latency = const Duration(milliseconds: 280),
  }) : _clock = clock;

  final PlatformTenantStore store;
  final DateTime Function() _clock;
  final MockTenantSubscriptionMode mode;
  final Duration latency;

  Future<void> _wait() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  @override
  Future<Result<TenantSubscriptionDetails>> getSubscription(
    String tenantId,
  ) async {
    await _wait();
    if (mode == MockTenantSubscriptionMode.offline) return const Offline();
    if (mode == MockTenantSubscriptionMode.failure) return _safeFailure();
    if (mode == MockTenantSubscriptionMode.subscriptionUnavailable) {
      return const Failure(
        'بيانات الاشتراك غير متاحة الآن.',
        code: 'subscription_not_found',
      );
    }
    final tenant = store.byId(tenantId);
    if (tenant == null) return _tenantNotFound();
    return Success(_details(tenant));
  }

  @override
  Future<Result<List<SaasPlan>>> listPlans() async {
    await _wait();
    if (mode == MockTenantSubscriptionMode.offline) return const Offline();
    if (mode == MockTenantSubscriptionMode.failure) return _safeFailure();
    return Success(canonicalSaasPlans);
  }

  @override
  Future<Result<TenantLimitsSnapshot>> getLimits(String tenantId) async {
    await _wait();
    if (mode == MockTenantSubscriptionMode.offline) return const Offline();
    if (mode == MockTenantSubscriptionMode.failure ||
        mode == MockTenantSubscriptionMode.usageUnavailable) {
      return const Failure(
        'تعذّر تحميل الاستخدام والحدود.',
        code: 'server',
      );
    }
    final tenant = store.byId(tenantId);
    if (tenant == null) return _tenantNotFound();
    final plan = canonicalPlanById(tenant.subscription.plan.planId);
    if (plan == null) {
      return const Failure(
        'لم تُعيّن خطة لهذا الفريق بعد.',
        code: 'plan_not_found',
      );
    }
    return Success(_limits(tenant, plan));
  }

  @override
  Future<Result<TenantSubscriptionDetails>> activate(
    ActivateSubscriptionCommand command,
  ) =>
      _mutate(
        command,
        allowed: const {
          SubscriptionStatus.trial,
          SubscriptionStatus.grace,
          SubscriptionStatus.inactive,
        },
        event: SaasTenantEventType.subscriptionActivated,
        transform: (tenant, now) {
          final planResult = _selectablePlan(command.planId);
          if (planResult == null) return null;
          return tenant.subscription.copyWith(
            status: SubscriptionStatus.active,
            plan: AssignedSaasPlan(planResult.id),
            version: tenant.subscription.version + 1,
            renewsAt: now.add(const Duration(days: 365)),
            clearTrialEndsAt: true,
            clearGraceEndsAt: true,
          );
        },
        note: 'تفعيل إداري للاشتراك دون أي عملية دفع.',
        planId: command.planId,
      );

  @override
  Future<Result<TenantSubscriptionDetails>> extendTrial(
    ExtendTrialCommand command,
  ) async {
    final now = _clock().toUtc();
    final tenant = store.byId(command.tenantId);
    final currentEnd = tenant?.subscription.trialEndsAt;
    if (!command.newEndsAt.toUtc().isAfter(now) ||
        currentEnd == null ||
        !command.newEndsAt.toUtc().isAfter(currentEnd)) {
      return const Failure(
        'يجب أن يكون انتهاء التجربة الجديد بعد تاريخها الحالي.',
        code: 'invalid_trial_extension',
      );
    }
    return _mutate(
      command,
      allowed: const {SubscriptionStatus.trial},
      event: SaasTenantEventType.trialExtended,
      transform: (tenant, _) => tenant.subscription.copyWith(
        version: tenant.subscription.version + 1,
        trialEndsAt: command.newEndsAt.toUtc(),
      ),
      note: 'مُدّدت الفترة التجريبية.',
    );
  }

  @override
  Future<Result<TenantSubscriptionDetails>> endTrial(
    SubscriptionVersionedCommand command,
  ) =>
      _mutate(
        command,
        allowed: const {SubscriptionStatus.trial},
        event: SaasTenantEventType.trialEnded,
        transform: (tenant, now) => tenant.subscription.copyWith(
          status: SubscriptionStatus.grace,
          version: tenant.subscription.version + 1,
          graceEndsAt: now.add(const Duration(days: kDefaultGraceDays)),
          clearTrialEndsAt: true,
        ),
        note: 'انتهت التجربة وبدأت فترة سماح؛ لم يُعلّق الفريق.',
      );

  @override
  Future<Result<TenantSubscriptionDetails>> moveToGrace(
    SubscriptionVersionedCommand command,
  ) =>
      _mutate(
        command,
        allowed: const {SubscriptionStatus.active},
        event: SaasTenantEventType.movedToGrace,
        transform: (tenant, now) => tenant.subscription.copyWith(
          status: SubscriptionStatus.grace,
          version: tenant.subscription.version + 1,
          graceEndsAt: now.add(const Duration(days: kDefaultGraceDays)),
          clearRenewsAt: true,
        ),
        note: 'بدأت فترة السماح؛ حالة وصول الفريق لم تتغير.',
      );

  @override
  Future<Result<TenantSubscriptionDetails>> changePlan(
    ChangePlanCommand command,
  ) =>
      _mutate(
        command,
        allowed: SubscriptionStatus.values.toSet(),
        event: SaasTenantEventType.planChanged,
        transform: (tenant, _) {
          final planResult = _selectablePlan(command.planId);
          if (planResult == null ||
              tenant.subscription.plan.planId == command.planId) {
            return null;
          }
          return tenant.subscription.copyWith(
            plan: AssignedSaasPlan(planResult.id),
            version: tenant.subscription.version + 1,
          );
        },
        note: 'تغيّرت الخطة مع بقاء البيانات الحالية.',
        planId: command.planId,
      );

  @override
  Future<Result<TenantLimitsSnapshot>> updateLimitOverride(
    UpdateLimitOverrideCommand command,
  ) async {
    if (command.overrideValue != null && command.overrideValue! < 0) {
      return const Failure('الحد غير صالح.', code: 'limit_invalid');
    }
    await _wait();
    final blocked = _writeBlock<TenantLimitsSnapshot>();
    if (blocked != null) return blocked;
    final tenant = store.byId(command.tenantId);
    if (tenant == null) return _tenantNotFound();
    if (tenant.subscription.version != command.expectedVersion) {
      return _stale();
    }
    final plan = canonicalPlanById(tenant.subscription.plan.planId);
    if (plan == null) return _planNotFound();
    final overrides = {...tenant.subscription.limitOverrides};
    if (command.overrideValue == null) {
      overrides.remove(command.key);
    } else {
      overrides[command.key] = command.overrideValue!;
    }
    final updated = store.updateSubscription(
      tenant.id,
      tenant.subscription.copyWith(
        version: tenant.subscription.version + 1,
        limitOverrides: overrides,
      ),
      eventType: SaasTenantEventType.limitOverrideChanged,
      note: command.overrideValue == null
          ? 'أُعيد ${command.key.wire} إلى حد الخطة.'
          : 'حُدّث الحد المخصص لـ${command.key.wire}.',
    );
    return Success(_limits(updated, plan));
  }

  Future<Result<TenantSubscriptionDetails>> _mutate(
    SubscriptionVersionedCommand command, {
    required Set<SubscriptionStatus> allowed,
    required SaasTenantEventType event,
    required SaasSubscription? Function(SaasTenant tenant, DateTime now)
        transform,
    required String note,
    String? planId,
  }) async {
    await _wait();
    final blocked = _writeBlock<TenantSubscriptionDetails>();
    if (blocked != null) return blocked;
    if (planId != null) {
      final requestedPlan = canonicalPlanById(planId);
      if (requestedPlan == null) return _planNotFound();
      if (!requestedPlan.selectable) return _planUnavailable();
    }
    final tenant = store.byId(command.tenantId);
    if (tenant == null) return _tenantNotFound();
    if (tenant.subscription.version != command.expectedVersion) {
      return _stale();
    }
    if (!allowed.contains(tenant.subscription.status)) {
      return _invalidTransition();
    }
    final next = transform(tenant, _clock().toUtc());
    if (next == null) return _invalidTransition();
    final updated = store.updateSubscription(
      tenant.id,
      next,
      eventType: event,
      note: note,
    );
    return Success(_details(updated));
  }

  Result<T>? _writeBlock<T>() {
    if (mode == MockTenantSubscriptionMode.offline) {
      return const Offline();
    }
    if (mode == MockTenantSubscriptionMode.failure) {
      return _safeFailure<T>();
    }
    return null;
  }

  SaasPlan? _selectablePlan(String id) {
    final plan = canonicalPlanById(id);
    return plan?.selectable == true ? plan : null;
  }

  TenantSubscriptionDetails _details(SaasTenant tenant) =>
      TenantSubscriptionDetails(
        tenantId: tenant.id,
        tenantName: tenant.displayName,
        subscription: tenant.subscription,
        currentPlan: canonicalPlanById(tenant.subscription.plan.planId),
      );

  TenantLimitsSnapshot _limits(SaasTenant tenant, SaasPlan plan) =>
      TenantLimitsSnapshot(
        tenantId: tenant.id,
        tenantName: tenant.displayName,
        subscription: tenant.subscription,
        plan: plan,
        usage: mockTenantPlanUsage(tenant),
      );

  Failure<T> _tenantNotFound<T>() => Failure(
        'الفريق غير موجود.',
        code: ProblemCode.notFound.wire,
      );
  Failure<T> _planNotFound<T>() => const Failure(
        'الخطة غير موجودة.',
        code: 'plan_not_found',
      );
  Failure<T> _planUnavailable<T>() => const Failure(
        'الخطة غير متاحة للاختيار.',
        code: 'plan_unavailable',
      );
  Failure<T> _stale<T>() => const Failure(
        'تغيّرت بيانات الاشتراك. حدّث الصفحة ثم أعد المحاولة.',
        code: 'stale_subscription',
      );
  Failure<T> _invalidTransition<T>() => const Failure(
        'لا تسمح حالة الاشتراك الحالية بهذا الإجراء.',
        code: 'invalid_subscription_transition',
      );
  Failure<T> _safeFailure<T>() => Failure(
        'تعذّر إتمام العملية بأمان.',
        code: ProblemCode.server.wire,
      );
}
