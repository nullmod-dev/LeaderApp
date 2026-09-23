import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/features/platform/data/platform_audit_providers.dart';
import 'package:mtm/features/platform/domain/platform_area.dart';
import 'package:mtm/features/platform/presentation/platform_audit_page.dart';
import 'package:mtm/features/platform/presentation/platform_operations_routes.dart';
import 'package:mtm/features/platform/presentation/platform_shell.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

void main() {
  testWidgets('audit route is inside Operations and reads no tenant repository',
      (tester) async {
    final watch = TenantRepositoryWatch();
    final router = await bootPlatform(
      tester,
      platformContainer(superAdmin, watch: watch),
    );
    router.go(PlatformOperationsRoutes.audit);
    await settlePlatform(tester);

    expect(locationOf(router), '/platform/audit');
    expect(
        PlatformArea.forLocation(locationOf(router)), PlatformArea.operations);
    expect(find.byType(PlatformAuditPageWidget), findsOneWidget);
    final shell = tester.widget<PlatformShell>(find.byType(PlatformShell));
    expect(shell.navigationShell.currentIndex, PlatformArea.operations.index);
    expect(watch.built, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final user in [mainAdmin, simpleAdmin, fullTenantAdmin]) {
    testWidgets('${user.id} cannot read audit by navigating to its route',
        (tester) async {
      ignoreKnownTenantComplaints();
      var auditReads = 0;
      final container = platformContainer(user, overrides: [
        platformAuditRepositoryProvider.overrideWith((ref) {
          auditReads++;
          throw StateError('Denied route read audit repository');
        }),
      ]);
      final router = await bootPlatform(tester, container);
      router.go(PlatformOperationsRoutes.audit);
      await settlePlatform(tester);

      expect(locationOf(router), '/home');
      expect(find.byType(PlatformAuditPageWidget), findsNothing);
      expect(find.byType(PlatformShell), findsNothing);
      expect(auditReads, 0);
    });
  }

  testWidgets('Operations audit row opens the audit page and can return',
      (tester) async {
    final router = await bootPlatform(tester, platformContainer(superAdmin));
    router.go(PlatformArea.operations.route);
    await settlePlatform(tester);
    // The operations landing is grouped into five sections now, so the audit
    // row sits below the first viewport on a default-height window.
    final row = find.byKey(const Key('platform-operations-audit'));
    await tester.scrollUntilVisible(row, 200);
    await tester.pumpAndSettle();
    final label = find.text(S.platformOpsAudit).hitTestable();
    expect(label, findsOneWidget);
    await tester.tap(label);
    await settlePlatform(tester);
    expect(find.byType(PlatformAuditPageWidget), findsOneWidget);
    expect(router.canPop(), isTrue);
    router.pop();
    await settlePlatform(tester);
    expect(find.byType(PlatformAuditPageWidget), findsNothing);
    expect(find.byType(PlatformShell), findsOneWidget);
  });
}
