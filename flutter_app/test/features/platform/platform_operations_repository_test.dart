import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/platform/data/mock_platform_health_repository.dart';
import 'package:mtm/features/platform/data/mock_platform_security_repository.dart';
import 'package:mtm/features/platform/data/platform_operations_fixtures.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/domain/platform_health_models.dart';
import 'package:mtm/features/platform/domain/platform_security_models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10, 16);

  PlatformOperationsFixtures fixtures(DateTime instant) =>
      PlatformOperationsFixtures(
        clock: () => instant,
        tenantStore: PlatformTenantStore(clock: () => instant),
      );

  Future<PlatformHealthSnapshot> health(
    MockPlatformHealthMode mode, {
    DateTime? instant,
  }) async {
    final result = await MockPlatformHealthRepository(
      fixtures: fixtures(instant ?? now),
      mode: mode,
      latency: Duration.zero,
    ).loadHealth();
    return result.when(
      success: (data, {stale = false}) => data,
      failure: (message, code) => throw TestFailure('$code: $message'),
      offline: (_) => throw TestFailure('unexpected offline'),
    );
  }

  Future<PlatformSecuritySnapshot> security(
    MockPlatformSecurityMode mode, {
    DateTime? instant,
  }) async {
    final result = await MockPlatformSecurityRepository(
      fixtures: fixtures(instant ?? now),
      mode: mode,
      latency: Duration.zero,
    ).loadSecurityAlerts();
    return result.when(
      success: (data, {stale = false}) => data,
      failure: (message, code) => throw TestFailure('$code: $message'),
      offline: (_) => throw TestFailure('unexpected offline'),
    );
  }

  test('health fixtures are deterministic and move only with Clock', () async {
    final first = await health(MockPlatformHealthMode.degraded);
    final repeated = await health(MockPlatformHealthMode.degraded);
    final later = await health(
      MockPlatformHealthMode.degraded,
      instant: now.add(const Duration(days: 2)),
    );

    expect(first.toJson(), repeated.toJson());
    expect(first.generatedAt, now.subtract(const Duration(minutes: 6)));
    expect(
      later.generatedAt.difference(first.generatedAt),
      const Duration(days: 2),
    );
    for (var index = 0; index < first.signals.length; index++) {
      expect(
        later.signals[index].observedAt.difference(
          first.signals[index].observedAt,
        ),
        const Duration(days: 2),
      );
    }
  });

  test('health modes distinguish platform state from result state', () async {
    expect(
      (await health(MockPlatformHealthMode.healthy)).overallStatus,
      PlatformHealthStatus.healthy,
    );
    expect(
      (await health(MockPlatformHealthMode.degraded)).overallStatus,
      PlatformHealthStatus.degraded,
    );
    final partial = await health(MockPlatformHealthMode.partial);
    expect(partial.isPartial, isTrue);
    expect(partial.signals, hasLength(2));
    expect(
      (await health(MockPlatformHealthMode.unavailable)).overallStatus,
      PlatformHealthStatus.unavailable,
    );
    expect(
      (await health(MockPlatformHealthMode.unknown)).overallStatus,
      PlatformHealthStatus.unknown,
    );
  });

  test('health stale, offline and failure outcomes remain typed', () async {
    Future<Result<PlatformHealthSnapshot>> load(MockPlatformHealthMode mode) =>
        MockPlatformHealthRepository(
          fixtures: fixtures(now),
          mode: mode,
          latency: Duration.zero,
        ).loadHealth();

    final stale = await load(MockPlatformHealthMode.stale);
    expect(stale, isA<Success<PlatformHealthSnapshot>>());
    expect((stale as Success<PlatformHealthSnapshot>).stale, isTrue);

    final cached = await load(MockPlatformHealthMode.offlineWithCache);
    expect(cached, isA<Offline<PlatformHealthSnapshot>>());
    expect((cached as Offline<PlatformHealthSnapshot>).cached, isNotNull);

    final empty = await load(MockPlatformHealthMode.offlineWithoutCache);
    expect(empty, isA<Offline<PlatformHealthSnapshot>>());
    expect((empty as Offline<PlatformHealthSnapshot>).cached, isNull);

    final failure = await load(MockPlatformHealthMode.failure);
    expect(failure, isA<Failure<PlatformHealthSnapshot>>());
    expect((failure as Failure<PlatformHealthSnapshot>).code, 'server');
  });

  test('security fixtures are deterministic, ordered, and Clock-based',
      () async {
    final first = await security(MockPlatformSecurityMode.mixed);
    final repeated = await security(MockPlatformSecurityMode.mixed);
    final later = await security(
      MockPlatformSecurityMode.mixed,
      instant: now.add(const Duration(hours: 5)),
    );

    expect(first.toJson(), repeated.toJson());
    expect(first.generatedAt, now.subtract(const Duration(minutes: 6)));
    for (var index = 1; index < first.alerts.length; index++) {
      expect(
        first.alerts[index - 1].detectedAt
            .isBefore(first.alerts[index].detectedAt),
        isFalse,
      );
    }
    for (var index = 0; index < first.alerts.length; index++) {
      expect(
        later.alerts[index].detectedAt.difference(
          first.alerts[index].detectedAt,
        ),
        const Duration(hours: 5),
      );
    }
  });

  test('security modes cover empty, linked, platform-wide and unknown',
      () async {
    expect(
      (await security(MockPlatformSecurityMode.noAlerts)).alerts,
      isEmpty,
    );
    final linked = await security(MockPlatformSecurityMode.tenantLinked);
    expect(linked.alerts.single.affectedTenant?.id, 'saas_hilal');
    expect(linked.alerts.single.affectedTenant?.isDeleted, isFalse);

    final platformWide = await security(MockPlatformSecurityMode.platformWide);
    expect(platformWide.alerts.single.affectedTenant, isNull);

    final unknown = await security(MockPlatformSecurityMode.unknown);
    expect(
        unknown.alerts.single.severity, PlatformSecurityAlertSeverity.unknown);
    expect(unknown.summaryState, PlatformSecuritySummaryState.unknown);
  });

  test('security stale, offline and failure outcomes remain typed', () async {
    Future<Result<PlatformSecuritySnapshot>> load(
      MockPlatformSecurityMode mode,
    ) =>
        MockPlatformSecurityRepository(
          fixtures: fixtures(now),
          mode: mode,
          latency: Duration.zero,
        ).loadSecurityAlerts();

    final stale = await load(MockPlatformSecurityMode.stale);
    expect(stale, isA<Success<PlatformSecuritySnapshot>>());
    expect((stale as Success<PlatformSecuritySnapshot>).stale, isTrue);

    final cached = await load(MockPlatformSecurityMode.offlineWithCache);
    expect(cached, isA<Offline<PlatformSecuritySnapshot>>());
    expect((cached as Offline<PlatformSecuritySnapshot>).cached, isNotNull);

    final empty = await load(MockPlatformSecurityMode.offlineWithoutCache);
    expect(empty, isA<Offline<PlatformSecuritySnapshot>>());
    expect((empty as Offline<PlatformSecuritySnapshot>).cached, isNull);

    final failure = await load(MockPlatformSecurityMode.failure);
    expect(failure, isA<Failure<PlatformSecuritySnapshot>>());
    expect((failure as Failure<PlatformSecuritySnapshot>).code, 'server');
  });
}
