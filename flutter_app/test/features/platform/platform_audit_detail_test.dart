import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/domain/platform_audit_models.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';
import 'package:mtm/features/platform/presentation/platform_audit_copy.dart';
import 'package:mtm/features/platform/presentation/platform_audit_detail.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_routes.dart';
import 'package:mtm/l10n/strings.dart';

final now = DateTime.utc(2026, 9, 10);

PlatformAuditEvent event({String? tenantId, bool deleted = false}) =>
    PlatformAuditEvent(
      id: 'audit_identifier_that_is_long_enough_to_wrap_at_mobile_width',
      occurredAt: now,
      actor: const PlatformAuditAdministratorActor(
          id: 'admin-1', displayName: 'مسؤول المنصة التجريبي'),
      action: PlatformAuditAction.unknown,
      target: const PlatformAuditTarget(
          type: PlatformAuditTargetResource.unknown, id: ''),
      tenant: tenantId == null
          ? null
          : PlatformAuditTenantReference(
              id: tenantId, displayName: 'المشترك', isDeleted: deleted),
      changes: const [
        PlatformAuditChange(
            field: PlatformAuditChangeField.planAssignment,
            before: PlatformAuditTextValue('sensitive-private-token'),
            after: PlatformAuditRedactedValue()),
      ],
    );

void finalize(PlatformTenantStore store, String id) {
  store.finalizeTenant(
      id,
      SaasTenantLifecycle(
        status: SaasTenantStatus.deleted,
        version: 2,
        deletion: TenantDeletionMetadata(
            requestedAt: now,
            scheduledFor: now,
            previousStatus: TenantDeletionRestoreStatus.active,
            reason: 'حذف تجريبي',
            deletedAt: now),
      ));
}

void main() {
  test('copy safely labels all unknowns and values', () {
    expect(AuditCopy.action(PlatformAuditAction.unknown), 'إجراء غير معروف');
    expect(
        AuditCopy.category(PlatformAuditCategory.unknown), 'تصنيف غير معروف');
    expect(AuditCopy.actor(const PlatformAuditSystemActor()), 'النظام');
    expect(
        AuditCopy.actor(const PlatformAuditUnknownActor()), 'منفّذ غير معروف');
    expect(AuditCopy.resource(PlatformAuditTargetResource.unknown),
        'مورد غير معروف');
    expect(AuditCopy.changeField(PlatformAuditChangeField.unknown),
        'حقل غير معروف');
    expect(
        AuditCopy.value(PlatformAuditChangeField.planAssignment,
            const PlatformAuditTextValue('mtm_standard')),
        '${S.productNameAr} القياسية');
    expect(
        AuditCopy.value(PlatformAuditChangeField.planAssignment,
            const PlatformAuditTextValue('mtm_advanced')),
        '${S.productNameAr} المتقدمة');
    expect(
        AuditCopy.value(PlatformAuditChangeField.lifecycleStatus,
            const PlatformAuditTextValue('private-secret')),
        'قيمة غير معروفة');
    expect(
        AuditCopy.value(PlatformAuditChangeField.featureEnabled,
            const PlatformAuditTextValue('private-secret')),
        'قيمة محجوبة');
    expect(AuditCopy.value(PlatformAuditChangeField.featureEnabled, null),
        'غير محدد');
  });

  testWidgets(
      'detail wraps at 320px with 1.6 text and never reveals arbitrary values',
      (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: MediaQuery(
      data: const MediaQueryData(
          size: Size(320, 720), textScaler: TextScaler.linear(1.6)),
      child: Scaffold(body: PlatformAuditDetail(event: event())),
    ))));
    expect(find.text('مسؤول المنصة التجريبي'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('قيمة محجوبة'), 300);
    expect(find.text('قيمة غير معروفة'), findsOneWidget);
    expect(find.textContaining('sensitive-private-token'), findsNothing);
    expect(find.textContaining('unknown'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final state in [
    'live',
    'tombstone',
    'missing',
    'deleted-live',
    'deleted-missing',
    'stale'
  ]) {
    testWidgets('tenant detail link validates $state against current store',
        (tester) async {
      final store = PlatformTenantStore(clock: () => now);
      final id = state.contains('missing') ? 'absent' : store.tenants.first.id;
      if (state == 'tombstone') finalize(store, id);
      final item = event(tenantId: id, deleted: state.startsWith('deleted'));
      final router = GoRouter(routes: [
        GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
                    body: TextButton(
                  onPressed: () => showPlatformAuditDetail(context, item),
                  child: const Text('افتح'),
                ))),
        GoRoute(
            path: SaasTenantRoutes.detail(id),
            builder: (context, state) =>
                const Scaffold(body: Text('صفحة المشترك'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
          overrides: [platformTenantStoreProvider.overrideWithValue(store)],
          child: MaterialApp.router(routerConfig: router)));
      await tester.tap(find.text('افتح'));
      await tester.pumpAndSettle();
      final label =
          state == 'tombstone' ? 'عرض سجل الفريق المحذوف' : 'فتح تفاصيل الفريق';
      if (state.contains('missing') || state == 'deleted-live') {
        expect(find.text('فتح تفاصيل الفريق'), findsNothing);
        expect(find.text('عرض سجل الفريق المحذوف'), findsNothing);
      } else {
        await tester.scrollUntilVisible(find.text(label), 250);
        // Historical live references may now resolve to the real tombstone.
        if (state == 'stale') finalize(store, id);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.text('صفحة المشترك'), findsOneWidget);
        expect(find.byType(PlatformAuditDetail), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
