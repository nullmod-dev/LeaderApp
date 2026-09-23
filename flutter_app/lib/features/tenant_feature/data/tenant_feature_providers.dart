import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../auth/data/auth_providers.dart';
import '../../platform/data/saas_tenant_providers.dart';
import '../domain/tenant_feature_models.dart';
import '../domain/tenant_feature_repository.dart';
import 'mock_tenant_feature_repository.dart';

final tenantFeatureRepositoryProvider =
    Provider<TenantFeatureRepository>((ref) {
  return MockTenantFeatureRepository(
    store: ref.watch(platformTenantStoreProvider),
  );
});

final tenantFeaturesProvider = FutureProvider.autoDispose
    .family<Result<TenantFeatureSet>, String>((ref, tenantId) {
  return ref.watch(tenantFeatureRepositoryProvider).getFeatures(tenantId);
});

/// A cheap invalidation token shared by router, navigation and tenant sources.
/// The canonical data remains in [PlatformTenantStore]; this only tells live
/// consumers to re-evaluate it after a platform mutation.
class TenantFeatureRevisionController extends Notifier<int> {
  @override
  int build() => 0;

  void changed() => state++;
}

final tenantFeatureRevisionProvider =
    NotifierProvider<TenantFeatureRevisionController, int>(
  TenantFeatureRevisionController.new,
);

enum TenantFeatureContextKind { tenant, unavailable, customerDemo }

/// The modules the Customer Demo workspace shows. Everything the trial is
/// meant to demonstrate, and nothing that would need a real subscription.
const demoTenantFeatures = <TenantFeatureKey>{
  TenantFeatureKey.inventory,
  TenantFeatureKey.statisticsReports,
  TenantFeatureKey.workshops,
  TenantFeatureKey.announcements,
};

class TenantFeatureAccess {
  const TenantFeatureAccess._(this.kind, this.features);

  const TenantFeatureAccess.tenant(TenantFeatureSet features)
      : this._(TenantFeatureContextKind.tenant, features);
  const TenantFeatureAccess.unavailable()
      : this._(TenantFeatureContextKind.unavailable, null);
  const TenantFeatureAccess.customerDemo()
      : this._(TenantFeatureContextKind.customerDemo, null);

  final TenantFeatureContextKind kind;
  final TenantFeatureSet? features;

  /// Unknown, missing, malformed and wrong-tenant state all fail closed.
  ///
  /// Customer Demo is the one context that is not a tenant and still has
  /// modules: the demo shows the product, so its module set is a **product
  /// decision** ([demoTenantFeatures]) rather than a subscription. It is
  /// fixed, it is never read from a tenant, and it can never widen one — a
  /// demo session has no `saasTenantId` for a feature to be granted against.
  bool isAvailable(TenantFeatureKey key) => switch (kind) {
        TenantFeatureContextKind.tenant => features?.isEnabled(key) == true,
        TenantFeatureContextKind.customerDemo =>
          demoTenantFeatures.contains(key),
        TenantFeatureContextKind.unavailable => false,
      };
}

/// The one tenant-side answer to "does this SaaS tenant have this module?".
/// It reads only the authenticated `saasTenantId`; no organisation label,
/// detachment, Team Code or email participates.
final currentTenantFeatureAccessProvider = Provider<TenantFeatureAccess>((ref) {
  ref.watch(tenantFeatureRevisionProvider);
  final access = ref.watch(sessionAccessProvider);
  if (access.isDemo) return const TenantFeatureAccess.customerDemo();
  final user = ref.watch(currentUserProvider).valueOrNull;
  final tenantId = user?.saasTenantId;
  if (tenantId == null || tenantId.isEmpty) {
    return const TenantFeatureAccess.unavailable();
  }
  final set = ref.watch(platformTenantStoreProvider).featuresOf(tenantId);
  return set == null
      ? const TenantFeatureAccess.unavailable()
      : TenantFeatureAccess.tenant(set);
});

/// Async companion for data pipelines that may start while authentication is
/// still restoring. It reaches the same [TenantFeatureAccess] decision after
/// awaiting the account instead of treating the transient loading frame as a
/// missing tenant configuration.
final currentTenantFeatureAccessFutureProvider =
    FutureProvider<TenantFeatureAccess>((ref) async {
  ref.watch(tenantFeatureRevisionProvider);
  final access = ref.watch(sessionAccessProvider);
  if (access.isDemo) return const TenantFeatureAccess.customerDemo();
  final user = await ref.watch(currentUserProvider.future);
  final tenantId = user?.saasTenantId;
  if (tenantId == null || tenantId.isEmpty) {
    return const TenantFeatureAccess.unavailable();
  }
  final set = ref.read(platformTenantStoreProvider).featuresOf(tenantId);
  return set == null
      ? const TenantFeatureAccess.unavailable()
      : TenantFeatureAccess.tenant(set);
});

final tenantFeatureAvailableProvider =
    Provider.family<bool, TenantFeatureKey>((ref, key) {
  return ref.watch(currentTenantFeatureAccessProvider).isAvailable(key);
});

enum TenantFeatureActionKind { enable, disable }

class TenantFeatureActionState {
  const TenantFeatureActionState({this.key, this.kind});
  final TenantFeatureKey? key;
  final TenantFeatureActionKind? kind;
  bool get isSubmitting => key != null;
}

sealed class TenantFeatureActionOutcome {
  const TenantFeatureActionOutcome();
}

class TenantFeatureActionSucceeded extends TenantFeatureActionOutcome {
  const TenantFeatureActionSucceeded(this.state);
  final TenantFeatureState state;
}

class TenantFeatureActionOffline extends TenantFeatureActionOutcome {
  const TenantFeatureActionOffline();
}

class TenantFeatureActionStale extends TenantFeatureActionOutcome {
  const TenantFeatureActionStale();
}

class TenantFeatureActionInvalid extends TenantFeatureActionOutcome {
  const TenantFeatureActionInvalid();
}

class TenantFeatureActionFailed extends TenantFeatureActionOutcome {
  const TenantFeatureActionFailed();
}

class TenantFeatureActionIgnored extends TenantFeatureActionOutcome {
  const TenantFeatureActionIgnored();
}

class TenantFeatureActionController extends Notifier<TenantFeatureActionState> {
  @override
  TenantFeatureActionState build() => const TenantFeatureActionState();

  Future<TenantFeatureActionOutcome> setEnabled(
    SetTenantFeatureCommand command,
  ) async {
    if (state.isSubmitting) return const TenantFeatureActionIgnored();
    state = TenantFeatureActionState(
      key: command.key,
      kind: command.enabled
          ? TenantFeatureActionKind.enable
          : TenantFeatureActionKind.disable,
    );
    try {
      final result = await ref
          .read(tenantFeatureRepositoryProvider)
          .setFeatureEnabled(command);
      return result.when(
        success: (updated, {stale = false}) {
          ref.invalidate(tenantFeaturesProvider(command.tenantId));
          ref.read(tenantFeatureRevisionProvider.notifier).changed();
          return TenantFeatureActionSucceeded(updated);
        },
        failure: (_, code) {
          final parsed = TenantFeatureProblemCode.parse(code);
          if (parsed == TenantFeatureProblemCode.staleFeatureState) {
            ref.invalidate(tenantFeaturesProvider(command.tenantId));
            return const TenantFeatureActionStale();
          }
          if (parsed == TenantFeatureProblemCode.featureNotFound ||
              parsed == TenantFeatureProblemCode.invalidFeature ||
              parsed == TenantFeatureProblemCode.tenantNotFound ||
              parsed == TenantFeatureProblemCode.notPermitted) {
            return const TenantFeatureActionInvalid();
          }
          return const TenantFeatureActionFailed();
        },
        offline: (_) => const TenantFeatureActionOffline(),
      );
    } finally {
      state = const TenantFeatureActionState();
    }
  }
}

final tenantFeatureActionControllerProvider =
    NotifierProvider<TenantFeatureActionController, TenantFeatureActionState>(
  TenantFeatureActionController.new,
);
