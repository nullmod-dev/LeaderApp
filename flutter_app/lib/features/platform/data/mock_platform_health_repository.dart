import '../../../core/result/result.dart';
import '../domain/platform_health_models.dart';
import '../domain/platform_health_repository.dart';
import 'platform_operations_fixtures.dart';

enum MockPlatformHealthMode {
  healthy,
  degraded,
  partial,
  unavailable,
  unknown,
  stale,
  offlineWithCache,
  offlineWithoutCache,
  failure,
}

class MockPlatformHealthRepository implements PlatformHealthRepository {
  MockPlatformHealthRepository({
    required this.fixtures,
    this.mode = MockPlatformHealthMode.degraded,
    this.latency = const Duration(milliseconds: 420),
  });

  final PlatformOperationsFixtures fixtures;
  final MockPlatformHealthMode mode;
  final Duration latency;

  @override
  Future<Result<PlatformHealthSnapshot>> loadHealth() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return switch (mode) {
      MockPlatformHealthMode.healthy =>
        Success(fixtures.health(fixture: PlatformHealthFixture.healthy)),
      MockPlatformHealthMode.degraded =>
        Success(fixtures.health(fixture: PlatformHealthFixture.degraded)),
      MockPlatformHealthMode.partial =>
        Success(fixtures.health(fixture: PlatformHealthFixture.partial)),
      MockPlatformHealthMode.unavailable =>
        Success(fixtures.health(fixture: PlatformHealthFixture.unavailable)),
      MockPlatformHealthMode.unknown =>
        Success(fixtures.health(fixture: PlatformHealthFixture.unknown)),
      MockPlatformHealthMode.stale => Success(
          fixtures.health(fixture: PlatformHealthFixture.degraded),
          stale: true,
        ),
      MockPlatformHealthMode.offlineWithCache => Offline(
          cached: fixtures.health(fixture: PlatformHealthFixture.degraded),
        ),
      MockPlatformHealthMode.offlineWithoutCache => const Offline(),
      MockPlatformHealthMode.failure => const Failure(
          'تعذّر تحميل صحة المنصة.',
          code: 'server',
        ),
    };
  }
}
