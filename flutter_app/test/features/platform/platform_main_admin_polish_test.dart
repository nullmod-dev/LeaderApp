import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/platform_main_admin_fixtures.dart';
import 'package:mtm/features/platform/data/platform_main_admin_providers.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/domain/platform_main_admin_models.dart';
import 'package:mtm/features/platform/domain/platform_main_admin_repository.dart';
import 'package:mtm/features/platform/presentation/platform_main_admin_page.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_routes.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

/// Point 14C — the presentation guarantees added by the final polish pass:
/// account vs tenant state, holder vs designate, read-only cached seats,
/// RTL-safe email input, dialog context and the 320dp/1.6× matrix.
void main() {
  final now = DateTime.utc(2026, 9, 11, 9);

  MainAdminAccountSnapshot snapshotFor(
    String tenantId, {
    SaasTenantStatus? tenantStatus,
    bool suspendAccount = false,
  }) {
    final store = PlatformTenantStore(clock: () => now);
    final tenant = store.byId(tenantId)!;
    final state = MainAdminFixtures.derive(tenant, now: now);
    final current = state.current;
    return MainAdminAccountSnapshot(
      tenant: MainAdminTenantReference(
        tenantId: tenant.id,
        displayName: tenant.displayName,
        lifecycleStatus: tenantStatus ?? tenant.tenantStatus,
        lifecycleVersion: tenant.tenantVersion,
      ),
      revision: state.revision,
      current: suspendAccount
          ? MainAdminAccount(
              accountId: current.accountId,
              displayName: current.displayName,
              loginEmail: current.loginEmail,
              status: MainAdminAccountStatus.suspended,
              createdAt: current.createdAt,
              activatedAt: current.activatedAt ?? current.createdAt,
              suspension: MainAdminSuspension(
                suspendedAt: now.subtract(const Duration(days: 2)),
                reason: MainAdminFixtures.suspensionReason,
              ),
            )
          : current,
      replacement: state.replacement,
      readAt: now,
    );
  }

  Future<GoRouter> open(
    WidgetTester tester,
    String location, {
    Result<MainAdminAccountSnapshot>? read,
    double width = 390,
    double height = 1800,
    double textScale = 1,
  }) async {
    final container = platformContainer(
      superAdmin,
      overrides: [
        clockProvider.overrideWithValue(() => now),
        mainAdminMockConfigProvider.overrideWithValue(
          const MainAdminMockConfig(latency: Duration.zero),
        ),
        if (read != null)
          platformMainAdminRepositoryProvider.overrideWithValue(
            _FixedReadRepository(read),
          ),
      ],
    );
    final router = await bootPlatform(
      tester,
      container,
      width: width,
      height: height,
      textScale: textScale,
    );
    router.go(location);
    await settlePlatform(tester);
    return router;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  group('account vs tenant state', () {
    testWidgets('both suspended are labelled separately, not by colour',
        (tester) async {
      await open(
        tester,
        SaasTenantRoutes.mainAdmin(MainAdminFixtures.suspendedTenantId),
        read: Success(
          snapshotFor(MainAdminFixtures.suspendedTenantId,
              suspendAccount: true),
        ),
      );

      final tenantAccess = find.byKey(const Key('main-admin-tenant-access'));
      expect(
        find.descendant(
          of: tenantAccess,
          matching: find.text(S.mainAdminTenantAccessSuspended),
        ),
        findsOneWidget,
      );
      final account = find.byKey(const Key('main-admin-account-status'));
      expect(
        find.descendant(
          of: account,
          matching: find.text(S.mainAdminStatusSuspended),
        ),
        findsOneWidget,
      );
      // The tenant chip lives outside the seat card; the account chip inside.
      final seat = find.byKey(const Key('main-admin-seat-card'));
      expect(find.descendant(of: seat, matching: tenantAccess), findsNothing);
      expect(find.descendant(of: seat, matching: account), findsOneWidget);
      expect(
          find.byKey(const Key('main-admin-tenant-boundary')), findsOneWidget);
    });

    testWidgets('an active tenant is stated beside a suspended account',
        (tester) async {
      await open(
        tester,
        SaasTenantRoutes.mainAdmin(MainAdminFixtures.suspendedAccountTenantId),
      );

      expect(find.text(S.mainAdminTenantAccessActive), findsOneWidget);
      expect(find.text(S.mainAdminStatusSuspended), findsOneWidget);
      expect(find.byKey(const Key('main-admin-tenant-boundary')), findsNothing);
    });

    testWidgets('account status is announced with its explicit label',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await open(tester, SaasTenantRoutes.mainAdmin('saas_hilal'));

      expect(
        find.bySemanticsLabel(RegExp(
          '${S.mainAdminAccountStatus}: ${S.mainAdminStatusActive}',
        )),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('holder vs designate', () {
    testWidgets('current holder and designate carry distinct labels',
        (tester) async {
      await open(
        tester,
        SaasTenantRoutes.mainAdmin(MainAdminFixtures.replacementTenantId),
      );

      expect(find.text(S.mainAdminSeatTitle), findsOneWidget);
      expect(find.text(S.mainAdminDesignateTitle), findsOneWidget);
      expect(find.text(S.mainAdminDesignateNotAuthorized), findsOneWidget);
      // The resend on this page targets the designate and says so.
      expect(find.text(S.mainAdminResendDesignate), findsOneWidget);
      expect(find.text(S.mainAdminResend), findsNothing);
    });

    testWidgets('cancel confirmation never shows two «إلغاء» buttons',
        (tester) async {
      await open(
        tester,
        SaasTenantRoutes.mainAdmin(MainAdminFixtures.replacementTenantId),
      );
      await tapKey(tester, 'main-admin-action-cancel_replacement');

      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.text(S.mainAdminDismiss)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('إلغاء')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.text(S.mainAdminCancelConfirmUnchanged),
        ),
        findsOneWidget,
      );
    });

    testWidgets('designate resend confirmation names the designate address',
        (tester) async {
      await open(
        tester,
        SaasTenantRoutes.mainAdmin(MainAdminFixtures.replacementTenantId),
      );
      await tapKey(tester, 'main-admin-action-resend_replacement_setup');

      final identity = find.byKey(const Key('platform-confirmation-identity'));
      expect(
        tester.widget<SelectableText>(identity).data,
        MainAdminFixtures.designateEmail,
      );
      expect(Directionality.of(tester.element(identity)), TextDirection.ltr);
    });
  });

  group('read-only cached seat', () {
    testWidgets('offline cache says why it is read-only and offers a read',
        (tester) async {
      await open(
        tester,
        SaasTenantRoutes.mainAdmin('saas_hilal'),
        read: Offline(cached: snapshotFor('saas_hilal')),
      );

      expect(find.byKey(const Key('main-admin-read-only')), findsOneWidget);
      expect(find.text(S.mainAdminReadOnlyOffline), findsOneWidget);
      expect(find.text(S.mainAdminNoActions), findsNothing);
      expect(find.byKey(const Key('main-admin-read-only-refresh')),
          findsOneWidget);
      for (final action in MainAdminAction.values) {
        expect(
            find.byKey(Key('main-admin-action-${action.wire}')), findsNothing);
      }
      expect(
        tester
            .getSize(find.byKey(const Key('main-admin-read-only-refresh')))
            .height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('dialogs and forms', () {
    testWidgets('suspend dialog names whose access ends, LTR email',
        (tester) async {
      await open(tester, SaasTenantRoutes.mainAdmin('saas_hilal'));
      await tapKey(tester, 'main-admin-action-suspend');

      final dialog = find.byKey(const Key('main-admin-suspend-dialog'));
      expect(
        find.descendant(of: dialog, matching: find.text('سلمى الحارثي')),
        findsOneWidget,
      );
      final email = find.descendant(
        of: find.byKey(const Key('main-admin-suspend-email')),
        matching: find.byType(SelectableText),
      );
      expect(Directionality.of(tester.element(email)), TextDirection.ltr);
      expect(
        find.descendant(of: dialog, matching: find.text(S.mainAdminDismiss)),
        findsOneWidget,
      );
    });

    testWidgets('replace email input is LTR while its messages stay RTL',
        (tester) async {
      await open(tester, SaasTenantRoutes.mainAdminReplace('saas_hilal'));

      expect(
          find.byKey(const Key('main-admin-replace-current')), findsOneWidget);
      final email = find.byKey(const Key('main-admin-replace-email'));
      expect(tester.widget<TextField>(email).textDirection, TextDirection.ltr);

      await tester.tap(find.byKey(const Key('main-admin-replace-submit')));
      await tester.pump();
      expect(
        Directionality.of(tester.element(find.text(S.mainAdminEmailRequired))),
        TextDirection.rtl,
      );
    });
  });

  group('responsive matrix', () {
    final seats = <String, String>{
      'active': 'saas_hilal',
      'pending setup': MainAdminFixtures.pendingSetupTenantId,
      'suspended account': MainAdminFixtures.suspendedAccountTenantId,
      'pending replacement': MainAdminFixtures.replacementTenantId,
      'suspended tenant': MainAdminFixtures.suspendedTenantId,
    };

    for (final width in [320.0, 390.0, 600.0, 900.0]) {
      for (final entry in seats.entries) {
        testWidgets('${entry.key} fits at ${width.toInt()}dp', (tester) async {
          await open(
            tester,
            SaasTenantRoutes.mainAdmin(entry.value),
            width: width,
            height: 2400,
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(PlatformMainAdminPage), findsOneWidget);
          expect(find.byKey(const Key('main-admin-seat-card')), findsOneWidget);
        });
      }
    }

    for (final entry in seats.entries) {
      testWidgets('${entry.key} fits at 320dp and 1.6× text', (tester) async {
        await open(
          tester,
          SaasTenantRoutes.mainAdmin(entry.value),
          width: 320,
          height: 3600,
          textScale: 1.6,
        );
        expect(tester.takeException(), isNull);
        final actions = find.byKey(const Key('main-admin-actions'));
        expect(actions, findsOneWidget);
        for (final button in tester.widgetList<ButtonStyleButton>(
          find.descendant(
              of: actions, matching: find.bySubtype<ButtonStyleButton>()),
        )) {
          expect(button.enabled, isTrue);
        }
      });
    }

    testWidgets('replace form and suspend dialog fit at 320dp and 1.6× text',
        (tester) async {
      final router = await open(
        tester,
        SaasTenantRoutes.mainAdminReplace('saas_hilal'),
        width: 320,
        height: 1600,
        textScale: 1.6,
      );
      await tapKey(tester, 'main-admin-replace-submit');
      expect(tester.takeException(), isNull);

      router.go(SaasTenantRoutes.mainAdmin('saas_hilal'));
      await settlePlatform(tester);
      await tapKey(tester, 'main-admin-action-suspend');
      await tester.enterText(
        find.byKey(const Key('main-admin-suspend-reason')),
        MainAdminFixtures.suspensionReason,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<FilledButton>(
                find.byKey(const Key('main-admin-suspend-confirm')))
            .onPressed,
        isNotNull,
      );
    });
  });
}

class _FixedReadRepository implements PlatformMainAdminRepository {
  const _FixedReadRepository(this.read);

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
