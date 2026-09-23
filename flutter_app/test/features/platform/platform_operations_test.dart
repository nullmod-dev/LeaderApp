import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/features/platform/domain/platform_area.dart';
import 'package:mtm/features/platform/presentation/platform_health_page.dart';
import 'package:mtm/features/platform/presentation/platform_break_glass_page.dart';
import 'package:mtm/features/platform/presentation/platform_operations_page.dart';
import 'package:mtm/features/platform/presentation/platform_operations_routes.dart';
import 'package:mtm/features/platform/presentation/platform_reports_catalogue_page.dart';
import 'package:mtm/features/platform/presentation/platform_security_page.dart';
import 'package:mtm/features/platform/presentation/platform_shell.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

void main() {
  Future<GoRouter> open(
    WidgetTester tester, {
    TenantRepositoryWatch? watch,
    double width = 390,
    double textScale = 1,
  }) async {
    final router = await bootPlatform(
      tester,
      platformContainer(superAdmin, watch: watch),
      width: width,
      height: 1000,
      textScale: textScale,
    );
    router.go(PlatformArea.operations.route);
    await settlePlatform(tester);
    return router;
  }

  testWidgets('landing exposes health, security, audit and emergency access',
      (tester) async {
    await open(tester);

    expect(find.byType(PlatformOperationsPage), findsOneWidget);
    expect(
      find.byKey(const Key('platform-operations-audit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('platform-operations-health')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('platform-operations-security')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('platform-operations-reports')),
      findsOneWidget,
    );
    // Emergency access is the last group on the page — the danger zone below
    // the routine work — so on a 390 × 1000 viewport it is reached by
    // scrolling rather than already laid out. It is still *on the landing*,
    // which is what this test is about.
    final access = find.byKey(const Key('platform-operations-break-glass'));
    await tester.scrollUntilVisible(access, 200);
    await tester.pumpAndSettle();
    expect(access, findsOneWidget);
  });

  testWidgets('all module rows navigate to real pages in the Operations branch',
      (tester) async {
    final router = await open(tester);

    await tester.tap(find.byKey(const Key('platform-operations-health')));
    await settlePlatform(tester);
    expect(find.byType(PlatformHealthPage), findsOneWidget);
    expect(find.byType(PlatformShell), findsOneWidget);
    expect(router.canPop(), isTrue);

    router.go(PlatformArea.operations.route);
    await settlePlatform(tester);
    await tester.tap(find.byKey(const Key('platform-operations-security')));
    await settlePlatform(tester);
    expect(find.byType(PlatformSecurityPage), findsOneWidget);
    expect(find.byType(PlatformShell), findsOneWidget);
    expect(router.canPop(), isTrue);

    router.go(PlatformArea.operations.route);
    await settlePlatform(tester);
    final audit = find.byKey(const Key('platform-operations-audit'));
    await tester.ensureVisible(audit);
    await tester.pumpAndSettle();
    final auditLabel = find.text(S.platformOpsAudit).hitTestable();
    expect(auditLabel, findsOneWidget);
    await tester.tap(auditLabel);
    await settlePlatform(tester);
    expect(find.text(S.platformAuditTitle), findsOneWidget);
    expect(find.byType(PlatformShell), findsOneWidget);
    expect(router.canPop(), isTrue);

    router.go(PlatformArea.operations.route);
    await settlePlatform(tester);
    final access = find.byKey(const Key('platform-operations-break-glass'));
    await tester.ensureVisible(access);
    await tester.tap(access);
    await settlePlatform(tester);
    expect(find.byType(PlatformBreakGlassPage), findsOneWidget);
    expect(find.byType(PlatformShell), findsOneWidget);
    expect(router.canPop(), isTrue);

    router.go(PlatformArea.operations.route);
    await settlePlatform(tester);
    final reports = find.byKey(const Key('platform-operations-reports'));
    await tester.ensureVisible(reports);
    await tester.tap(reports);
    await settlePlatform(tester);
    expect(find.byType(PlatformReportsCataloguePage), findsOneWidget);
    expect(find.byType(PlatformShell), findsOneWidget);
    expect(router.canPop(), isTrue);
  });

  testWidgets('landing fits the narrowest supported layout', (tester) async {
    await open(tester, width: 320, textScale: 1.6);
    expect(find.byType(PlatformOperationsPage), findsOneWidget);
  });

  testWidgets('landing and all modules preserve repository isolation',
      (tester) async {
    final watch = TenantRepositoryWatch();
    final router = await open(tester, watch: watch);
    for (final route in PlatformOperationsRoutes.all) {
      router.go(route);
      await settlePlatform(tester);
      expect(watch.built, isEmpty, reason: route);
    }
  });
}
