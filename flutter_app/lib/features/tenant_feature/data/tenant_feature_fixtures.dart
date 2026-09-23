import '../domain/tenant_feature_models.dart';

/// Deterministic variations over the same eight canonical SaaS tenants.
const Map<String, Set<TenantFeatureKey>> canonicalTenantFeatureConfiguration = {
  'saas_hilal': {...TenantFeatureKey.values},
  'saas_najd': {
    TenantFeatureKey.statisticsReports,
    TenantFeatureKey.workshops,
    TenantFeatureKey.announcements,
  },
  'saas_sahel': {
    TenantFeatureKey.inventory,
    TenantFeatureKey.statisticsReports,
    TenantFeatureKey.announcements,
  },
  'saas_wadi': {
    TenantFeatureKey.inventory,
  },
  'saas_nabd': defaultEnabledTenantFeatures,
  'saas_masar': {
    TenantFeatureKey.inventory,
    TenantFeatureKey.statisticsReports,
    TenantFeatureKey.announcements,
  },
  'saas_afiah': {
    TenantFeatureKey.inventory,
    TenantFeatureKey.workshops,
    TenantFeatureKey.announcements,
  },
  'saas_rukn': {},
};

TenantFeatureSet initialTenantFeatureSet({
  required String tenantId,
  required String tenantName,
  required DateTime updatedAt,
  Set<TenantFeatureKey>? enabled,
}) {
  final active = enabled ??
      canonicalTenantFeatureConfiguration[tenantId] ??
      defaultEnabledTenantFeatures;
  return TenantFeatureSet(
    tenantId: tenantId,
    tenantName: tenantName,
    states: {
      for (final key in TenantFeatureKey.values)
        key: TenantFeatureState(
          key: key,
          enabled: active.contains(key),
          version: 1,
          updatedAt: updatedAt.toUtc(),
        ),
    },
  );
}
