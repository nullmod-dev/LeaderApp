import '../../../core/result/result.dart';
import 'platform_report_datasets.dart';

/// Point 13A — the one read seam for the closed Platform Reports catalogue.
///
/// Read-only and synchronous (direct reads of server-computed report
/// projections; no report jobs). Separate from Audit, Security, Health,
/// Break-glass, Overview, lifecycle and every tenant-operational repository:
/// a report composes control-plane data **on the server**, never by opening
/// other repositories or a tenant's local datastore on the client.
///
/// Every method: `Success` (optionally `stale`), `Offline` with or without a
/// cached result, or `Failure` with `validation`, `not_permitted`, `server`,
/// or a `PlatformReportProblemCode`. A cursor is honoured only for the snapshot
/// that issued it; paging is online-only.
abstract interface class PlatformReportsRepository {
  Future<Result<SubscriptionReport>> loadSubscriptions(
    SubscriptionReportQuery query,
  );

  Future<Result<UsageLimitsReport>> loadUsageLimits(
    UsageLimitsReportQuery query,
  );

  Future<Result<FeatureAvailabilityReport>> loadFeatureAvailability(
    FeatureAvailabilityReportQuery query,
  );

  Future<Result<PlatformActivityReport>> loadPlatformActivity(
    PlatformActivityReportQuery query,
  );
}
