import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../domain/platform_report_datasets.dart';
import '../domain/platform_reports_repository.dart';
import 'mock_platform_reports_repository.dart';
import 'platform_audit_providers.dart';
import 'saas_tenant_providers.dart';

/// Development/test knobs for the Point 13A mock. A real backend replaces the
/// repository provider and this config disappears.
@immutable
class MockPlatformReportsConfig {
  const MockPlatformReportsConfig({
    this.mode = MockPlatformReportsMode.loaded,
    this.latency = const Duration(milliseconds: 350),
    this.auditRetention,
  });

  final MockPlatformReportsMode mode;
  final Duration latency;
  final Duration? auditRetention;
}

final platformReportsMockConfigProvider =
    Provider<MockPlatformReportsConfig>((ref) {
  return const MockPlatformReportsConfig();
});

/// The Platform Reports seam. The mock shares the canonical tenant store and
/// the Audit fixtures (data, not repositories), so reports agree with tenant
/// management and with the Audit drill-down.
final platformReportsRepositoryProvider =
    Provider<PlatformReportsRepository>((ref) {
  final config = ref.watch(platformReportsMockConfigProvider);
  return MockPlatformReportsRepository(
    store: ref.watch(platformTenantStoreProvider),
    auditFixtures: ref.watch(platformAuditFixturesProvider),
    clock: ref.watch(clockProvider),
    mode: config.mode,
    latency: config.latency,
    auditRetention: config.auditRetention,
  );
});

// First-page reads, keyed by value-equal queries. Later pages are requested
// through the repository by 13B's rows controller with the opaque cursor and
// folded with `PlatformReportRowsState`; they are never family keys.

final subscriptionReportProvider = FutureProvider.autoDispose
    .family<Result<SubscriptionReport>, SubscriptionReportQuery>((ref, query) {
  return ref
      .watch(platformReportsRepositoryProvider)
      .loadSubscriptions(query.firstPage);
});

final usageLimitsReportProvider = FutureProvider.autoDispose
    .family<Result<UsageLimitsReport>, UsageLimitsReportQuery>((ref, query) {
  return ref
      .watch(platformReportsRepositoryProvider)
      .loadUsageLimits(query.firstPage);
});

final featureAvailabilityReportProvider = FutureProvider.autoDispose
    .family<Result<FeatureAvailabilityReport>, FeatureAvailabilityReportQuery>(
        (ref, query) {
  return ref
      .watch(platformReportsRepositoryProvider)
      .loadFeatureAvailability(query.firstPage);
});

final platformActivityReportProvider = FutureProvider.autoDispose
    .family<Result<PlatformActivityReport>, PlatformActivityReportQuery>(
        (ref, query) {
  return ref
      .watch(platformReportsRepositoryProvider)
      .loadPlatformActivity(query);
});
