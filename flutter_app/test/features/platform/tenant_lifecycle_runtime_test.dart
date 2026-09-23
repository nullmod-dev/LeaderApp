import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/presentation/status_pages.dart';
import 'package:mtm/features/platform/data/mock_tenant_lifecycle_repository.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/data/tenant_lifecycle_providers.dart';
import 'package:mtm/features/platform/domain/saas_tenant_models.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';
import 'package:mtm/features/shell/main_shell.dart';

import 'platform_harness.dart';

void main() {
  final now = DateTime.utc(2026, 9, 9, 12);

  ProviderContainer containerFor(
    DemoPersona persona, {
    Duration deletionGrace = kProvisionalTenantDeletionGrace,
  }) =>
      platformContainer(
        persona.user,
        overrides: [
          clockProvider.overrideWithValue(() => now),
          tenantLifecycleRepositoryProvider.overrideWith((ref) {
            return MockTenantLifecycleRepository(
              store: ref.watch(platformTenantStoreProvider),
              clock: () => now,
              deletionGrace: deletionGrace,
              latency: Duration.zero,
            );
          }),
        ],
      );

  Future<void> settle(WidgetTester tester, {int cycles = 8}) async {
    for (var i = 0; i < cycles; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('active Main Admin leaves an open module after suspension',
      (tester) async {
    ignoreKnownTenantComplaints();
    final container = containerFor(DemoPersona.mainAdmin);
    final router = await bootPlatform(tester, container);
    expect(locationOf(router), '/home');
    expect(find.byType(MainShell), findsOneWidget);

    final tenant =
        container.read(platformTenantStoreProvider).byId(kDemoSaasTenantId)!;
    final outcome = await container
        .read(tenantLifecycleActionControllerProvider.notifier)
        .suspend(SuspendTenantCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.tenantVersion,
          idempotencyKey: 'runtime-suspend',
          reason: 'اختبار تغيير الحالة أثناء الجلسة',
        ));
    expect(outcome, isA<TenantLifecycleActionSucceeded>());
    await settle(tester);

    expect(locationOf(router), '/tenant-suspended');
    expect(find.byType(TenantSuspendedPage), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);

    router.go('/detachment');
    await settle(tester);
    expect(locationOf(router), '/tenant-suspended',
        reason: 'a direct deep link cannot bypass lifecycle');

    final suspended =
        container.read(platformTenantStoreProvider).byId(kDemoSaasTenantId)!;
    final reactivated = TenantLifecyclePolicy.transition(
      current: suspended.lifecycle,
      action: TenantLifecycleAction.reactivate,
      now: now,
    ) as TenantLifecycleTransitionAllowed;
    container.read(platformTenantStoreProvider).updateLifecycle(
          suspended.id,
          reactivated.next,
          eventType: SaasTenantEventType.tenantReactivated,
        );
    container.read(tenantLifecycleRevisionProvider.notifier).changed();
    await settle(tester);
    expect(locationOf(router), '/home',
        reason: 'the mock runtime also observes later reactivation');
    expect(find.byType(MainShell), findsOneWidget);
    // Returning to Home starts its independent mock aggregate reads. Drain
    // those finite timers so this lifecycle test leaves no unrelated work.
    await settle(tester, cycles: 30);
  });

  testWidgets('deletion pending also ejects the tenant shell', (tester) async {
    ignoreKnownTenantComplaints();
    final container = containerFor(DemoPersona.mainAdmin);
    final router = await bootPlatform(tester, container);
    final tenant =
        container.read(platformTenantStoreProvider).byId(kDemoSaasTenantId)!;

    final outcome = await container
        .read(tenantLifecycleActionControllerProvider.notifier)
        .beginDeletion(BeginTenantDeletionCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.tenantVersion,
          idempotencyKey: 'runtime-delete-pending',
          reason: 'اختبار انتظار الحذف',
        ));
    expect(outcome, isA<TenantLifecycleActionSucceeded>());
    await settle(tester);

    expect(locationOf(router), '/tenant-deletion-pending');
    expect(find.byType(TenantDeletionPendingPage), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
  });

  testWidgets('suspension blocks Simple Admin with no per-user bypass',
      (tester) async {
    ignoreKnownTenantComplaints();
    final container = containerFor(DemoPersona.simpleAdmin);
    final store = container.read(platformTenantStoreProvider);
    final tenant = store.byId(kDemoSaasTenantId)!;
    final next = TenantLifecyclePolicy.transition(
      current: tenant.lifecycle,
      action: TenantLifecycleAction.suspend,
      now: now,
      reason: 'اختبار',
    ) as TenantLifecycleTransitionAllowed;
    store.updateLifecycle(
      tenant.id,
      next.next,
      eventType: SaasTenantEventType.tenantSuspended,
    );

    final router = await bootPlatform(tester, container);
    expect(locationOf(router), '/tenant-suspended');
    expect(find.byType(MainShell), findsNothing);
  });

  testWidgets(
      'finalized tenant relationship resolves to deleted, not not-found',
      (tester) async {
    ignoreKnownTenantComplaints();
    final container = containerFor(
      DemoPersona.mainAdmin,
      deletionGrace: Duration.zero,
    );
    final router = await bootPlatform(tester, container);
    final tenant =
        container.read(platformTenantStoreProvider).byId(kDemoSaasTenantId)!;
    final controller =
        container.read(tenantLifecycleActionControllerProvider.notifier);
    final pending = await controller.beginDeletion(BeginTenantDeletionCommand(
      tenantId: tenant.id,
      expectedVersion: tenant.tenantVersion,
      idempotencyKey: 'runtime-final-begin',
      reason: 'اختبار حذف نهائي',
    ));
    final pendingVersion =
        (pending as TenantLifecycleActionSucceeded).result.lifecycle.version;
    await controller.finalizeDeletion(FinalizeTenantDeletionCommand(
      tenantId: tenant.id,
      expectedVersion: pendingVersion,
      idempotencyKey: 'runtime-finalize',
    ));
    await settle(tester);

    expect(locationOf(router), '/tenant-deleted');
    expect(find.byType(TenantDeletedPage), findsOneWidget);
    expect(find.byType(MainShell), findsNothing);
    expect(container.read(platformTenantStoreProvider).byId(tenant.id), isNull);
    expect(
      container.read(platformTenantStoreProvider).tombstoneById(tenant.id),
      isNotNull,
    );
  });
}
