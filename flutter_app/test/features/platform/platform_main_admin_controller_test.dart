import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/platform/data/mock_platform_main_admin_repository.dart';
import 'package:mtm/features/platform/data/platform_audit_providers.dart';
import 'package:mtm/features/platform/data/platform_main_admin_fixtures.dart';
import 'package:mtm/features/platform/data/platform_main_admin_providers.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/data/tenant_lifecycle_providers.dart';
import 'package:mtm/features/platform/domain/platform_audit_models.dart';
import 'package:mtm/features/platform/domain/platform_main_admin_models.dart';
import 'package:mtm/features/platform/domain/platform_main_admin_repository.dart';

final _signedIn =
    StateProvider<AuthUser?>((ref) => DemoPersona.superAdmin.user);

void main() {
  final now = DateTime.utc(2026, 9, 11, 9);

  ProviderContainer container({
    MockMainAdminMode mode = MockMainAdminMode.loaded,
    Duration latency = Duration.zero,
  }) {
    final result = ProviderContainer(overrides: [
      clockProvider.overrideWithValue(() => now),
      currentUserProvider.overrideWith((ref) async => ref.watch(_signedIn)),
      mainAdminMockConfigProvider.overrideWithValue(
        MainAdminMockConfig(mode: mode, latency: latency),
      ),
    ]);
    addTearDown(result.dispose);
    return result;
  }

  Future<MainAdminManagementView?> view(
    ProviderContainer c,
    String tenantId,
  ) async {
    await c.read(currentUserProvider.future);
    // Held like a mounted page holds it, so the autoDispose read survives
    // the mock's latency.
    final page = c.listen(mainAdminManagementProvider(tenantId), (_, __) {});
    await c.read(mainAdminAccountProvider(tenantId).future);
    return page.read();
  }

  SuspendMainAdminCommand suspend(MainAdminAccountSnapshot s,
          {int? revision}) =>
      SuspendMainAdminCommand(
        tenantId: s.tenant.tenantId,
        expectedRevision: revision ?? s.revision,
        idempotencyKey: mainAdminIdempotencyKey(MainAdminAction.suspend, 'a1'),
        reason: 'اشتباه في مشاركة بيانات الدخول',
      );

  ReplaceMainAdminCommand replace(
    MainAdminAccountSnapshot s, {
    String email = 'new.admin@example.org',
  }) =>
      ReplaceMainAdminCommand(
        tenantId: s.tenant.tenantId,
        expectedRevision: s.revision,
        idempotencyKey: mainAdminIdempotencyKey(MainAdminAction.replace, 'a1'),
        designate: MainAdminDesignateIdentity(
          displayName: 'مدير جديد',
          loginEmail: email,
        ),
        reason: 'طلبت الجهة تغيير المدير الرئيسي',
      );

  group('management view', () {
    test('a confirmed super-admin read offers exactly the policy actions',
        () async {
      final c = container();
      final hilal = (await view(c, 'saas_hilal'))!;
      expect(hilal.freshness, MainAdminFreshness.confirmed);
      expect(hilal.actions, {MainAdminAction.suspend, MainAdminAction.replace});

      final rukn = (await view(c, MainAdminFixtures.suspendedTenantId))!;
      expect(rukn.tenantBlocksAccessPaths, isTrue);
      expect(rukn.actions, {MainAdminAction.suspend});

      final nabd = (await view(c, MainAdminFixtures.pendingSetupTenantId))!;
      expect(nabd.replacementMode, MainAdminReplacementMode.immediate);
    });

    test('stale and unsupported reads are shown with no actions', () async {
      final stale = (await view(
        container(mode: MockMainAdminMode.stale),
        'saas_hilal',
      ))!;
      expect(stale.isReadOnly, isTrue);
      expect(stale.actions, isEmpty);

      final unsupported = (await view(
        container(mode: MockMainAdminMode.unsupportedState),
        'saas_hilal',
      ))!;
      expect(unsupported.isUnsupported, isTrue);
      expect(unsupported.actions, isEmpty);
    });

    test('offline without a cached read has no view; failure has none',
        () async {
      final offline = container(mode: MockMainAdminMode.offline);
      expect(await view(offline, 'saas_hilal'), isNull);
      expect(
        await offline.read(mainAdminAccountProvider('saas_hilal').future),
        isA<Offline<MainAdminAccountSnapshot>>(),
      );
      expect(
        await view(container(mode: MockMainAdminMode.failure), 'saas_hilal'),
        isNull,
      );
    });

    test('a tenant session never reaches seat data', () async {
      final c = container();
      c.read(_signedIn.notifier).state = DemoPersona.mainAdmin.user;
      await c.read(currentUserProvider.future);
      final result =
          await c.read(mainAdminAccountProvider('saas_hilal').future);
      expect(
        result.when(
          success: (_, {stale = false}) => null,
          failure: (_, code) => code,
          offline: (_) => 'offline',
        ),
        'not_permitted',
      );
      expect(c.read(mainAdminManagementProvider('saas_hilal')), isNull);
    });
  });

  group('action controller', () {
    test('single flight: a second submit while one runs is ignored', () async {
      final c = container(latency: const Duration(milliseconds: 20));
      final seat = (await view(c, 'saas_hilal'))!.snapshot;
      final controller = c.read(mainAdminActionControllerProvider.notifier);
      final first = controller.suspend(suspend(seat));
      expect(c.read(mainAdminActionControllerProvider).submitting,
          MainAdminAction.suspend);
      final second = await controller.suspend(suspend(seat));
      expect(second, isA<MainAdminActionIgnored>());
      final outcome = await first;
      expect(outcome, isA<MainAdminActionSucceeded>());
      expect(c.read(mainAdminActionControllerProvider).isSubmitting, isFalse);

      final after = (await view(c, 'saas_hilal'))!;
      expect(after.snapshot.current.status, MainAdminAccountStatus.suspended);
      expect(
          after.actions, {MainAdminAction.reactivate, MainAdminAction.replace});
    });

    test('typed outcomes: stale, tenant unavailable, rejected', () async {
      final c = container();
      final controller = c.read(mainAdminActionControllerProvider.notifier);
      final hilal = (await view(c, 'saas_hilal'))!.snapshot;
      expect(
        await controller.suspend(suspend(hilal, revision: hilal.revision + 9)),
        isA<MainAdminActionStale>(),
      );

      final rukn =
          (await view(c, MainAdminFixtures.suspendedTenantId))!.snapshot;
      final unavailable = await controller.replace(replace(rukn));
      expect(unavailable, isA<MainAdminActionTenantUnavailable>());
      expect((unavailable as MainAdminActionTenantUnavailable).code,
          MainAdminProblemCode.tenantNotEligible);

      final taken = await controller
          .replace(replace(hilal, email: 'badr@najd-response.sa'));
      expect(taken, isA<MainAdminActionRejected>());
      expect((taken as MainAdminActionRejected).code,
          MainAdminProblemCode.identityUnavailable);
    });

    test('offline, recent-auth, not-permitted and failure are never retried',
        () async {
      Future<MainAdminActionOutcome> attempt(MockMainAdminMode mode) async {
        final seat = (await view(container(), 'saas_hilal'))!.snapshot;
        final c = container(mode: mode);
        await c.read(currentUserProvider.future);
        return c
            .read(mainAdminActionControllerProvider.notifier)
            .suspend(suspend(seat));
      }

      expect(await attempt(MockMainAdminMode.offline),
          isA<MainAdminActionOffline>());
      expect(await attempt(MockMainAdminMode.recentAuthRequired),
          isA<MainAdminActionRecentAuthRequired>());
      expect(await attempt(MockMainAdminMode.notPermitted),
          isA<MainAdminActionNotPermitted>());
      expect(await attempt(MockMainAdminMode.failure),
          isA<MainAdminActionFailed>());
    });

    test('a completed replacement refreshes the tenant contact everywhere',
        () async {
      final c = container();
      final nabd =
          (await view(c, MainAdminFixtures.pendingSetupTenantId))!.snapshot;
      final outcome = await c
          .read(mainAdminActionControllerProvider.notifier)
          .replace(replace(nabd));
      expect((outcome as MainAdminActionSucceeded).result.effect,
          MainAdminMutationEffect.replaced);
      final detail = await c.read(
          saasTenantDetailProvider(MainAdminFixtures.pendingSetupTenantId)
              .future);
      expect(
        (detail as Success).data.mainAdmin.email,
        'new.admin@example.org',
      );
    });
  });

  group('boundaries', () {
    test('account actions never touch lifecycle, role, Cap or Audit', () async {
      final c = container();
      final query = PlatformAuditQuery(limit: 100);
      List<String> ids(Result<PlatformAuditPage> page) =>
          (page as Success<PlatformAuditPage>)
              .data
              .items
              .map((event) => event.id)
              .toList();
      final auditBefore =
          await c.read(platformAuditRepositoryProvider).listAuditEvents(query);
      final revisionBefore = c.read(tenantLifecycleRevisionProvider);

      final controller = c.read(mainAdminActionControllerProvider.notifier);
      final hilal = (await view(c, 'saas_hilal'))!.snapshot;
      await controller.suspend(suspend(hilal));
      final suspended = (await view(c, 'saas_hilal'))!.snapshot;
      await controller.reactivate(ReactivateMainAdminCommand(
        tenantId: 'saas_hilal',
        expectedRevision: suspended.revision,
        idempotencyKey: 'r1',
      ));

      final auditAfter =
          await c.read(platformAuditRepositoryProvider).listAuditEvents(query);
      expect(ids(auditAfter), ids(auditBefore));
      expect(c.read(tenantLifecycleRevisionProvider), revisionBefore);
      expect(
        c.read(platformTenantStoreProvider).byId('saas_hilal')!.tenantStatus,
        hilal.tenant.lifecycleStatus,
      );

      final user = (await c.read(currentUserProvider.future))!;
      expect(user.role, AuthRole.superAdmin);
      expect(user.saasTenantId, isNull);
      expect(user.capabilities.global, isEmpty);
      expect(user.capabilities.can(Cap.adminManage), isFalse);
    });
  });
}
