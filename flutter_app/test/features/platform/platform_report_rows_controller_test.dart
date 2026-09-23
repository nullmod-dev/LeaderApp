import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/platform/data/platform_report_rows_controller.dart';
import 'package:mtm/features/platform/domain/platform_report_datasets.dart';
import 'package:mtm/features/platform/domain/platform_report_models.dart';
import 'package:mtm/features/platform/domain/saas_subscription_models.dart';

/// Point 13B — the report-agnostic rows controller built on top of Point
/// 13A's pure `PlatformReportRowsState`. Exercised here against the
/// subscriptions report's real types (no mock repository, no widget tree):
/// stable initial load, append, no duplicates, next-page failure keeps rows,
/// cursor-expiry recovery, and that a stale in-flight page never lands after
/// a newer first page replaced it.
void main() {
  SubscriptionReportRow row(String id) => SubscriptionReportRow(
        tenant: PlatformReportTenantRef(id: id, displayName: id),
        lifecycle: const PlatformReportValue.supported(SaasTenantStatus.active),
        status: const PlatformReportValue.supported(SubscriptionStatus.active),
        plan: null,
      );

  SubscriptionReport report({
    required String snapshotId,
    required List<SubscriptionReportRow> items,
    String? nextCursor,
  }) =>
      SubscriptionReport(
        meta: PlatformReportMeta(
          type: PlatformReportType.subscriptions,
          generatedAt: DateTime.utc(2026, 1, 1),
          snapshotId: snapshotId,
        ),
        query: SubscriptionReportQuery(),
        summary: SubscriptionReportSummary(
          tenantCount: 0,
          byStatus: PlatformReportBreakdown(keys: SubscriptionStatus.values),
          byLifecycle:
              PlatformReportBreakdown(keys: kReportableLifecycleStatuses),
          byPlan: const [],
        ),
        rows: PlatformReportPage(items: items, nextCursor: nextCursor),
      );

  PlatformReportRowsController<SubscriptionReportQuery, SubscriptionReport,
      SubscriptionReportRow> controllerWith(
    Future<Result<SubscriptionReport>> Function(SubscriptionReportQuery) load,
  ) =>
      PlatformReportRowsController(
        loadPage: load,
        pageOf: (r) => r.rows,
        snapshotIdOf: (r) => r.meta.snapshotId,
        withCursor: (q, c) => q.withCursor(c),
        keyOf: (r) => r.tenant.id,
      );

  test('syncFirstPage replaces rows and needsSync tracks the snapshot', () {
    final controller = controllerWith((_) async => throw StateError('unused'));
    expect(controller.state, isNull);
    expect(controller.needsSync('s1'), isTrue);

    final page1 = report(
      snapshotId: 's1',
      items: [row('a'), row('b')],
      nextCursor: 'c1',
    );
    controller.syncFirstPage(SubscriptionReportQuery(), page1.meta, page1.rows);

    expect(controller.state!.items.map((r) => r.tenant.id), ['a', 'b']);
    expect(controller.state!.canLoadMore, isTrue);
    expect(controller.needsSync('s1'), isFalse);
    expect(controller.needsSync('s2'), isTrue);
  });

  test('loadMore appends the next page in order with no duplicates', () async {
    var requestedCursor = '';
    final controller = controllerWith((q) async {
      requestedCursor = q.cursor!;
      return Success(report(snapshotId: 's1', items: [row('b'), row('c')]));
    });
    final page1 = report(
      snapshotId: 's1',
      items: [row('a')],
      nextCursor: 'c1',
    );
    controller.syncFirstPage(SubscriptionReportQuery(), page1.meta, page1.rows);

    await controller.loadMore();

    expect(requestedCursor, 'c1');
    expect(controller.state!.items.map((r) => r.tenant.id), ['a', 'b', 'c']);
    expect(controller.state!.canLoadMore, isFalse);
    expect(controller.paging, isFalse);
  });

  test('a next-page failure keeps every loaded row and flags pageFailed',
      () async {
    var attempts = 0;
    final controller = controllerWith((_) async {
      attempts++;
      return const Failure('تعذّر تحميل التقرير.', code: 'server');
    });
    final page1 = report(
      snapshotId: 's1',
      items: [row('a')],
      nextCursor: 'c1',
    );
    controller.syncFirstPage(SubscriptionReportQuery(), page1.meta, page1.rows);

    await controller.loadMore();

    expect(controller.state!.items.map((r) => r.tenant.id), ['a']);
    expect(controller.state!.pageFailed, isTrue);
    expect(controller.state!.canLoadMore, isTrue, reason: 'retry is allowed');
    expect(attempts, 1);

    // Retrying re-attempts the same cursor rather than looping silently.
    await controller.loadMore();
    expect(attempts, 2);
  });

  test('a cursor-expired failure requires a first-page reload, never loops',
      () async {
    final controller = controllerWith((_) async => const Failure(
          'تغيّرت بيانات التقرير.',
          code: 'report_cursor_expired',
        ));
    final page1 = report(
      snapshotId: 's1',
      items: [row('a')],
      nextCursor: 'c1',
    );
    controller.syncFirstPage(SubscriptionReportQuery(), page1.meta, page1.rows);

    await controller.loadMore();

    expect(controller.state!.items.map((r) => r.tenant.id), ['a']);
    expect(controller.state!.mustReload, isTrue);
    expect(controller.state!.canLoadMore, isFalse);
  });

  test('an offline next-page refuses paging without losing rows', () async {
    final controller = controllerWith((_) async => const Offline());
    final page1 = report(
      snapshotId: 's1',
      items: [row('a')],
      nextCursor: 'c1',
    );
    controller.syncFirstPage(SubscriptionReportQuery(), page1.meta, page1.rows);

    await controller.loadMore();

    expect(controller.offlinePaging, isTrue);
    expect(controller.state!.items.map((r) => r.tenant.id), ['a']);
    expect(controller.paging, isFalse);
  });

  test(
      'a first page that lands mid-flight makes the stale next page a '
      'no-op — rows from two snapshots are never mixed', () async {
    final completer = Completer<Result<SubscriptionReport>>();
    final controller = controllerWith((_) => completer.future);

    final page1 = report(
      snapshotId: 's1',
      items: [row('a')],
      nextCursor: 'c1',
    );
    controller.syncFirstPage(SubscriptionReportQuery(), page1.meta, page1.rows);

    final pending = controller.loadMore();
    expect(controller.paging, isTrue);

    // A new query's first page (e.g. the user changed a filter) replaces the
    // state while the stale request above is still in flight.
    final page2 = report(snapshotId: 's2', items: [row('x')]);
    controller.syncFirstPage(
      SubscriptionReportQuery(statuses: const {SubscriptionStatus.trial}),
      page2.meta,
      page2.rows,
    );
    expect(controller.state!.snapshotId, 's2');

    completer.complete(
      Success(report(snapshotId: 's1', items: [row('a'), row('b')])),
    );
    await pending;

    expect(controller.state!.snapshotId, 's2');
    expect(controller.state!.items.map((r) => r.tenant.id), ['x']);
  });

  test('loadMore is a no-op with nothing to load', () async {
    final controller = controllerWith((_) async => throw StateError('unused'));
    await controller.loadMore();
    expect(controller.state, isNull);

    final page1 = report(snapshotId: 's1', items: [row('a')]);
    controller.syncFirstPage(SubscriptionReportQuery(), page1.meta, page1.rows);
    await controller.loadMore();
    expect(controller.state!.items.length, 1);
  });
}
