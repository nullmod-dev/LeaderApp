import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../../tenant_feature/domain/tenant_feature_models.dart';
import '../../tenant_feature/domain/tenant_feature_repository.dart';

/// `/platform/tenants/:id/features` (`docs/api/platform-tenants.md` §§19–20).
/// Each feature row carries its own version; disabling never deletes data.
class HttpTenantFeatureRepository implements TenantFeatureRepository {
  HttpTenantFeatureRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<TenantFeatureSet>> getFeatures(String tenantId) => _api.send(
        'GET',
        '/platform/tenants/${Uri.encodeComponent(tenantId)}/features',
        parse: (json) =>
            TenantFeatureSet.fromJson(json as Map<String, dynamic>),
      );

  @override
  Future<Result<TenantFeatureState>> setFeatureEnabled(
    SetTenantFeatureCommand command,
  ) =>
      _api.send(
        'PATCH',
        '/platform/tenants/${Uri.encodeComponent(command.tenantId)}'
            '/features/${command.key.wire}',
        body: {
          'enabled': command.enabled,
          'expectedVersion': command.expectedVersion,
        },
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: (json) {
          final j = json as Map<String, dynamic>;
          return TenantFeatureState(
            key: TenantFeatureKey.parse(j['key'] as String?) ?? command.key,
            enabled: j['enabled'] as bool,
            version: (j['version'] as num).toInt(),
            updatedAt: DateTime.parse(j['updatedAt'] as String).toUtc(),
          );
        },
      );
}
