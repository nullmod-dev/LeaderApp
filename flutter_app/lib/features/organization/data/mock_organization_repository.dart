import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../../platform/data/mock_tenant_subscription_repository.dart';
import '../../platform/data/platform_subscription_fixtures.dart';
import '../../platform/data/platform_tenant_store.dart';
import '../../platform/domain/saas_tenant_models.dart';
import '../domain/organization_models.dart';
import '../domain/organization_repository.dart';

enum MockOrganizationMode {
  loaded,

  /// A successful read flagged as a cached copy (background refresh failed).
  stale,

  /// Offline: the last successful read, if there is one, else nothing.
  offline,
  failure,

  /// A read whose lifecycle, subscription status, plan and one limit key
  /// are values this build does not know — the fail-safe parsing path.
  unsupported,
}

/// The tenant-side adapter over the **same** `PlatformTenantStore` record the
/// Super Admin screens read and write. It projects; it never copies and it
/// has no write path.
class MockOrganizationRepository implements OrganizationRepository {
  MockOrganizationRepository({
    required this.store,
    required this.clock,
    required this.tenantId,
    required this.usageVisible,
    this.mode = MockOrganizationMode.loaded,
    this.latency = const Duration(milliseconds: 260),
  });

  final PlatformTenantStore store;
  final DateTime Function() clock;

  /// The session's `saasTenantId`, asked on every call — the backend reads it
  /// from the bearer; the mock is told.
  final String? Function() tenantId;

  /// Whether the session may see organisation-wide usage figures. The backend
  /// decides this from the grant; the mock is told.
  final bool Function() usageVisible;

  /// Mutable so a test (or a developer) can read, go offline, and see the
  /// cached copy come back — the one path a fixed mode cannot show.
  MockOrganizationMode mode;
  final Duration latency;

  final Map<String, OrganizationSnapshot> _lastRead = {};

  Future<void> _wait() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  @override
  Future<Result<OrganizationSnapshot>> readCurrent() async {
    await _wait();
    final id = tenantId();
    if (id == null || id.isEmpty) return _contextUnavailable();
    if (mode == MockOrganizationMode.offline) {
      return Offline(cached: _lastRead[id]);
    }
    if (mode == MockOrganizationMode.failure) {
      return Failure('تعذّر تحميل بيانات المؤسسة.',
          code: ProblemCode.server.wire);
    }
    final tenant = store.byId(id);
    if (tenant == null) {
      return Failure('المؤسسة غير موجودة.', code: ProblemCode.notFound.wire);
    }
    var snapshot = project(tenant, now: clock(), usage: usageVisible());
    if (mode == MockOrganizationMode.unsupported) {
      snapshot = OrganizationSnapshot.fromJson(_unsupported(snapshot.toJson()));
    }
    _lastRead[id] = snapshot;
    return Success(snapshot, stale: mode == MockOrganizationMode.stale);
  }

  /// The projection itself, public so tests build expectations from the
  /// canonical record the same way.
  static OrganizationSnapshot project(
    SaasTenant tenant, {
    required DateTime now,
    required bool usage,
  }) {
    final subscription = tenant.subscription;
    final plan = canonicalPlanById(subscription.plan.planId);
    final used = mockTenantPlanUsage(tenant);
    return OrganizationSnapshot(
      tenantId: tenant.id,
      displayName: tenant.displayName,
      lifecycle: tenant.tenantStatus,
      createdAt: tenant.createdAt,
      mainAdminName: tenant.mainAdmin.name,
      subscription: OrganizationSubscription(
        status: subscription.status,
        plan: OrganizationPlan.fromWire(subscription.plan.planId),
        trialEndsAt: subscription.trialEndsAt,
        renewsAt: subscription.renewsAt,
        graceEndsAt: subscription.graceEndsAt,
      ),
      limits: OrganizationLimits(
        usageIncluded: usage,
        items: [
          for (final key in PlanLimitKey.values)
            OrganizationLimit(
              key: key,
              // The canonical rule, not a restatement of it.
              effective:
                  plan == null ? null : subscription.effectiveLimit(key, plan),
              planDefault: plan?.defaultLimits[key],
              overridden: plan != null && subscription.hasOverride(key),
              usage: usage ? used[key] : null,
            ),
        ],
      ),
      readAt: now.toUtc(),
    );
  }

  Map<String, dynamic> _unsupported(Map<String, dynamic> json) {
    final organization = json['organization'] as Map<String, dynamic>;
    final subscription = json['subscription'] as Map<String, dynamic>;
    final limits = json['limits'] as Map<String, dynamic>;
    final items = [...limits['items'] as List<dynamic>];
    items.removeWhere(
      (item) => (item as Map<String, dynamic>)['key'] == 'workshops',
    );
    return {
      ...json,
      'organization': {...organization, 'lifecycleStatus': 'archived_v2'},
      'subscription': {
        ...subscription,
        'status': 'paused_v2',
        'planId': 'mtm_enterprise_v2',
      },
      'limits': {
        ...limits,
        'items': [
          ...items,
          {'key': 'api_calls_v2', 'effective': 5000, 'usage': 12},
        ],
      },
    };
  }

  Failure<T> _contextUnavailable<T>() => Failure(
        'لا ترتبط هذه الجلسة بمؤسسة.',
        code: OrganizationProblemCode.contextUnavailable.wire,
      );
}
