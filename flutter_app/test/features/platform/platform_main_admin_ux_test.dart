import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_platform_main_admin_repository.dart';
import 'package:mtm/features/platform/data/platform_main_admin_fixtures.dart';
import 'package:mtm/features/platform/data/platform_main_admin_providers.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/domain/platform_main_admin_models.dart';
import 'package:mtm/features/platform/domain/platform_main_admin_repository.dart';
import 'package:mtm/features/platform/domain/saas_tenant_models.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';
import 'package:mtm/features/platform/presentation/platform_main_admin_page.dart';
import 'package:mtm/features/platform/presentation/platform_main_admin_replace_page.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_routes.dart';
import 'package:mtm/features/shell/main_shell.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

void main() {
  final now = DateTime.utc(2026, 9, 11, 9);

  List<Override> overrides({
    MockMainAdminMode mode = MockMainAdminMode.loaded,
    Duration latency = Duration.zero,
    DateTime? at,
  }) =>
      [
        clockProvider.overrideWithValue(() => at ?? now),
        mainAdminMockConfigProvider.overrideWithValue(
          MainAdminMockConfig(mode: mode, latency: latency),
        ),
      ];

  Future<ProviderContainer> open(
    WidgetTester tester,
    String tenantId, {
    MockMainAdminMode mode = MockMainAdminMode.loaded,
    double width = 390,
    double height = 1800,
    double textScale = 1,
    TenantRepositoryWatch? watch,
    List<Override> extra = const [],
    DateTime? at,
  }) async {
    final container = platformContainer(
      superAdmin,
      watch: watch,
      overrides: [
        ...overrides(mode: mode, at: at),
        ...extra,
      ],
    );
    final router = await bootPlatform(
      tester,
      container,
      width: width,
      height: height,
      textScale: textScale,
    );
    router.go(SaasTenantRoutes.mainAdmin(tenantId));
    await settlePlatform(tester);
    return container;
  }

  group('seat states', () {
    testWidgets('active holder is first, LTR, and offers suspend/replace only',
        (tester) async {
      await open(tester, 'saas_hilal');

      expect(find.byType(PlatformMainAdminPage), findsOneWidget);
      expect(find.text(S.mainAdminStatusActive), findsOneWidget);
      final email = find.text('salma@hilal-medical.org');
      expect(email, findsOneWidget);
      expect(Directionality.of(tester.element(email)), TextDirection.ltr);
      expect(
          find.byKey(const Key('main-admin-action-suspend')), findsOneWidget);
      expect(
          find.byKey(const Key('main-admin-action-replace')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('revoke'), findsNothing);
      expect(find.byType(MainShell), findsNothing);
    });

    testWidgets('pending setup shows invitation timing and allowed actions',
        (tester) async {
      await open(tester, MainAdminFixtures.pendingSetupTenantId);

      expect(find.text(S.mainAdminStatusPending), findsOneWidget);
      expect(find.textContaining(S.mainAdminInvitationSent), findsOneWidget);
      expect(find.byKey(const Key('main-admin-action-resend_setup')),
          findsOneWidget);
      expect(
          find.byKey(const Key('main-admin-action-replace')), findsOneWidget);
      expect(find.byKey(const Key('main-admin-action-suspend')), findsNothing);
    });

    testWidgets('invitation expires exactly into the explicit expired state',
        (tester) async {
      final store = PlatformTenantStore(clock: () => now);
      final tenant = store.byId(MainAdminFixtures.pendingSetupTenantId)!;
      final snapshot = MainAdminAccountSnapshot(
        tenant: MainAdminTenantReference(
          tenantId: tenant.id,
          displayName: tenant.displayName,
          lifecycleStatus: tenant.tenantStatus,
          lifecycleVersion: tenant.tenantVersion,
        ),
        revision: 1,
        current: MainAdminAccount(
          accountId: 'ma_expiry_boundary',
          displayName: tenant.mainAdmin.name,
          loginEmail: tenant.mainAdmin.email,
          status: MainAdminAccountStatus.pendingSetup,
          createdAt: now.subtract(const Duration(days: 8)),
          setup: MainAdminSetupState(
            status: MainAdminSetupStatus.outstanding,
            lastSentAt: now.subtract(const Duration(days: 7)),
            expiresAt: now,
          ),
        ),
        readAt: now,
      );
      await open(
        tester,
        MainAdminFixtures.pendingSetupTenantId,
        extra: [
          platformTenantStoreProvider.overrideWithValue(store),
          platformMainAdminRepositoryProvider.overrideWithValue(
            _ReadOnlyMainAdminRepository(Success(snapshot)),
          ),
        ],
      );

      expect(find.byKey(const Key('main-admin-invitation-expired')),
          findsOneWidget);
      expect(find.byKey(const Key('main-admin-action-resend_setup')),
          findsOneWidget);
    });

    testWidgets('suspended account is distinct from tenant lifecycle',
        (tester) async {
      await open(tester, MainAdminFixtures.suspendedAccountTenantId);

      expect(find.text(S.mainAdminStatusSuspended), findsOneWidget);
      expect(find.text(MainAdminFixtures.suspensionReason), findsOneWidget);
      expect(find.byKey(const Key('main-admin-action-reactivate')),
          findsOneWidget);
      expect(
          find.byKey(const Key('main-admin-action-replace')), findsOneWidget);
      expect(find.byKey(const Key('main-admin-tenant-boundary')), findsNothing);
    });

    testWidgets('pending replacement keeps holder and designate distinct',
        (tester) async {
      await open(tester, MainAdminFixtures.replacementTenantId);

      expect(find.byKey(const Key('main-admin-replacement-pending')),
          findsOneWidget);
      expect(find.text(MainAdminFixtures.designateName), findsWidgets);
      expect(find.text(S.mainAdminDesignateNotAuthorized), findsOneWidget);
      expect(
          find.byKey(const Key('main-admin-action-resend_replacement_setup')),
          findsOneWidget);
      expect(find.byKey(const Key('main-admin-action-cancel_replacement')),
          findsOneWidget);
      expect(find.byKey(const Key('main-admin-action-replace')), findsNothing);
    });

    testWidgets('blocked tenant explains restrictions and keeps suspend only',
        (tester) async {
      await open(tester, MainAdminFixtures.suspendedTenantId);

      expect(
          find.byKey(const Key('main-admin-tenant-boundary')), findsOneWidget);
      expect(find.text(S.mainAdminTenantBlockedSuspended), findsOneWidget);
      expect(
          find.byKey(const Key('main-admin-action-suspend')), findsOneWidget);
      expect(find.byKey(const Key('main-admin-action-replace')), findsNothing);
      expect(
          find.byKey(const Key('main-admin-action-reactivate')), findsNothing);
    });

    testWidgets('deletion-pending tenant refuses access-opening actions',
        (tester) async {
      final store = PlatformTenantStore(clock: () => now);
      final tenant = store.byId('saas_hilal')!;
      final pending = TenantLifecyclePolicy.transition(
        current: tenant.lifecycle,
        action: TenantLifecycleAction.beginDeletion,
        reason: 'سبب إداري',
        now: now,
      ) as TenantLifecycleTransitionAllowed;
      store.updateLifecycle(
        tenant.id,
        pending.next,
        eventType: SaasTenantEventType.deletionRequested,
      );
      await open(
        tester,
        tenant.id,
        extra: [platformTenantStoreProvider.overrideWithValue(store)],
      );

      expect(find.text(S.mainAdminTenantBlockedDeletion), findsOneWidget);
      expect(
          find.byKey(const Key('main-admin-action-suspend')), findsOneWidget);
      expect(find.byKey(const Key('main-admin-action-replace')), findsNothing);
      expect(find.byKey(const Key('main-admin-action-resend_setup')),
          findsNothing);
    });
  });

  group('tenant detail summary', () {
    testWidgets('summarizes representative states and opens the seat route',
        (tester) async {
      final watch = TenantRepositoryWatch();
      final container = platformContainer(
        superAdmin,
        watch: watch,
        overrides: overrides(),
      );
      final router = await bootPlatform(tester, container, height: 2200);

      for (final entry in <String, String>{
        'saas_hilal': S.mainAdminSummaryActive,
        MainAdminFixtures.pendingSetupTenantId: S.mainAdminSummaryPending,
        MainAdminFixtures.suspendedAccountTenantId: S.mainAdminSummarySuspended,
        MainAdminFixtures.replacementTenantId: S.mainAdminSummaryReplacement,
      }.entries) {
        router.go(SaasTenantRoutes.detail(entry.key));
        await settlePlatform(tester);
        expect(find.text(entry.value), findsOneWidget, reason: entry.key);
      }

      router.go(SaasTenantRoutes.detail('saas_hilal'));
      await settlePlatform(tester);
      final action = find.byKey(const Key('open-tenant-main-admin'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await settlePlatform(tester);
      expect(find.byType(PlatformMainAdminPage), findsOneWidget);
      expect(watch.built, isEmpty);
    });

    testWidgets('unavailable summary exposes no security action',
        (tester) async {
      final container = platformContainer(
        superAdmin,
        overrides: overrides(mode: MockMainAdminMode.failure),
      );
      final router = await bootPlatform(tester, container, height: 1800);
      router.go(SaasTenantRoutes.detail('saas_hilal'));
      await settlePlatform(tester);

      expect(find.text(S.mainAdminSummaryUnavailable), findsWidgets);
      expect(find.byKey(const Key('main-admin-action-suspend')), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('read states and separation', () {
    for (final entry in <MockMainAdminMode, String>{
      MockMainAdminMode.stale: 'main-admin-stale',
      MockMainAdminMode.unsupportedState: 'main-admin-unsupported',
      MockMainAdminMode.offline: 'main-admin-offline-empty',
      MockMainAdminMode.failure: 'main-admin-failure',
      MockMainAdminMode.notPermitted: 'main-admin-not-permitted',
    }.entries) {
      testWidgets('${entry.key.name} has its safe state and no mutation',
          (tester) async {
        await open(tester, 'saas_hilal', mode: entry.key);
        expect(find.byKey(Key(entry.value)), findsOneWidget);
        expect(
            find.byKey(const Key('main-admin-action-suspend')), findsNothing);
        expect(
            find.byKey(const Key('main-admin-action-replace')), findsNothing);
      });
    }

    testWidgets('offline cached seat remains visible and read-only',
        (tester) async {
      final store = PlatformTenantStore(clock: () => now);
      final tenant = store.byId('saas_hilal')!;
      final state = MainAdminFixtures.derive(tenant, now: now);
      final snapshot = MainAdminAccountSnapshot(
        tenant: MainAdminTenantReference(
          tenantId: tenant.id,
          displayName: tenant.displayName,
          lifecycleStatus: tenant.tenantStatus,
          lifecycleVersion: tenant.tenantVersion,
        ),
        revision: state.revision,
        current: state.current,
        replacement: state.replacement,
        readAt: now,
      );
      await open(
        tester,
        tenant.id,
        extra: [
          platformTenantStoreProvider.overrideWithValue(store),
          platformMainAdminRepositoryProvider.overrideWithValue(
            _ReadOnlyMainAdminRepository(Offline(cached: snapshot)),
          ),
        ],
      );

      expect(
          find.byKey(const Key('main-admin-offline-cached')), findsOneWidget);
      expect(find.text('salma@hilal-medical.org'), findsOneWidget);
      expect(find.byKey(const Key('main-admin-action-suspend')), findsNothing);
    });

    testWidgets('320dp RTL keeps identity/status/actions without overflow',
        (tester) async {
      await open(
        tester,
        'saas_hilal',
        width: 320,
        height: 1800,
        textScale: 1.6,
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('main-admin-current-email')), findsOneWidget);
      expect(
          find.byKey(const Key('main-admin-account-status')), findsOneWidget);
      expect(find.byKey(const Key('main-admin-actions')), findsOneWidget);
      expect(
          Directionality.of(
              tester.element(find.text('salma@hilal-medical.org'))),
          TextDirection.ltr);
    });

    testWidgets('management page constructs no tenant operational repository',
        (tester) async {
      final watch = TenantRepositoryWatch();
      await open(tester, 'saas_hilal', watch: watch);
      expect(watch.built, isEmpty);
    });
  });

  group('commands and confirmations', () {
    testWidgets('resend confirms once and reports success', (tester) async {
      await open(tester, MainAdminFixtures.pendingSetupTenantId);
      await tester.tap(find.byKey(const Key('main-admin-action-resend_setup')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.byKey(const Key('platform-confirmation-confirm')));
      await settlePlatform(tester);

      expect(find.text(S.mainAdminSuccessResent), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('suspend requires normalized reason and leaves tenant active',
        (tester) async {
      final container = await open(tester, 'saas_hilal');
      await tester.tap(find.byKey(const Key('main-admin-action-suspend')));
      await tester.pumpAndSettle();

      final confirm = find.byKey(const Key('main-admin-suspend-confirm'));
      expect(
        tester
            .widget<TextField>(
                find.byKey(const Key('main-admin-suspend-reason')))
            .maxLength,
        280,
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('main-admin-suspend-reason')),
        '  اشتباه   إداري  ',
      );
      await tester.pump();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
      await tester.tap(confirm);
      await settlePlatform(tester);

      expect(find.text(S.mainAdminStatusSuspended), findsOneWidget);
      expect(
          container
              .read(platformTenantStoreProvider)
              .byId('saas_hilal')!
              .tenantStatus,
          SaasTenantStatus.active);
    });

    testWidgets('reactivate confirms and restores account only',
        (tester) async {
      await open(tester, MainAdminFixtures.suspendedAccountTenantId);
      await tester.tap(find.byKey(const Key('main-admin-action-reactivate')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('platform-confirmation-confirm')));
      await settlePlatform(tester);

      expect(find.text(S.mainAdminStatusActive), findsOneWidget);
    });

    testWidgets('cancel removes designate and preserves current holder',
        (tester) async {
      await open(tester, MainAdminFixtures.replacementTenantId);
      final holder = find.text('badr@najd-response.sa');
      expect(holder, findsOneWidget);
      await tester
          .tap(find.byKey(const Key('main-admin-action-cancel_replacement')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('platform-confirmation-confirm')));
      await settlePlatform(tester);

      expect(holder, findsOneWidget);
      expect(find.byKey(const Key('main-admin-replacement-pending')),
          findsNothing);
    });

    testWidgets('recent auth explains sign-out and never retries',
        (tester) async {
      await open(
        tester,
        MainAdminFixtures.pendingSetupTenantId,
        mode: MockMainAdminMode.recentAuthRequired,
      );
      await tester.tap(find.byKey(const Key('main-admin-action-resend_setup')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('platform-confirmation-confirm')));
      await settlePlatform(tester);

      expect(find.byKey(const Key('main-admin-recent-auth')), findsOneWidget);
      expect(find.text(S.mainAdminRecentAuthBody), findsOneWidget);
    });
  });

  group('replace page', () {
    testWidgets('validates fields and rejects the current login identity',
        (tester) async {
      await open(tester, 'saas_hilal');
      final router =
          GoRouter.of(tester.element(find.byType(PlatformMainAdminPage)));
      router.go(SaasTenantRoutes.mainAdminReplace('saas_hilal'));
      await settlePlatform(tester);

      expect(find.byType(PlatformMainAdminReplacePage), findsOneWidget);
      await tester.tap(find.byKey(const Key('main-admin-replace-submit')));
      await tester.pump();
      expect(find.text(S.mainAdminNameRequired), findsOneWidget);
      expect(find.text(S.mainAdminEmailRequired), findsOneWidget);
      expect(find.text(S.mainAdminReasonRequired), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('main-admin-replace-name')), 'مدير جديد');
      await tester.enterText(find.byKey(const Key('main-admin-replace-email')),
          'salma@hilal-medical.org');
      await tester.enterText(find.byKey(const Key('main-admin-replace-reason')),
          'طلبت الجهة الاستبدال');
      await tester.tap(find.byKey(const Key('main-admin-replace-submit')));
      await tester.pump();
      expect(find.text(S.mainAdminEmailSame), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });

    for (final entry in <String, MainAdminMutationEffect>{
      MainAdminFixtures.pendingSetupTenantId: MainAdminMutationEffect.replaced,
      'saas_hilal': MainAdminMutationEffect.replacementStarted,
      MainAdminFixtures.suspendedAccountTenantId:
          MainAdminMutationEffect.replacementStarted,
    }.entries) {
      testWidgets(
          '${entry.key} replacement uses one confirmation and backend result',
          (tester) async {
        await open(tester, entry.key);
        final router =
            GoRouter.of(tester.element(find.byType(PlatformMainAdminPage)));
        router.go(SaasTenantRoutes.mainAdminReplace(entry.key));
        await settlePlatform(tester);

        await tester.enterText(
            find.byKey(const Key('main-admin-replace-name')), 'مدير جديد');
        await tester.enterText(
            find.byKey(const Key('main-admin-replace-email')),
            'new.${entry.key}@example.org');
        await tester.enterText(
            find.byKey(const Key('main-admin-replace-reason')),
            'طلبت الجهة استبدال المدير الرئيسي');
        await tester.tap(find.byKey(const Key('main-admin-replace-submit')));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        final identity =
            find.byKey(const Key('platform-confirmation-identity'));
        expect(Directionality.of(tester.element(identity)), TextDirection.ltr);
        await tester
            .tap(find.byKey(const Key('platform-confirmation-confirm')));
        await settlePlatform(tester);

        expect(find.byType(PlatformMainAdminReplacePage), findsNothing);
        expect(find.byType(PlatformMainAdminPage), findsOneWidget);
        if (entry.value == MainAdminMutationEffect.replacementStarted) {
          expect(find.byKey(const Key('main-admin-replacement-pending')),
              findsOneWidget);
        } else {
          expect(find.text('new.${entry.key}@example.org'), findsOneWidget);
        }
      });
    }
  });

  testWidgets('deleted tenant redirects to its tombstone without seat data',
      (tester) async {
    final container = platformContainer(
      superAdmin,
      overrides: overrides(),
    );
    final store = container.read(platformTenantStoreProvider);
    final tenant = store.byId('saas_hilal')!;
    final pending = TenantLifecyclePolicy.transition(
      current: tenant.lifecycle,
      action: TenantLifecycleAction.beginDeletion,
      reason: 'سبب إداري',
      now: now.subtract(const Duration(days: 31)),
      deletionGrace: const Duration(days: 30),
    ) as TenantLifecycleTransitionAllowed;
    final updated = store.updateLifecycle(
      tenant.id,
      pending.next,
      eventType: SaasTenantEventType.deletionRequested,
    );
    final deleted = TenantLifecyclePolicy.transition(
      current: updated.lifecycle,
      action: TenantLifecycleAction.finalizeDeletion,
      now: now,
    ) as TenantLifecycleTransitionAllowed;
    store.finalizeTenant(tenant.id, deleted.next);

    final router = await bootPlatform(tester, container, height: 1200);
    router.go(SaasTenantRoutes.mainAdmin(tenant.id));
    await settlePlatform(tester);

    expect(find.byKey(const Key('platform-tenant-tombstone')), findsOneWidget);
    expect(find.byKey(const Key('main-admin-seat-card')), findsNothing);
  });
}

class _ReadOnlyMainAdminRepository implements PlatformMainAdminRepository {
  const _ReadOnlyMainAdminRepository(this.read);

  final Result<MainAdminAccountSnapshot> read;

  @override
  Future<Result<MainAdminAccountSnapshot>> load(String tenantId) async => read;

  @override
  Future<Result<MainAdminMutationResult>> cancelReplacement(
          CancelMainAdminReplacementCommand command) =>
      throw UnsupportedError('read only');

  @override
  Future<Result<MainAdminMutationResult>> reactivate(
          ReactivateMainAdminCommand command) =>
      throw UnsupportedError('read only');

  @override
  Future<Result<MainAdminMutationResult>> replace(
          ReplaceMainAdminCommand command) =>
      throw UnsupportedError('read only');

  @override
  Future<Result<MainAdminMutationResult>> resendSetup(
          ResendMainAdminSetupCommand command) =>
      throw UnsupportedError('read only');

  @override
  Future<Result<MainAdminMutationResult>> suspend(
          SuspendMainAdminCommand command) =>
      throw UnsupportedError('read only');
}
