import '../../../core/result/result.dart';
import 'tenant_feature_models.dart';

enum TenantFeatureProblemCode {
  tenantNotFound('tenant_not_found'),
  featureNotFound('feature_not_found'),
  invalidFeature('invalid_feature'),
  staleFeatureState('stale_feature_state'),
  notPermitted('not_permitted');

  const TenantFeatureProblemCode(this.wire);
  final String wire;

  static TenantFeatureProblemCode? parse(String? wire) {
    for (final code in values) {
      if (code.wire == wire) return code;
    }
    return null;
  }
}

abstract class TenantFeatureRepository {
  Future<Result<TenantFeatureSet>> getFeatures(String tenantId);

  Future<Result<TenantFeatureState>> setFeatureEnabled(
    SetTenantFeatureCommand command,
  );
}
