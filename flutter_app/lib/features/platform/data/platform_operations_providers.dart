import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../domain/platform_health_models.dart';
import '../domain/platform_health_repository.dart';
import '../domain/platform_security_models.dart';
import '../domain/platform_security_repository.dart';
import 'mock_platform_health_repository.dart';
import 'mock_platform_security_repository.dart';
import 'platform_operations_fixtures.dart';
import 'saas_tenant_providers.dart';

final platformOperationsFixturesProvider =
    Provider<PlatformOperationsFixtures>((ref) {
  return PlatformOperationsFixtures(
    clock: ref.watch(clockProvider),
    tenantStore: ref.watch(platformTenantStoreProvider),
  );
});

final platformHealthRepositoryProvider =
    Provider<PlatformHealthRepository>((ref) {
  return MockPlatformHealthRepository(
    fixtures: ref.watch(platformOperationsFixturesProvider),
  );
});

final platformSecurityRepositoryProvider =
    Provider<PlatformSecurityRepository>((ref) {
  return MockPlatformSecurityRepository(
    fixtures: ref.watch(platformOperationsFixturesProvider),
  );
});

final platformHealthProvider =
    FutureProvider<Result<PlatformHealthSnapshot>>((ref) {
  return ref.watch(platformHealthRepositoryProvider).loadHealth();
});

final platformSecurityProvider =
    FutureProvider<Result<PlatformSecuritySnapshot>>((ref) {
  return ref.watch(platformSecurityRepositoryProvider).loadSecurityAlerts();
});
