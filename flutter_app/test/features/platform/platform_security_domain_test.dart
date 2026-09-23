import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/platform/domain/platform_security_models.dart';

void main() {
  PlatformSecurityAlert alert(
    PlatformSecurityAlertSeverity severity, {
    String id = 'alert',
  }) =>
      PlatformSecurityAlert(
        id: id,
        severity: severity,
        category: PlatformSecurityAlertCategory.authentication,
        title: 'تنبيه',
        description: 'وصف آمن',
        detectedAt: DateTime.utc(2026, 9, 10, 12),
      );

  test('known security values parse and unsupported values fail closed', () {
    for (final value in PlatformSecurityAlertSeverity.values) {
      expect(PlatformSecurityAlertSeverity.parse(value.wire), value);
    }
    for (final value in PlatformSecurityAlertCategory.values) {
      expect(PlatformSecurityAlertCategory.parse(value.wire), value);
    }

    expect(
      PlatformSecurityAlertSeverity.parse('future_severity'),
      PlatformSecurityAlertSeverity.unknown,
    );
    expect(
      PlatformSecurityAlertCategory.parse('future_category'),
      PlatformSecurityAlertCategory.unknown,
    );
  });

  test('security summary uses conservative severity precedence', () {
    expect(
      derivePlatformSecuritySummary(const []),
      PlatformSecuritySummaryState.noAlerts,
    );
    expect(
      derivePlatformSecuritySummary([
        alert(PlatformSecurityAlertSeverity.info),
      ]),
      PlatformSecuritySummaryState.informational,
    );
    expect(
      derivePlatformSecuritySummary([
        alert(PlatformSecurityAlertSeverity.info),
        alert(PlatformSecurityAlertSeverity.warning),
      ]),
      PlatformSecuritySummaryState.warning,
    );
    expect(
      derivePlatformSecuritySummary([
        alert(PlatformSecurityAlertSeverity.warning),
        alert(PlatformSecurityAlertSeverity.unknown),
      ]),
      PlatformSecuritySummaryState.unknown,
    );
    expect(
      derivePlatformSecuritySummary([
        alert(PlatformSecurityAlertSeverity.unknown),
        alert(PlatformSecurityAlertSeverity.critical),
      ]),
      PlatformSecuritySummaryState.critical,
    );
  });

  test('unknown parsed alert stays explicit and timestamps are UTC', () {
    final snapshot = PlatformSecuritySnapshot.fromJson(const {
      'generatedAt': '2026-09-10T15:30:00+03:00',
      'alerts': [
        {
          'id': 'future',
          'severity': 'unsupported',
          'category': 'unsupported',
          'title': 'حالة جديدة',
          'description': 'لا يفهمها هذا الإصدار',
          'detectedAt': '2026-09-10T15:20:00+03:00',
        },
      ],
    });

    expect(snapshot.generatedAt, DateTime.utc(2026, 9, 10, 12, 30));
    expect(
        snapshot.alerts.single.detectedAt, DateTime.utc(2026, 9, 10, 12, 20));
    expect(
      snapshot.alerts.single.severity,
      PlatformSecurityAlertSeverity.unknown,
    );
    expect(
        snapshot.alerts.single.category, PlatformSecurityAlertCategory.unknown);
    expect(snapshot.summaryState, PlatformSecuritySummaryState.unknown);
  });

  test('deleted tenant reference carries only tombstone-safe fields', () {
    final reference = PlatformSecurityTenantReference.fromJson(const {
      'id': 'saas_deleted',
      'displayName': 'فريق محذوف',
      'isDeleted': true,
      'deletedAt': '2026-09-10T12:00:00Z',
    });

    expect(reference.isDeleted, isTrue);
    expect(reference.deletedAt, DateTime.utc(2026, 9, 10, 12));
    expect(reference.toJson().keys, const {
      'id',
      'displayName',
      'isDeleted',
      'deletedAt',
    });
  });
}
