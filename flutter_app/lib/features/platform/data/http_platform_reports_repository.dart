import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/platform_report_datasets.dart';
import '../domain/platform_reports_repository.dart';

/// `GET /platform/reports/*` (`docs/api/platform-insights.md` → Reports).
/// The four closed reports, computed on the server; each query already
/// knows its own wire parameters, and each report parses against the query
/// that produced it.
class HttpPlatformReportsRepository implements PlatformReportsRepository {
  HttpPlatformReportsRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<SubscriptionReport>> loadSubscriptions(
    SubscriptionReportQuery query,
  ) =>
      _api.send(
        'GET',
        '/platform/reports/subscriptions',
        query: query.toQueryParameters(),
        parse: (json) => SubscriptionReport.fromJson(
          json as Map<String, dynamic>,
          query: query,
        ),
      );

  @override
  Future<Result<UsageLimitsReport>> loadUsageLimits(
    UsageLimitsReportQuery query,
  ) =>
      _api.send(
        'GET',
        '/platform/reports/usage-limits',
        query: query.toQueryParameters(),
        parse: (json) => UsageLimitsReport.fromJson(
          json as Map<String, dynamic>,
          query: query,
        ),
      );

  @override
  Future<Result<FeatureAvailabilityReport>> loadFeatureAvailability(
    FeatureAvailabilityReportQuery query,
  ) =>
      _api.send(
        'GET',
        '/platform/reports/feature-availability',
        query: query.toQueryParameters(),
        parse: (json) => FeatureAvailabilityReport.fromJson(
          json as Map<String, dynamic>,
          query: query,
        ),
      );

  @override
  Future<Result<PlatformActivityReport>> loadPlatformActivity(
    PlatformActivityReportQuery query,
  ) =>
      _api.send(
        'GET',
        '/platform/reports/platform-activity',
        query: query.toQueryParameters(),
        parse: (json) => PlatformActivityReport.fromJson(
          json as Map<String, dynamic>,
          query: query,
        ),
      );
}
