@Tags(['render'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/motion/motion_level.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/theme/theme_choice.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_platform_audit_repository.dart';
import 'package:mtm/features/platform/data/platform_audit_fixtures.dart';
import 'package:mtm/features/platform/data/platform_audit_providers.dart';
import 'package:mtm/features/platform/domain/platform_audit_models.dart';
import 'package:mtm/features/platform/presentation/platform_audit_detail.dart';
import 'package:mtm/features/platform/presentation/platform_audit_page.dart';
import 'package:mtm/features/platform/presentation/platform_operations_routes.dart';

import 'platform_harness.dart';

/// Deliberate visual review harness; all PNGs stay outside the repository.
/// MTM_RENDER_DIR=/tmp/mtm-audit flutter test
/// test/features/platform/platform_audit_render.dart --tags render --update-goldens
void main() {
  final outDir = Platform.environment['MTM_RENDER_DIR'];
  final now = DateTime.utc(2026, 9, 10, 16);
  final fixtures = PlatformAuditFixtures(clock: () => now);

  setUpAll(() async {
    final arabic = FontLoader('IBMPlexSansArabic');
    for (final weight in ['Regular', 'Medium', 'SemiBold']) {
      arabic.addFont(
        File('assets/fonts/IBMPlexSansArabic-$weight.ttf')
            .readAsBytes()
            .then(ByteData.sublistView),
      );
    }
    await arabic.load();
    var cache = File(Platform.resolvedExecutable).parent;
    while (!cache.path.endsWith('/cache') && cache.parent.path != cache.path) {
      cache = cache.parent;
    }
    await (FontLoader('MaterialIcons')
          ..addFont(File('${cache.path}/artifacts/material_fonts/'
                  'MaterialIcons-Regular.otf')
              .readAsBytes()
              .then(ByteData.sublistView)))
        .load();
  });

  Future<void> shot(
    WidgetTester tester, {
    required String name,
    AppThemeChoice theme = AppThemeChoice.darkCyber,
    double width = 390,
    double height = 950,
    double textScale = 1,
    bool reduceMotion = false,
    bool eyeProtect = false,
    MockPlatformAuditMode mode = MockPlatformAuditMode.loaded,
    String? search,
    PlatformAuditEvent? detail,
    bool scrollDetailToChanges = false,
    Future<void> Function(WidgetTester)? interact,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = Size(width * 2, height * 2);
    addTearDown(tester.view.reset);
    final watch = TenantRepositoryWatch();
    final container = platformContainer(superAdmin, watch: watch, overrides: [
      clockProvider.overrideWithValue(() => now),
      platformAuditRepositoryProvider.overrideWithValue(
        MockPlatformAuditRepository(
          fixtures: fixtures,
          mode: mode,
          latency: Duration.zero,
        ),
      ),
    ]);
    final router = container.read(appRouterProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(theme.palette, eyeProtect: eyeProtect),
        darkTheme: AppTheme.dark(theme.palette, eyeProtect: eyeProtect),
        themeMode: theme.defaultMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: MotionScope(
              level:
                  reduceMotion ? MotionLevel.performance : MotionLevel.balanced,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    ));
    await settlePlatform(tester);
    router.go(PlatformOperationsRoutes.audit);
    await settlePlatform(tester);
    expect(find.byType(PlatformAuditPageWidget), findsOneWidget);
    if (search != null) {
      await tester.enterText(
        find.byKey(const Key('audit-search')),
        search,
      );
      await settlePlatform(tester);
      expect(find.text(search), findsWidgets);
    }
    if (interact != null) {
      await interact(tester);
      await settlePlatform(tester);
    }
    if (detail != null) {
      showPlatformAuditDetail(
        tester.element(find.byType(PlatformAuditPageWidget)),
        detail,
      );
      await settlePlatform(tester);
      expect(find.byType(PlatformAuditDetail), findsOneWidget);
      expect(find.text(detail.id), findsWidgets);
      if (scrollDetailToChanges) {
        await tester.scrollUntilVisible(
          find.text('بعد التغيير').last,
          300,
          scrollable: find.descendant(
            of: find.byType(PlatformAuditDetail),
            matching: find.byType(Scrollable),
          ),
        );
        await tester.pump();
      }
    }
    expect(watch.built, isEmpty);
    expect(tester.takeException(), isNull, reason: '$name must fit');
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$outDir/$name.png'),
    );
  }

  testWidgets('audit populated 390 darkCyber', (tester) async {
    await shot(tester, name: 'audit-populated-390-dark-cyber');
  }, skip: outDir == null);

  testWidgets('audit search 600 purpleArena', (tester) async {
    await shot(tester,
        name: 'audit-search-600-purple-arena',
        width: 600,
        theme: AppThemeChoice.purpleArena,
        search: 'الهلال');
  }, skip: outDir == null);

  testWidgets('audit safe changes 390 light', (tester) async {
    await shot(tester,
        name: 'audit-safe-detail-390-light',
        theme: AppThemeChoice.light,
        detail: fixtures.events.first,
        scrollDetailToChanges: true);
  }, skip: outDir == null);

  testWidgets('audit tombstone system actor eye protection', (tester) async {
    await shot(tester,
        name: 'audit-tombstone-390-eye-protect',
        eyeProtect: true,
        detail: fixtures.events.firstWhere((event) => event.id == 'audit_003'));
  }, skip: outDir == null);

  testWidgets('audit unknown restricted and missing values', (tester) async {
    final event = PlatformAuditEvent(
      id: 'audit_unknown_safe',
      occurredAt: now,
      actor: const PlatformAuditUnknownActor(),
      action: PlatformAuditAction.unknown,
      target: const PlatformAuditTarget(
        type: PlatformAuditTargetResource.unknown,
        id: 'unknown-resource',
      ),
      changes: const [
        PlatformAuditChange(
          field: PlatformAuditChangeField.unknown,
          before: PlatformAuditRedactedValue(),
        ),
      ],
    );
    await shot(tester,
        name: 'audit-unknown-redacted-missing-390',
        eyeProtect: true,
        detail: event);
  }, skip: outDir == null);

  testWidgets('audit filtered empty results', (tester) async {
    await shot(tester,
        name: 'audit-empty-filtered-390', search: 'no-matching-audit-event');
  }, skip: outDir == null);

  testWidgets('audit offline cached results', (tester) async {
    await shot(tester,
        name: 'audit-offline-cache-390',
        mode: MockPlatformAuditMode.offlineWithCache);
  }, skip: outDir == null);

  testWidgets('audit stale results', (tester) async {
    await shot(tester,
        name: 'audit-stale-390', mode: MockPlatformAuditMode.stale);
  }, skip: outDir == null);

  testWidgets('audit 320 large text reduced motion', (tester) async {
    await shot(tester,
        name: 'audit-narrow-320-large-text-reduced-motion',
        width: 320,
        textScale: 1.6,
        reduceMotion: true);
  }, skip: outDir == null);

  testWidgets('audit 900 wide', (tester) async {
    await shot(tester, name: 'audit-wide-900', width: 900);
  }, skip: outDir == null);
}
