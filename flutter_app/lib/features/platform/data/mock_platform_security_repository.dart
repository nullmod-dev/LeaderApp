import '../../../core/result/result.dart';
import '../domain/platform_security_models.dart';
import '../domain/platform_security_repository.dart';
import 'platform_operations_fixtures.dart';

enum MockPlatformSecurityMode {
  noAlerts,
  informational,
  warning,
  critical,
  mixed,
  tenantLinked,
  platformWide,
  unknown,
  stale,
  offlineWithCache,
  offlineWithoutCache,
  failure,
}

class MockPlatformSecurityRepository implements PlatformSecurityRepository {
  MockPlatformSecurityRepository({
    required this.fixtures,
    this.mode = MockPlatformSecurityMode.critical,
    this.latency = const Duration(milliseconds: 420),
  });

  final PlatformOperationsFixtures fixtures;
  final MockPlatformSecurityMode mode;
  final Duration latency;

  @override
  Future<Result<PlatformSecuritySnapshot>> loadSecurityAlerts() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return switch (mode) {
      MockPlatformSecurityMode.noAlerts => Success(
          fixtures.security(fixture: PlatformSecurityFixture.noAlerts),
        ),
      MockPlatformSecurityMode.informational => Success(
          fixtures.security(fixture: PlatformSecurityFixture.informational),
        ),
      MockPlatformSecurityMode.warning => Success(
          fixtures.security(fixture: PlatformSecurityFixture.warning),
        ),
      MockPlatformSecurityMode.critical => Success(
          fixtures.security(fixture: PlatformSecurityFixture.critical),
        ),
      MockPlatformSecurityMode.mixed => Success(
          fixtures.security(fixture: PlatformSecurityFixture.mixed),
        ),
      MockPlatformSecurityMode.tenantLinked => Success(
          fixtures.security(fixture: PlatformSecurityFixture.tenantLinked),
        ),
      MockPlatformSecurityMode.platformWide => Success(
          fixtures.security(fixture: PlatformSecurityFixture.platformWide),
        ),
      MockPlatformSecurityMode.unknown => Success(
          fixtures.security(fixture: PlatformSecurityFixture.unknown),
        ),
      MockPlatformSecurityMode.stale => Success(
          fixtures.security(fixture: PlatformSecurityFixture.critical),
          stale: true,
        ),
      MockPlatformSecurityMode.offlineWithCache => Offline(
          cached: fixtures.security(fixture: PlatformSecurityFixture.critical),
        ),
      MockPlatformSecurityMode.offlineWithoutCache => const Offline(),
      MockPlatformSecurityMode.failure => const Failure(
          'تعذّر تحميل تنبيهات المنصة.',
          code: 'server',
        ),
    };
  }
}
