import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../../platform/data/platform_tenant_store.dart';
import '../domain/tenant_feature_models.dart';
import '../domain/tenant_feature_repository.dart';

enum MockTenantFeatureMode {
  loaded,
  offlineWithCache,
  offlineWithoutCache,
  failure,
  unavailable,
}

class MockTenantFeatureRepository implements TenantFeatureRepository {
  MockTenantFeatureRepository({
    required this.store,
    this.mode = MockTenantFeatureMode.loaded,
    this.latency = const Duration(milliseconds: 240),
  });

  final PlatformTenantStore store;
  final MockTenantFeatureMode mode;
  final Duration latency;

  Future<void> _wait() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  @override
  Future<Result<TenantFeatureSet>> getFeatures(String tenantId) async {
    await _wait();
    final cached = store.featuresOf(tenantId);
    if (mode == MockTenantFeatureMode.offlineWithCache) {
      return Offline(cached: cached);
    }
    if (mode == MockTenantFeatureMode.offlineWithoutCache) {
      return const Offline();
    }
    if (mode == MockTenantFeatureMode.failure) return _safeFailure();
    if (cached == null) return _tenantNotFound();
    if (mode == MockTenantFeatureMode.unavailable) {
      return const Failure(
        'حالة الميزات غير متاحة الآن.',
        code: 'feature_not_found',
      );
    }
    return Success(cached);
  }

  @override
  Future<Result<TenantFeatureState>> setFeatureEnabled(
    SetTenantFeatureCommand command,
  ) async {
    await _wait();
    if (mode == MockTenantFeatureMode.offlineWithCache ||
        mode == MockTenantFeatureMode.offlineWithoutCache) {
      return const Offline();
    }
    if (mode == MockTenantFeatureMode.failure ||
        mode == MockTenantFeatureMode.unavailable) {
      return _safeFailure();
    }
    final current = store.featuresOf(command.tenantId);
    if (current == null) return _tenantNotFound();
    final state = current.stateOf(command.key);
    if (state == null) return _featureNotFound();
    if (state.version != command.expectedVersion) {
      return const Failure(
        'تغيّرت حالة الميزة. حدّث الصفحة ثم أعد المحاولة.',
        code: 'stale_feature_state',
      );
    }
    return Success(store.updateFeature(
      command.tenantId,
      command.key,
      command.enabled,
    ));
  }

  Failure<T> _tenantNotFound<T>() => const Failure(
        'الفريق غير موجود.',
        code: 'tenant_not_found',
      );

  Failure<T> _featureNotFound<T>() => const Failure(
        'الميزة غير موجودة في حالة هذا الفريق.',
        code: 'feature_not_found',
      );

  Failure<T> _safeFailure<T>() => Failure(
        'تعذّر إتمام العملية بأمان.',
        code: ProblemCode.server.wire,
      );
}
