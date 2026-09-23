import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/platform/domain/platform_health_models.dart';

void main() {
  PlatformHealthSignal signal(
    PlatformHealthStatus status, {
    String id = 'signal',
  }) =>
      PlatformHealthSignal(
        id: id,
        label: 'إشارة',
        status: status,
        summary: 'ملخص آمن',
        observedAt: DateTime.parse('2026-09-10T12:00:00+03:00'),
      );

  test('known health wire values parse and unsupported values fail closed', () {
    for (final value in PlatformHealthStatus.values) {
      expect(PlatformHealthStatus.parse(value.wire), value);
    }

    expect(
      PlatformHealthStatus.parse('future_healthy_like_value'),
      PlatformHealthStatus.unknown,
    );
  });

  test('overall health is conservative and empty data is unknown', () {
    expect(deriveOverallPlatformHealth(const []), PlatformHealthStatus.unknown);
    expect(
      deriveOverallPlatformHealth([signal(PlatformHealthStatus.healthy)]),
      PlatformHealthStatus.healthy,
    );
    expect(
      deriveOverallPlatformHealth([
        signal(PlatformHealthStatus.healthy),
        signal(PlatformHealthStatus.unknown),
      ]),
      PlatformHealthStatus.unknown,
    );
    expect(
      deriveOverallPlatformHealth([
        signal(PlatformHealthStatus.unknown),
        signal(PlatformHealthStatus.degraded),
      ]),
      PlatformHealthStatus.degraded,
    );
    expect(
      deriveOverallPlatformHealth([
        signal(PlatformHealthStatus.degraded),
        signal(PlatformHealthStatus.unavailable),
      ]),
      PlatformHealthStatus.unavailable,
    );
  });

  test('snapshot parsing normalizes timestamps and preserves partial truth',
      () {
    final snapshot = PlatformHealthSnapshot.fromJson(const {
      'generatedAt': '2026-09-10T15:30:00+03:00',
      'isPartial': true,
      'signals': [
        {
          'id': 'identity',
          'label': 'الدخول والجلسات',
          'status': 'future_status',
          'summary': 'الحالة غير مفهومة',
          'observedAt': '2026-09-10T15:28:00+03:00',
        },
      ],
    });

    expect(snapshot.generatedAt, DateTime.utc(2026, 9, 10, 12, 30));
    expect(
        snapshot.signals.single.observedAt, DateTime.utc(2026, 9, 10, 12, 28));
    expect(snapshot.signals.single.status, PlatformHealthStatus.unknown);
    expect(snapshot.overallStatus, PlatformHealthStatus.unknown);
    expect(snapshot.isPartial, isTrue);
    expect(snapshot.toJson()['isPartial'], isTrue);
  });
}
