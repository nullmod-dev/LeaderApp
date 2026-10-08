import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/saas_tenant_models.dart';
import '../domain/saas_tenant_repository.dart';

/// `/platform/tenants` (`docs/api/platform-tenants.md` §§1–5). Super Admin
/// only — the server's `platformGuard` refuses any other session.
class HttpSaasTenantRepository implements SaasTenantRepository {
  HttpSaasTenantRepository(this._api);

  final ApiClient _api;

  static String _one(String id) =>
      '/platform/tenants/${Uri.encodeComponent(id)}';

  @override
  Future<Result<SaasTenantPage>> list(SaasTenantQuery query) => _api.send(
        'GET',
        '/platform/tenants',
        query: {
          if (query.search.trim().isNotEmpty) 'search': query.search.trim(),
          if (query.status != null) 'status': query.status!.wire,
          if (query.cursor != null) 'cursor': query.cursor!,
          'limit': '${query.limit.clamp(1, 100)}',
        },
        parse: (json) => SaasTenantPage.fromJson(json as Map<String, dynamic>),
      );

  /// After final deletion the server answers a tombstone, which this model
  /// cannot hold; it reads as `not_found` here (decision D9).
  @override
  Future<Result<SaasTenant>> byId(String tenantId) async {
    final outcome = await _api.exchange('GET', _one(tenantId));
    if (outcome is ApiReply &&
        outcome.ok &&
        outcome.json is Map<String, dynamic> &&
        (outcome.json as Map<String, dynamic>)['status'] == 'deleted') {
      return Failure(failureMessage('not_found'), code: 'not_found');
    }
    return ApiClient.resultOf(
      outcome,
      (json) => SaasTenant.fromJson(json as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<SaasTenant>> create(SaasTenantDraft draft) {
    final d = draft.normalized;
    return _api.send(
      'POST',
      '/platform/tenants',
      body: {
        'displayName': d.displayName,
        'mainAdminName': d.mainAdminName,
        'mainAdminEmail': d.mainAdminEmail,
        // Absent → the server generates one with its own generator.
        if (d.teamCode.isNotEmpty) 'teamCode': d.teamCode,
      },
      idempotencyKey: ApiClient.newIdempotencyKey(),
      parse: (json) => SaasTenant.fromJson(json as Map<String, dynamic>),
    );
  }

  @override
  Future<Result<List<SaasTenantEvent>>> statusHistory(String tenantId) =>
      _api.send(
        'GET',
        '${_one(tenantId)}/status-history',
        parse: (json) => [
          for (final row in json as List)
            SaasTenantEvent.fromJson(row as Map<String, dynamic>),
        ],
      );
}
