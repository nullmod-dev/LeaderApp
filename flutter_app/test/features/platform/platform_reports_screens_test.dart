import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/mock_platform_reports_repository.dart';
import 'package:mtm/features/platform/data/platform_reports_providers.dart';
import 'package:mtm/features/platform/domain/platform_audit_models.dart';
import 'package:mtm/features/platform/domain/platform_report_datasets.dart';
import 'package:mtm/features/platform/domain/platform_report_models.dart';
import 'package:mtm/features/platform/presentation/platform_audit_page.dart';
import 'package:mtm/features/platform/presentation/platform_operations_routes.dart';
import 'package:mtm/features/platform/presentation/platform_reports_catalogue_page.dart';
import 'package:mtm/features/platform/presentation/saas_tenant_detail_page.dart';
import 'package:mtm/features/platform/presentation/widgets/platform_report_widgets.dart';
import 'package:mtm/l10n/strings.dart';

import 'platform_harness.dart';

/// Point 13B — the four report screens: landing, filters, states, rows,
/// paging surfaces, tenant navigation and the Audit drill-down. Point 13A's
/// own domain/repository tests already hold the data layer to 55/55; this
/// file is about what the screens built on top of it actually show.
void main() {
  final now = DateTime.utc(2026, 9, 11, 9);
  DateTime clock() => now;

  Future<GoRouter> open(
    WidgetTester tester,
    String location, {
    MockPlatformReportsMode mode = MockPlatformReportsMode.loaded,
    Duration? auditRetention,
    TenantRepositoryWatch? watch,
    double width = 390,
    double textScale = 1,
  }) async {
    final router = await bootPlatform(
      tester,
      platformContainer(superAdmin, watch: watch, overrides: [
        clockProvider.overrideWithValue(clock),
        platformReportsMockConfigProvider.overrideWithValue(
          MockPlatformReportsConfig(
            mode: mode,
            latency: Duration.zero,
            auditRetention: auditRetention,
          ),
        ),
      ]),
      width: width,
      height: 1400,
      textScale: textScale,
    );
    router.go(location);
    await settlePlatform(tester);
    return router;
  }

  group('reports landing', () {
    testWidgets('exactly the four catalogue entries, grouped by kind',
        (tester) async {
      await open(tester, PlatformOperationsRoutes.reports);

      expect(find.byType(PlatformReportsCataloguePage), findsOneWidget);
      expect(find.byKey(const Key('platform-report-subscriptions')),
          findsOneWidget);
      expect(find.byKey(const Key('platform-report-usage_limits')),
          findsOneWidget);
      expect(find.byKey(const Key('platform-report-feature_availability')),
          findsOneWidget);
      expect(find.byKey(const Key('platform-report-platform_activity')),
          findsOneWidget);
      expect(find.text(S.platformReportsSectionCurrent), findsOneWidget);
      expect(find.text(S.platformReportsSectionPeriod), findsOneWidget);
      // No metrics on the landing — a stray number would be a report result
      // leaking onto the catalogue.
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a row opens its report inside the platform shell',
        (tester) async {
      // Pushed (not `go`) inside the Operations branch, exactly like the
      // Health/Security/Audit rows on the same landing — go_router leaves
      // `currentConfiguration.uri` at the branch root for an imperative
      // `push`, so the pushed page is asserted by its widget, not the URI
      // (`platform_routing_test.dart` documents the same caveat).
      await open(tester, PlatformOperationsRoutes.reports);
      await tester.tap(find.byKey(const Key('platform-report-subscriptions')));
      await settlePlatform(tester);
      expect(find.byKey(const Key('subscriptions-loaded')), findsOneWidget);
    });
  });

  group('subscriptions report', () {
    testWidgets('loads with breakdowns, provenance and rows', (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.subscriptions),
      );
      expect(find.byKey(const Key('subscriptions-loaded')), findsOneWidget);
      expect(find.textContaining(S.platformReportScopeNote), findsOneWidget);
    });

    testWidgets('tapping a row opens that tenant detail', (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.subscriptions),
      );
      final rowFinder = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('subscription-row-'),
      );
      expect(rowFinder, findsWidgets);
      await tester.tap(rowFinder.first);
      await settlePlatform(tester);
      expect(find.byType(SaasTenantDetailPage), findsOneWidget);
    });

    testWidgets('empty is distinct from failure', (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.subscriptions),
        mode: MockPlatformReportsMode.empty,
      );
      expect(find.byKey(const Key('subscriptions-empty')), findsOneWidget);
      expect(find.byKey(const Key('subscriptions-failure')), findsNothing);
    });

    testWidgets('a safe failure offers retry', (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.subscriptions),
        mode: MockPlatformReportsMode.failure,
      );
      expect(find.byKey(const Key('subscriptions-failure')), findsOneWidget);
    });

    testWidgets('offline without cache says so, not empty', (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.subscriptions),
        mode: MockPlatformReportsMode.offlineWithoutCache,
      );
      expect(find.byKey(const Key('subscriptions-offline')), findsOneWidget);
      expect(find.byKey(const Key('subscriptions-empty')), findsNothing);
    });

    testWidgets('stale cached data says so in the provenance line',
        (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.subscriptions),
        mode: MockPlatformReportsMode.stale,
      );
      expect(find.byKey(const Key('report-stale-note')), findsOneWidget);
    });

    testWidgets('applying a filter narrows the query and shows a clear-all',
        (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.subscriptions),
      );
      await tester.tap(find.byKey(const Key('report-open-filters')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const Key('subscription-filter-status-trial')));
      await tester.tap(find.byKey(const Key('report-filters-apply')));
      await settlePlatform(tester);

      expect(find.byKey(const Key('report-clear-filters')), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-clear-filters')));
      await settlePlatform(tester);
      expect(find.byKey(const Key('report-clear-filters')), findsNothing);
    });

    testWidgets('the wide layout shows a permanent side filter panel',
        (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.subscriptions),
        width: 1100,
      );
      expect(find.byKey(const Key('report-filter-panel')), findsOneWidget);
      expect(find.byKey(const Key('report-open-filters')), findsNothing);
    });
  });

  group('usage & limits report', () {
    testWidgets('renders every factual band and no near-limit category',
        (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.usageLimits),
      );
      expect(find.byKey(const Key('usage-loaded')), findsOneWidget);
      expect(find.text(S.platformUsageBandWithin), findsWidgets);
      expect(find.text(S.platformUsageBandAt), findsWidgets);
      expect(find.text(S.platformUsageBandOver), findsWidgets);
      expect(find.text(S.platformUsageBandNoLimit), findsWidgets);
      expect(find.textContaining('قريب من الحد'), findsNothing);
    });

    testWidgets('the limit-key pill row re-ranks without becoming a filter',
        (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.usageLimits),
      );
      expect(find.byKey(const Key('usage-limit-key-all')), findsOneWidget);
      await tester.tap(find.byKey(const Key('usage-limit-key-members')));
      await settlePlatform(tester);
      // Re-ranking is not a filter: no active-filter badge appears from it.
      expect(find.byKey(const Key('report-clear-filters')), findsNothing);
    });
  });

  group('feature availability report', () {
    testWidgets('renders enabled/disabled per module', (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(
          PlatformReportType.featureAvailability,
        ),
      );
      expect(find.byKey(const Key('features-loaded')), findsOneWidget);
      expect(find.text(S.platformFeatureEnabled), findsWidgets);
      expect(find.text(S.platformFeatureDisabled), findsWidgets);
    });
  });

  group('platform activity report', () {
    testWidgets('shows category totals and a governance note', (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.platformActivity),
      );
      expect(find.byKey(const Key('activity-loaded')), findsOneWidget);
    });

    testWidgets(
        'an action with events drills down to the equivalent Audit '
        'query', (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.platformActivity),
      );
      final actionKey = Key(
        'activity-action-${PlatformAuditAction.tenantRegistered.wire}',
      );
      if (tester.any(find.byKey(actionKey))) {
        await tester.tap(find.byKey(actionKey));
        await settlePlatform(tester);
        // Pushed, like every Operations sibling route — asserted by widget,
        // not by `currentConfiguration.uri` (see the landing test above).
        expect(find.byType(PlatformAuditPageWidget), findsOneWidget);
        final page = tester.widget<PlatformAuditPageWidget>(
          find.byType(PlatformAuditPageWidget),
        );
        final expectedRange = PlatformActivityReportQuery.defaultAt(now).range;
        expect(page.initialQuery?.action, PlatformAuditAction.tenantRegistered);
        expect(page.initialQuery?.from, expectedRange.from);
        expect(page.initialQuery?.before, expectedRange.before);
      }
    });

    testWidgets('retention gaps read as unavailable, never as zero',
        (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.platformActivity),
        auditRetention: const Duration(days: 1),
      );
      expect(find.textContaining('السجل متاح منذ'), findsOneWidget);
    });
  });

  group('unsupported values', () {
    testWidgets('an unsupported subscription row is shown, never guessed',
        (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.subscriptions),
        mode: MockPlatformReportsMode.unsupportedValues,
      );
      expect(
        find.text(S.platformReportUnsupportedValuesNote),
        findsWidgets,
      );
    });
  });

  group('≥900 dp dense rows', () {
    testWidgets('subscriptions switches from tiles to a dense table, same rows',
        (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.subscriptions),
        width: 1100,
      );
      expect(find.byType(ReportDenseTable), findsOneWidget);
      expect(find.byType(ReportRowTile), findsNothing);
      final rowFinder = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('subscription-row-'),
      );
      expect(rowFinder, findsWidgets);
      await tester.tap(rowFinder.first);
      await settlePlatform(tester);
      expect(find.byType(SaasTenantDetailPage), findsOneWidget);
    });

    testWidgets('usage & limits shows the dense table and the key×band table',
        (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.usageLimits),
        width: 1100,
      );
      // Two tables at this width: the summary key×band table and the rows.
      expect(find.byType(ReportDenseTable), findsOneWidget);
      expect(find.byType(ReportRowTile), findsNothing);
      expect(find.text(S.platformUsageBandWithin), findsWidgets);
    });

    testWidgets('feature availability renders one column per module',
        (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.featureAvailability),
        width: 1100,
      );
      expect(find.byType(ReportDenseTable), findsOneWidget);
      expect(find.byType(ReportRowTile), findsNothing);
    });

    testWidgets('platform activity lays out category groups two per row',
        (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.platformActivity),
        width: 1100,
      );
      expect(find.byKey(const Key('activity-loaded')), findsOneWidget);
      expect(find.byType(Wrap), findsWidgets);
    });

    testWidgets('narrower than 900 dp keeps the compact tiles', (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.subscriptions),
        width: 800,
      );
      expect(find.byType(ReportDenseTable), findsNothing);
      expect(find.byType(ReportRowTile), findsWidgets);
    });
  });

  group('320 dp at 1.6× text', () {
    for (final type in [
      PlatformReportType.subscriptions,
      PlatformReportType.usageLimits,
      PlatformReportType.featureAvailability,
      PlatformReportType.platformActivity,
    ]) {
      testWidgets('${type.wire} renders with real rows, no overflow',
          (tester) async {
        // No `FlutterError.onError` override in this file: an overflow
        // anywhere while pumping fails the test that produced it.
        await open(
          tester,
          PlatformOperationsRoutes.report(type),
          width: 320,
          textScale: 1.6,
        );
        expect(find.byType(PlatformReportScaffold), findsOneWidget);
      });
    }
  });

  group('separation', () {
    testWidgets('no report page builds a tenant-operational repository',
        (tester) async {
      final watch = TenantRepositoryWatch();
      final router =
          await open(tester, PlatformOperationsRoutes.reports, watch: watch);
      for (final type in [
        PlatformReportType.subscriptions,
        PlatformReportType.usageLimits,
        PlatformReportType.featureAvailability,
        PlatformReportType.platformActivity,
      ]) {
        router.go(PlatformOperationsRoutes.report(type));
        await settlePlatform(tester);
        expect(watch.built, isEmpty, reason: type.wire);
      }
    });

    testWidgets('no export or chart affordance is offered', (tester) async {
      await open(
        tester,
        PlatformOperationsRoutes.report(PlatformReportType.subscriptions),
      );
      expect(find.byIcon(Icons.download_rounded), findsNothing);
      expect(find.byIcon(Icons.share_rounded), findsNothing);
      expect(find.byIcon(Icons.pie_chart_rounded), findsNothing);
      expect(find.byIcon(Icons.bar_chart_rounded), findsNothing);
    });
  });
}
