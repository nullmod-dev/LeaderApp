import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../domain/platform_overview_models.dart';
import '../domain/platform_overview_repository.dart';
import 'mock_platform_overview_repository.dart';
import 'platform_operations_providers.dart';
import 'saas_tenant_providers.dart';

/// The overview reads the **same** subscriber store the Point 6 list does, so
/// the count on this screen and the rows on that one cannot describe two
/// different customer bases — and so registering a subscriber changes both.
final platformOverviewRepositoryProvider =
    Provider<PlatformOverviewRepository>((ref) {
  return MockPlatformOverviewRepository(
    clock: ref.watch(clockProvider),
    store: ref.watch(platformTenantStoreProvider),
    operationsFixtures: ref.watch(platformOperationsFixturesProvider),
  );
});

/// The platform shell reads no business repository. Only its overview branch
/// asks for this aggregate, keeping tenant operational providers outside the
/// control plane by construction.
final platformOverviewProvider =
    FutureProvider<Result<PlatformOverviewSnapshot>>((ref) async {
  return ref.read(platformOverviewRepositoryProvider).loadOverview();
});
