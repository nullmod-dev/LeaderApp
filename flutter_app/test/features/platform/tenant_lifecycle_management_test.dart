import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/platform/data/mock_tenant_lifecycle_repository.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/data/tenant_lifecycle_providers.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/domain/saas_tenant_models.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_repository.dart';
import 'package:mtm/features/platform/presentation/tenant_lifecycle_management_section.dart';
import 'package:mtm/features/platform/presentation/tenant_lifecycle_copy.dart';

void main() {
  final now = DateTime.utc(2026, 9, 9, 12);

  ProviderContainer container() {
    final scope = ProviderContainer(overrides: [
      clockProvider.overrideWithValue(() => now),
      tenantLifecycleRepositoryProvider.overrideWith((ref) {
        return MockTenantLifecycleRepository(
          store: ref.watch(platformTenantStoreProvider),
          clock: () => now,
          deletionGrace: Duration.zero,
          latency: Duration.zero,
        );
      }),
    ]);
    addTearDown(scope.dispose);
    return scope;
  }

  Future<void> pump(
    WidgetTester tester,
    ProviderContainer scope,
    SaasTenant tenant,
  ) async {
    await tester.pumpWidget(UncontrolledProviderScope(
      container: scope,
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: TenantLifecycleManagementSection(tenant: tenant),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('suspension requires a reason and names every consequence',
      (tester) async {
    final scope = container();
    final tenant = scope.read(platformTenantStoreProvider).byId('saas_hilal')!;
    await pump(tester, scope, tenant);

    await tester.tap(find.byKey(const Key('tenant-lifecycle-suspend')));
    await tester.pump();
    expect(find.byKey(const Key('tenant-lifecycle-reason')), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('tenant-lifecycle-reason-continue')),
          )
          .onPressed,
      isNull,
    );

    await tester.enterText(
      find.byKey(const Key('tenant-lifecycle-reason')),
      'سبب إداري موثق',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('tenant-lifecycle-reason-continue')),
    );
    await tester.pump();

    expect(find.text(tenant.displayName), findsOneWidget);
    expect(find.textContaining('الوصول التشغيلي لكل'), findsOneWidget);
    expect(find.textContaining('الاشتراك والخطة والحدود والميزات'),
        findsOneWidget);
    expect(find.textContaining('إعادة تفعيل'), findsOneWidget);
  });

  testWidgets('final deletion is a two-step exact-name acknowledgement',
      (tester) async {
    final scope = container();
    final store = scope.read(platformTenantStoreProvider);
    final before = store.byId('saas_hilal')!;
    await scope.read(tenantLifecycleRepositoryProvider).beginDeletion(
          BeginTenantDeletionCommand(
            tenantId: before.id,
            expectedVersion: before.tenantVersion,
            idempotencyKey: 'ui-pending',
            reason: 'طلب حذف موثق',
          ),
        );
    final tenant = store.byId(before.id)!;
    await pump(tester, scope, tenant);

    final finalButton =
        find.byKey(const Key('tenant-lifecycle-finalize-delete'));
    expect(tester.widget<OutlinedButton>(finalButton).onPressed, isNotNull);
    await tester.tap(finalButton);
    await tester.pump();

    expect(find.textContaining('قد تصبح الاستعادة مستحيلة'), findsOneWidget);
    expect(find.textContaining('Flutter'), findsOneWidget);
    await tester.tap(find.text('متابعة إلى التأكيد'));
    await tester.pump();

    final submit = find.byKey(const Key('final-delete-submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('final-delete-typed-confirmation')),
      '${tenant.displayName} ',
    );
    await tester.pump();
    expect(find.text('اسم الفريق غير مطابق.'), findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('final-delete-typed-confirmation')),
      tenant.displayName,
    );
    await tester.tap(
      find.byKey(const Key('final-delete-acknowledgement')),
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
  });

  testWidgets('renders only actions legal at the injected instant',
      (tester) async {
    final scope = container();
    final store = scope.read(platformTenantStoreProvider);

    final active = store.byId('saas_hilal')!;
    await pump(tester, scope, active);
    expect(find.byKey(const Key('tenant-lifecycle-suspend')), findsOneWidget);
    expect(
        find.byKey(const Key('tenant-lifecycle-begin-delete')), findsOneWidget);
    expect(find.byKey(const Key('tenant-lifecycle-reactivate')), findsNothing);

    final suspended = store.byId('saas_rukn')!;
    await pump(tester, scope, suspended);
    expect(
        find.byKey(const Key('tenant-lifecycle-reactivate')), findsOneWidget);
    expect(
        find.byKey(const Key('tenant-lifecycle-begin-delete')), findsOneWidget);
    expect(find.text('مراجعة إدارية موثقة'), findsOneWidget);

    final pendingBefore = _beginDeletion(
      store,
      active,
      at: now,
      grace: const Duration(days: 30),
    );
    await pump(tester, scope, pendingBefore);
    expect(find.byKey(const Key('tenant-lifecycle-cancel-delete')),
        findsOneWidget);
    expect(find.byKey(const Key('tenant-lifecycle-finalize-delete')),
        findsNothing);
    expect(find.text('متبقي ٣٠ يوماً'), findsOneWidget);

    final other = store.byId('saas_najd')!;
    final pendingAfter = _beginDeletion(
      store,
      other,
      at: now.subtract(const Duration(days: 31)),
      grace: const Duration(days: 30),
    );
    await pump(tester, scope, pendingAfter);
    expect(
        find.byKey(const Key('tenant-lifecycle-cancel-delete')), findsNothing);
    expect(find.byKey(const Key('tenant-lifecycle-finalize-delete')),
        findsOneWidget);
    expect(find.text('بلغ موعد الحذف النهائي'), findsOneWidget);
  });

  testWidgets('offline refusal keeps the administrative reason for retry',
      (tester) async {
    final scope = ProviderContainer(overrides: [
      clockProvider.overrideWithValue(() => now),
      tenantLifecycleRepositoryProvider.overrideWith((ref) {
        return MockTenantLifecycleRepository(
          store: ref.watch(platformTenantStoreProvider),
          clock: () => now,
          mode: MockTenantLifecycleMode.offline,
          latency: Duration.zero,
        );
      }),
    ]);
    addTearDown(scope.dispose);
    final tenant = scope.read(platformTenantStoreProvider).byId('saas_hilal')!;
    await pump(tester, scope, tenant);

    await tester.tap(find.byKey(const Key('tenant-lifecycle-suspend')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('tenant-lifecycle-reason')),
      'سبب محفوظ للمحاولة',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('tenant-lifecycle-reason-continue')),
    );
    await tester.pump();
    await tester.tap(find.text('إيقاف الوصول').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('احتُفظ بالنص'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tenant-lifecycle-suspend')));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const Key('tenant-lifecycle-reason')),
    );
    expect(field.controller!.text, 'سبب محفوظ للمحاولة');
  });

  test('safe problem copy covers every typed lifecycle failure', () {
    for (final code in TenantLifecycleProblemCode.values) {
      final message = tenantLifecycleProblemMessage(code);
      expect(message, isNotEmpty, reason: code.wire);
      expect(message, isNot(contains(code.wire)), reason: code.wire);
    }
  });
}

SaasTenant _beginDeletion(
  PlatformTenantStore store,
  SaasTenant tenant, {
  required DateTime at,
  required Duration grace,
}) {
  final decision = TenantLifecyclePolicy.transition(
    current: tenant.lifecycle,
    action: TenantLifecycleAction.beginDeletion,
    now: at,
    reason: 'طلب حذف موثق',
    deletionGrace: grace,
  ) as TenantLifecycleTransitionAllowed;
  return store.updateLifecycle(
    tenant.id,
    decision.next,
    eventType: SaasTenantEventType.deletionRequested,
    note: 'طلب حذف موثق',
  );
}
