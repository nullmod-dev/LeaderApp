import '../domain/platform_health_models.dart';
import '../domain/platform_security_models.dart';
import 'platform_tenant_store.dart';

enum PlatformHealthFixture {
  healthy,
  degraded,
  partial,
  unavailable,
  unknown,
}

enum PlatformSecurityFixture {
  noAlerts,
  informational,
  warning,
  critical,
  mixed,
  tenantLinked,
  platformWide,
  unknown,
}

/// One deterministic, backend-neutral source for Point 5 and Point 10 mocks.
class PlatformOperationsFixtures {
  PlatformOperationsFixtures({
    required DateTime Function() clock,
    required PlatformTenantStore tenantStore,
  })  : _clock = clock,
        _tenantStore = tenantStore;

  final DateTime Function() _clock;
  final PlatformTenantStore _tenantStore;

  PlatformHealthSnapshot health({
    PlatformHealthFixture fixture = PlatformHealthFixture.degraded,
    DateTime? capturedAt,
  }) {
    final now = (capturedAt ?? _clock()).toUtc();
    final statuses = switch (fixture) {
      PlatformHealthFixture.healthy => const (
          PlatformHealthStatus.healthy,
          PlatformHealthStatus.healthy,
          PlatformHealthStatus.healthy,
        ),
      PlatformHealthFixture.degraded => const (
          PlatformHealthStatus.healthy,
          PlatformHealthStatus.degraded,
          PlatformHealthStatus.healthy,
        ),
      PlatformHealthFixture.partial => const (
          PlatformHealthStatus.healthy,
          PlatformHealthStatus.unknown,
          PlatformHealthStatus.healthy,
        ),
      PlatformHealthFixture.unavailable => const (
          PlatformHealthStatus.healthy,
          PlatformHealthStatus.unavailable,
          PlatformHealthStatus.healthy,
        ),
      PlatformHealthFixture.unknown => const (
          PlatformHealthStatus.unknown,
          PlatformHealthStatus.unknown,
          PlatformHealthStatus.unknown,
        ),
    };
    final all = [
      PlatformHealthSignal(
        id: 'identity',
        label: 'الدخول والجلسات',
        status: statuses.$1,
        summary: _healthSummary(statuses.$1),
        observedAt: now.subtract(const Duration(minutes: 7)),
      ),
      PlatformHealthSignal(
        id: 'background_jobs',
        label: 'المهام الخلفية',
        status: statuses.$2,
        summary: statuses.$2 == PlatformHealthStatus.degraded
            ? 'تأخير محدود في بعض المهام'
            : _healthSummary(statuses.$2),
        observedAt: now.subtract(const Duration(minutes: 8)),
      ),
      PlatformHealthSignal(
        id: 'files',
        label: 'الملفات والتصدير',
        status: statuses.$3,
        summary: _healthSummary(statuses.$3),
        observedAt: now.subtract(const Duration(minutes: 9)),
      ),
    ];
    return PlatformHealthSnapshot(
      generatedAt: now.subtract(const Duration(minutes: 6)),
      signals:
          fixture == PlatformHealthFixture.partial ? all.take(2).toList() : all,
      isPartial: fixture == PlatformHealthFixture.partial,
    );
  }

  PlatformSecuritySnapshot security({
    PlatformSecurityFixture fixture = PlatformSecurityFixture.critical,
    DateTime? capturedAt,
  }) {
    final now = (capturedAt ?? _clock()).toUtc();
    final linked = _tenantReference('saas_hilal');
    final info = PlatformSecurityAlert(
      id: 'security_info_sign_in',
      severity: PlatformSecurityAlertSeverity.info,
      category: PlatformSecurityAlertCategory.authentication,
      title: 'معلومة عن نشاط الدخول',
      description: 'سُجّلت إشارة مصادقة جديدة في آخر لقطة متاحة.',
      detectedAt: now.subtract(const Duration(minutes: 42)),
    );
    final warning = PlatformSecurityAlert(
      id: 'security_repeated_sign_in',
      severity: PlatformSecurityAlertSeverity.warning,
      category: PlatformSecurityAlertCategory.authentication,
      title: 'محاولات دخول متكررة',
      description: 'رُصد نمط دخول يحتاج إلى مراجعة في آخر لقطة متاحة.',
      detectedAt: now.subtract(const Duration(hours: 2)),
    );
    final critical = PlatformSecurityAlert(
      id: 'security_tenant_sign_in',
      severity: PlatformSecurityAlertSeverity.critical,
      category: PlatformSecurityAlertCategory.authentication,
      title: 'نشاط دخول يحتاج انتباها',
      description: 'توجد إشارة مصادقة عالية الأهمية مرتبطة بهذا الفريق.',
      detectedAt: now.subtract(const Duration(hours: 1, minutes: 18)),
      affectedTenant: linked,
    );
    final unknown = PlatformSecurityAlert.fromJson({
      'id': 'security_future_state',
      'severity': 'future_severity',
      'category': 'future_category',
      'title': 'حالة تنبيه غير معروفة',
      'description': 'أرسل المصدر حالة لا يفهمها هذا الإصدار.',
      'detectedAt': now.subtract(const Duration(minutes: 20)).toIso8601String(),
    });
    final alerts = switch (fixture) {
      PlatformSecurityFixture.noAlerts => <PlatformSecurityAlert>[],
      PlatformSecurityFixture.informational => [info],
      PlatformSecurityFixture.warning => [warning],
      PlatformSecurityFixture.critical => [critical, warning],
      PlatformSecurityFixture.mixed => [critical, warning, info],
      PlatformSecurityFixture.tenantLinked => [critical],
      PlatformSecurityFixture.platformWide => [warning],
      PlatformSecurityFixture.unknown => [unknown],
    }
      ..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    return PlatformSecuritySnapshot(
      generatedAt: now.subtract(const Duration(minutes: 6)),
      alerts: alerts,
    );
  }

  PlatformSecurityTenantReference? _tenantReference(String tenantId) {
    final tenant = _tenantStore.byId(tenantId);
    if (tenant != null) {
      return PlatformSecurityTenantReference(
        id: tenant.id,
        displayName: tenant.displayName,
        isDeleted: false,
      );
    }
    final tombstone = _tenantStore.tombstoneById(tenantId);
    if (tombstone == null) return null;
    return PlatformSecurityTenantReference(
      id: tombstone.tenantId,
      displayName: tombstone.displayNameSnapshot,
      isDeleted: true,
      deletedAt: tombstone.deletedAt,
    );
  }
}

String _healthSummary(PlatformHealthStatus status) => switch (status) {
      PlatformHealthStatus.healthy => 'تعمل بصورة طبيعية',
      PlatformHealthStatus.degraded => 'تعمل بصورة متأثرة جزئيا',
      PlatformHealthStatus.unavailable => 'لا تتوفر حالتها الآن',
      PlatformHealthStatus.unknown => 'لم تُعرف حالتها في هذه اللقطة',
    };
