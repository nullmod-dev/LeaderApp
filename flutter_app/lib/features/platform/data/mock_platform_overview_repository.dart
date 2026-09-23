import '../../../core/result/result.dart';
import '../../../core/format/app_date.dart';
import '../../../core/motion/animated_counter.dart';
import '../../../core/access/saas_tenant_status.dart';
import '../domain/platform_overview_models.dart';
import '../domain/platform_overview_repository.dart';
import '../domain/platform_security_models.dart';
import 'platform_tenant_store.dart';
import 'platform_operations_fixtures.dart';

enum MockPlatformOverviewMode {
  loaded,
  empty,
  offlineWithCache,
  offlineWithoutCache,
  failure,
}

/// Deterministic frontend data for the first control-plane read.
///
/// The only moving input is [clock]. Every timestamp is an offset from the one
/// captured instant, so two repositories built with the same clock return the
/// same snapshot. The cache is intentionally process-memory only; it proves
/// the repository state semantics without claiming durable platform storage.
///
/// **The tenant buckets are counted, not stated.** They used to be four
/// literal integers here, which meant this file and Point 6's subscriber list
/// were two descriptions of one customer base and could disagree — and a
/// subscriber registered on the list would never have changed the number on
/// this screen. [store] now holds the records and
/// [PlatformTenantStore.tenantSummary] counts them. Injecting the store rather
/// than creating one is what lets the platform provider hand the *same* store
/// to both mocks; a repository built without one gets its own, which is what
/// the focused overview tests want.
class MockPlatformOverviewRepository implements PlatformOverviewRepository {
  factory MockPlatformOverviewRepository({
    required DateTime Function() clock,
    PlatformTenantStore? store,
    PlatformOperationsFixtures? operationsFixtures,
    MockPlatformOverviewMode mode = MockPlatformOverviewMode.loaded,
    Duration latency = const Duration(milliseconds: 520),
  }) {
    final resolvedStore = store ?? PlatformTenantStore(clock: clock);
    return MockPlatformOverviewRepository._(
      clock: clock,
      store: resolvedStore,
      operationsFixtures: operationsFixtures ??
          PlatformOperationsFixtures(clock: clock, tenantStore: resolvedStore),
      mode: mode,
      latency: latency,
    );
  }

  MockPlatformOverviewRepository._({
    required DateTime Function() clock,
    required PlatformTenantStore store,
    required PlatformOperationsFixtures operationsFixtures,
    required this.mode,
    required this.latency,
  })  : _clock = clock,
        _store = store,
        _operationsFixtures = operationsFixtures;

  final DateTime Function() _clock;
  final PlatformTenantStore _store;
  final PlatformOperationsFixtures _operationsFixtures;
  final MockPlatformOverviewMode mode;
  final Duration latency;

  @override
  Future<Result<PlatformOverviewSnapshot>> loadOverview() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final generatedAt = _clock().toUtc();
    return switch (mode) {
      MockPlatformOverviewMode.loaded => Success(_snapshot(generatedAt)),
      MockPlatformOverviewMode.empty =>
        Success(PlatformOverviewSnapshot.empty(generatedAt)),
      MockPlatformOverviewMode.offlineWithCache =>
        Offline(cached: _snapshot(generatedAt)),
      MockPlatformOverviewMode.offlineWithoutCache => const Offline(),
      MockPlatformOverviewMode.failure => const Failure(
          'تعذّر تحميل ملخص المنصة.',
          code: 'server',
        ),
    };
  }

  PlatformOverviewSnapshot _snapshot(DateTime now) {
    final tenantSummary = _store.tenantSummary();
    final healthSnapshot = _operationsFixtures.health(capturedAt: now);
    final securitySnapshot = _operationsFixtures.security(capturedAt: now);
    final pendingTenants = _store.tenants
        .where(
            (tenant) => tenant.tenantStatus == SaasTenantStatus.deletionPending)
        .toList();
    final activity = <PlatformActivityEvent>[
      PlatformActivityEvent(
        id: 'event_demo_started',
        type: PlatformActivityType.demoStarted,
        title: 'بدأت تجربة عميل جديدة',
        description: 'تجربة بسيطة لفريق نبض التطوعي',
        occurredAt: now.subtract(const Duration(minutes: 38)),
      ),
      PlatformActivityEvent(
        id: 'event_tenant_created',
        type: PlatformActivityType.tenantCreated,
        title: 'أضيف فريق مشترك',
        description: 'فريق الاستجابة الطبية',
        occurredAt: now.subtract(const Duration(hours: 3)),
      ),
      PlatformActivityEvent(
        id: 'event_subscription_changed',
        type: PlatformActivityType.subscriptionChanged,
        title: 'تغيّرت حالة اشتراك',
        description: 'جمعية عافية انتقلت إلى فترة السماح',
        occurredAt: now.subtract(const Duration(hours: 7)),
      ),
      PlatformActivityEvent(
        id: 'event_security_alert',
        type: PlatformActivityType.securityAlert,
        title: 'رُصد تنبيه أمني',
        description: 'محاولات دخول متكررة تحتاج مراجعة',
        occurredAt: now.subtract(const Duration(days: 1, hours: 2)),
      ),
      PlatformActivityEvent(
        id: 'event_health_changed',
        type: PlatformActivityType.platformHealthChanged,
        title: 'تراجعت خدمة المهام',
        description: 'بعض المهام الخلفية تتأخر عن المعتاد',
        occurredAt: now.subtract(const Duration(days: 1, hours: 5)),
      ),
    ]..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    return PlatformOverviewSnapshot(
      generatedAt: now.subtract(const Duration(minutes: 6)),
      // Counted from the canonical dataset — see the class header. The
      // fixtures are eight subscribers in exactly these four states, so this
      // returns what the literal used to say, and keeps returning the truth
      // after one is registered.
      tenants: tenantSummary,
      demos: const PlatformDemoSummary(
        active: 4,
        simple: 2,
        full: 2,
        expiringSoon: 2,
      ),
      health: healthSnapshot.signals,
      attention: [
        if (securitySnapshot.alerts.isNotEmpty)
          PlatformAttentionItem(
            id: 'attention_security',
            severity: _securityAttentionSeverity(securitySnapshot),
            category: PlatformAttentionCategory.security,
            title: '${toArabicIndic('${securitySnapshot.alerts.length}')}'
                ' تنبيه أمني يحتاج مراجعة',
            description: 'تعرض أحدث لقطة نشاط مصادقة يحتاج إلى الانتباه.',
            occurredAt: securitySnapshot.alerts
                .map((alert) => alert.detectedAt)
                .reduce((a, b) => a.isAfter(b) ? a : b),
            target: PlatformOverviewTarget.security,
          ),
        if (tenantSummary.gracePeriod > 0)
          PlatformAttentionItem(
            id: 'attention_grace',
            severity: AttentionSeverity.warning,
            category: PlatformAttentionCategory.subscription,
            title: '${toArabicIndic('${tenantSummary.gracePeriod}')}'
                ' اشتراك في فترة السماح',
            description: 'تحتاج أوضاعها التجارية إلى متابعة قبل انتهاء المهلة.',
            occurredAt: now.subtract(const Duration(hours: 7)),
            target: PlatformOverviewTarget.tenants,
          ),
        for (final tenant in pendingTenants)
          PlatformAttentionItem(
            id: 'attention_tenant_deletion_pending_${tenant.id}',
            severity: AttentionSeverity.critical,
            category: PlatformAttentionCategory.tenantLifecycle,
            title: '${tenant.displayName} — الحذف قيد الانتظار',
            description:
                'موعد الحذف النهائي: ${AppDate.dayMonthTime(tenant.lifecycle.deletion!.scheduledFor.toLocal())}',
            occurredAt: tenant.lifecycle.deletion!.requestedAt,
            target: PlatformOverviewTarget.tenants,
            tenantId: tenant.id,
            scheduledFor: tenant.lifecycle.deletion!.scheduledFor,
          ),
        if (healthSnapshot.overallStatus != PlatformHealthStatus.healthy)
          PlatformAttentionItem(
            id: 'attention_health',
            severity:
                healthSnapshot.overallStatus == PlatformHealthStatus.unavailable
                    ? AttentionSeverity.critical
                    : AttentionSeverity.warning,
            category: PlatformAttentionCategory.health,
            title: 'صحة المنصة تحتاج إلى مراجعة',
            description: healthSnapshot.signals
                .firstWhere(
                  (signal) => signal.status != PlatformHealthStatus.healthy,
                )
                .summary,
            occurredAt: healthSnapshot.generatedAt,
            target: PlatformOverviewTarget.health,
          ),
      ],
      recentActivity: activity,
      usage: const PlatformUsageSummary(
        storageUsedBytes: 18 * 1024 * 1024 * 1024,
        storageAllowanceBytes: 100 * 1024 * 1024 * 1024,
      ),
    );
  }
}

AttentionSeverity _securityAttentionSeverity(
  PlatformSecuritySnapshot snapshot,
) =>
    switch (snapshot.summaryState) {
      PlatformSecuritySummaryState.critical => AttentionSeverity.critical,
      PlatformSecuritySummaryState.warning ||
      PlatformSecuritySummaryState.unknown =>
        AttentionSeverity.warning,
      PlatformSecuritySummaryState.informational => AttentionSeverity.info,
      PlatformSecuritySummaryState.noAlerts => AttentionSeverity.info,
    };
