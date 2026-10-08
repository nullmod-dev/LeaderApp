import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_providers.dart';
import '../../../core/result/result.dart';
import '../../auth/data/auth_providers.dart';
import '../domain/tenant_feature_models.dart';
import 'tenant_feature_providers.dart';

/// `GET /tenant/features` (`docs/api/tenant-administration.md` §4) — the
/// tenant app's own read of which modules its organisation has. The tenant
/// is the caller's; [tenantId] only labels the parsed set.
Future<Result<TenantFeatureSet>> readCurrentTenantFeatures(
  ApiClient api,
  String tenantId,
) =>
    api.send(
      'GET',
      '/tenant/features',
      parse: (json) => TenantFeatureSet.fromJson({
        ...json as Map<String, dynamic>,
        'tenantId': tenantId,
      }),
    );

/// The last set each tenant answered, so an offline relaunch inside the same
/// process keeps the modules it already knew instead of hiding them.
final Map<String, TenantFeatureSet> _lastKnown = {};

/// The signed-in tenant's module set from the server — what
/// `currentTenantFeatureAccessProvider` reads in a backend build (decision
/// D6). `null` (no tenant, or nothing could be read) fails closed there.
final remoteTenantFeaturesProvider =
    FutureProvider<TenantFeatureSet?>((ref) async {
  ref.watch(tenantFeatureRevisionProvider);
  final user = await ref.watch(currentUserProvider.future);
  final tenantId = user?.saasTenantId;
  if (tenantId == null || tenantId.isEmpty) return null;
  final result =
      await readCurrentTenantFeatures(ref.watch(apiClientProvider), tenantId);
  return switch (result) {
    Success(:final data) => _lastKnown[tenantId] = data,
    Offline() => _lastKnown[tenantId],
    Failure() => null,
  };
});
