import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/platform_audit_models.dart';
import '../domain/platform_audit_repository.dart';
import '../domain/platform_health_repository.dart';
import '../domain/platform_overview_models.dart';
import '../domain/platform_overview_repository.dart';
import '../domain/platform_security_models.dart';
import '../domain/platform_security_repository.dart';

/// The read-only Super Admin insight seams (`docs/api/platform-insights.md`):
/// overview, health, security alerts and the audit log. Every route sits
/// behind the server's `platformGuard`; nothing here writes.

class HttpPlatformOverviewRepository implements PlatformOverviewRepository {
  HttpPlatformOverviewRepository(this._api);

  final ApiClient _api;

  /// The server reports `usage.storageAllowanceBytes: 0` when no tenant has
  /// an allowance set; the app's model says the same thing by leaving
  /// `usage` out (an allowance is only shown when a truthful one exists).
  @override
  Future<Result<PlatformOverviewSnapshot>> loadOverview() => _api.send(
        'GET',
        '/platform/overview',
        parse: (json) {
          final j = {...json as Map<String, dynamic>};
          final usage = j['usage'];
          if (usage is Map<String, dynamic> &&
              ((usage['storageAllowanceBytes'] as num?) ?? 0) <= 0) {
            j.remove('usage');
          }
          return PlatformOverviewSnapshot.fromJson(j);
        },
      );
}

class HttpPlatformHealthRepository implements PlatformHealthRepository {
  HttpPlatformHealthRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<PlatformHealthSnapshot>> loadHealth() => _api.send(
        'GET',
        '/platform/health',
        parse: (json) =>
            PlatformHealthSnapshot.fromJson(json as Map<String, dynamic>),
      );
}

class HttpPlatformSecurityRepository implements PlatformSecurityRepository {
  HttpPlatformSecurityRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<PlatformSecuritySnapshot>> loadSecurityAlerts() => _api.send(
        'GET',
        '/platform/security-alerts',
        parse: (json) =>
            PlatformSecuritySnapshot.fromJson(json as Map<String, dynamic>),
      );
}

class HttpPlatformAuditRepository implements PlatformAuditRepository {
  HttpPlatformAuditRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<PlatformAuditPage>> listAuditEvents(PlatformAuditQuery query) =>
      _api.send(
        'GET',
        '/platform/audit',
        query: {
          if (query.from != null) 'from': query.from!.toIso8601String(),
          if (query.before != null) 'before': query.before!.toIso8601String(),
          if (query.actorKind != null) 'actorKind': query.actorKind!.wire,
          if (query.actorId != null) 'actorId': query.actorId!,
          if (query.action != null) 'action': query.action!.wire,
          if (query.category != null) 'category': query.category!.wire,
          if (query.tenantId != null) 'tenantId': query.tenantId!,
          if (query.targetType != null) 'targetType': query.targetType!.wire,
          if (query.search.trim().isNotEmpty) 'search': query.search.trim(),
          if (query.cursor != null && query.cursor!.isNotEmpty)
            'cursor': query.cursor!,
          'limit': '${query.limit}',
        },
        parse: (json) =>
            PlatformAuditPage.fromJson(json as Map<String, dynamic>),
      );
}
