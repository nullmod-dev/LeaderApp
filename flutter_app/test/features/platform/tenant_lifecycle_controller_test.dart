import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_tenant_lifecycle_repository.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/data/tenant_lifecycle_providers.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 9, 12);

  ProviderContainer container({
    MockTenantLifecycleMode mode = MockTenantLifecycleMode.loaded,
    Duration latency = Duration.zero,
  }) {
    final result = ProviderContainer(overrides: [
      clockProvider.overrideWithValue(() => now),
      tenantLifecycleRepositoryProvider.overrideWith((ref) {
        return MockTenantLifecycleRepository(
          store: ref.watch(platformTenantStoreProvider),
          clock: () => now,
          mode: mode,
          latency: latency,
        );
      }),
    ]);
    addTearDown(result.dispose);
    return result;
  }

  test('guards duplicate submissions in the controller', () async {
    final scope = container(latency: const Duration(milliseconds: 20));
    final tenant = scope.read(platformTenantStoreProvider).byId('saas_hilal')!;
    final controller =
        scope.read(tenantLifecycleActionControllerProvider.notifier);
    final command = SuspendTenantCommand(
      tenantId: tenant.id,
      expectedVersion: tenant.tenantVersion,
      idempotencyKey: 'controller-duplicate',
      reason: 'سبب موثق',
    );

    final first = controller.suspend(command);
    final second = await controller.suspend(command);
    expect(second, isA<TenantLifecycleActionIgnored>());
    expect(await first, isA<TenantLifecycleActionSucceeded>());
    expect(scope.read(tenantLifecycleActionControllerProvider).isSubmitting,
        isFalse);
  });

  test('maps offline to a typed refusal and changes nothing', () async {
    final scope = container(mode: MockTenantLifecycleMode.offline);
    final tenant = scope.read(platformTenantStoreProvider).byId('saas_hilal')!;
    final outcome = await scope
        .read(tenantLifecycleActionControllerProvider.notifier)
        .suspend(SuspendTenantCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.tenantVersion,
          idempotencyKey: 'controller-offline',
          reason: 'سبب موثق',
        ));
    expect(outcome, isA<TenantLifecycleActionOffline>());
    expect(scope.read(platformTenantStoreProvider).byId(tenant.id)!.lifecycle,
        same(tenant.lifecycle));
  });

  test('maps stale version and refreshes without overwriting', () async {
    final scope = container();
    final tenant = scope.read(platformTenantStoreProvider).byId('saas_hilal')!;
    final repository = scope.read(tenantLifecycleRepositoryProvider);
    await repository.suspend(SuspendTenantCommand(
      tenantId: tenant.id,
      expectedVersion: tenant.tenantVersion,
      idempotencyKey: 'fresh-operator',
      reason: 'سبب موثق',
    ));
    final outcome = await scope
        .read(tenantLifecycleActionControllerProvider.notifier)
        .beginDeletion(BeginTenantDeletionCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.tenantVersion,
          idempotencyKey: 'stale-operator',
          reason: 'طلب قديم',
        ));
    expect(outcome, isA<TenantLifecycleActionStale>());
    expect(
      scope.read(platformTenantStoreProvider).byId(tenant.id)!.tenantVersion,
      tenant.tenantVersion + 1,
    );
  });
}
