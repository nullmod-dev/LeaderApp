import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/platform/data/platform_audit_list_controller.dart';
import 'package:mtm/features/platform/data/platform_audit_providers.dart';
import 'package:mtm/features/platform/domain/platform_audit_models.dart';
import 'package:mtm/features/platform/domain/platform_audit_repository.dart';
import 'package:mtm/features/platform/presentation/platform_audit_copy.dart';
import 'package:mtm/features/platform/presentation/platform_audit_filters.dart';
import 'package:mtm/features/platform/presentation/platform_audit_page.dart';

final _now = DateTime.utc(2026, 9, 10, 12);

PlatformAuditEvent _event(String id, {Duration ago = Duration.zero}) =>
    PlatformAuditEvent(
      id: id,
      occurredAt: _now.subtract(ago),
      actor: const PlatformAuditSystemActor(),
      action: PlatformAuditAction.tenantRegistered,
      target: PlatformAuditTarget(
        type: PlatformAuditTargetResource.tenant,
        id: 'tenant-$id',
      ),
      tenant: PlatformAuditTenantReference(
        id: 'tenant-$id',
        displayName: 'فريق $id',
        isDeleted: false,
      ),
      changes: const [],
    );

class _ScriptedRepository implements PlatformAuditRepository {
  final responses = <FutureOr<Result<PlatformAuditPage>>>[];
  final calls = <PlatformAuditQuery>[];

  @override
  Future<Result<PlatformAuditPage>> listAuditEvents(
    PlatformAuditQuery query,
  ) async {
    calls.add(query);
    if (responses.isEmpty) throw StateError('Missing scripted response');
    return await responses.removeAt(0);
  }
}

void main() {
  group('PlatformAuditListController', () {
    test('appends opaque pages in order without duplicates', () async {
      final repository = _ScriptedRepository()
        ..responses.addAll([
          Success(PlatformAuditPage(
            items: [
              _event('003'),
              _event('002', ago: const Duration(hours: 1))
            ],
            nextCursor: 'opaque-1',
          )),
          Success(PlatformAuditPage(
            items: [
              _event('002'),
              _event('001', ago: const Duration(hours: 2))
            ],
          )),
        ]);
      final controller = PlatformAuditListController(repository);
      addTearDown(controller.dispose);

      await controller.refresh();
      await controller.loadMore();

      expect(controller.items.map((event) => event.id), ['003', '002', '001']);
      expect(repository.calls[1].cursor, 'opaque-1');
      expect(controller.nextCursor, isNull);
    });

    test('query change resets the page and forwards every filter', () async {
      final repository = _ScriptedRepository()
        ..responses.addAll([
          Success(PlatformAuditPage(items: [_event('old')], nextCursor: 'old')),
          Success(PlatformAuditPage(items: [_event('filtered')])),
        ]);
      final controller = PlatformAuditListController(repository);
      addTearDown(controller.dispose);
      await controller.refresh();
      final from = DateTime.utc(2026, 9, 1);
      final before = DateTime.utc(2026, 9, 11);

      await controller.setQuery(PlatformAuditQuery(
        from: from,
        before: before,
        actorKind: PlatformAuditActorKind.system,
        actorId: 'actor-1',
        action: PlatformAuditAction.planChanged,
        category: PlatformAuditCategory.subscription,
        tenantId: 'tenant-1',
        targetType: PlatformAuditTargetResource.planAssignment,
        search: 'safe search',
        cursor: 'must-be-cleared',
        limit: 8,
      ));

      expect(controller.items.single.id, 'filtered');
      final forwarded = repository.calls.last;
      expect(forwarded.cursor, isNull);
      expect(forwarded.from, from);
      expect(forwarded.before, before);
      expect(forwarded.actorKind, PlatformAuditActorKind.system);
      expect(forwarded.actorId, 'actor-1');
      expect(forwarded.action, PlatformAuditAction.planChanged);
      expect(forwarded.category, PlatformAuditCategory.subscription);
      expect(forwarded.tenantId, 'tenant-1');
      expect(forwarded.targetType, PlatformAuditTargetResource.planAssignment);
      expect(forwarded.search, 'safe search');
    });

    test('next-page failure preserves rows and can retry the same cursor',
        () async {
      final repository = _ScriptedRepository()
        ..responses.addAll([
          Success(
              PlatformAuditPage(items: [_event('002')], nextCursor: 'next')),
          const Failure<PlatformAuditPage>('server', code: 'server'),
          Success(PlatformAuditPage(items: [_event('001')])),
        ]);
      final controller = PlatformAuditListController(repository);
      addTearDown(controller.dispose);

      await controller.refresh();
      await controller.loadMore();
      expect(controller.items.single.id, '002');
      expect(controller.failed, isTrue);
      expect(controller.stale, isFalse);
      expect(controller.nextCursor, 'next');

      await controller.loadMore();
      expect(repository.calls.last.cursor, 'next');
      expect(controller.items.map((event) => event.id), ['002', '001']);
      expect(controller.failed, isFalse);
    });

    test('invalid cursor stops paging and refresh recovers from page one',
        () async {
      final repository = _ScriptedRepository()
        ..responses.addAll([
          Success(PlatformAuditPage(items: [_event('002')], nextCursor: 'bad')),
          const Failure<PlatformAuditPage>('invalid', code: 'validation'),
          Success(PlatformAuditPage(items: [_event('fresh')])),
        ]);
      final controller = PlatformAuditListController(repository);
      addTearDown(controller.dispose);

      await controller.refresh();
      await controller.loadMore();
      expect(controller.cursorFailed, isTrue);
      expect(controller.items.single.id, '002');

      await controller.refresh();
      expect(repository.calls.last.cursor, isNull);
      expect(controller.cursorFailed, isFalse);
      expect(controller.items.single.id, 'fresh');
    });

    test('offline cache is honest and offline without data stays empty',
        () async {
      final cachedRepository = _ScriptedRepository()
        ..responses.add(Offline(
          cached: PlatformAuditPage(items: [_event('cached')]),
        ));
      final cached = PlatformAuditListController(cachedRepository);
      addTearDown(cached.dispose);
      await cached.refresh();
      expect(cached.offline, isTrue);
      expect(cached.stale, isTrue);
      expect(cached.items.single.id, 'cached');

      final emptyRepository = _ScriptedRepository()
        ..responses.add(const Offline<PlatformAuditPage>());
      final empty = PlatformAuditListController(emptyRepository);
      addTearDown(empty.dispose);
      await empty.refresh();
      expect(empty.offline, isTrue);
      expect(empty.stale, isFalse);
      expect(empty.items, isEmpty);
    });
  });

  test('date selection becomes inclusive local start and exclusive next day',
      () {
    final day = DateTime(2026, 9, 10, 18, 45);
    expect(auditDayStart(day), DateTime(2026, 9, 10).toUtc());
    expect(auditDayEndExclusive(day), DateTime(2026, 9, 11).toUtc());
  });

  test('active filter count excludes search and includes query dimensions', () {
    expect(auditFilterCount(PlatformAuditQuery(search: 'needle')), 0);
    expect(
      auditFilterCount(PlatformAuditQuery(
        actorKind: PlatformAuditActorKind.system,
        category: PlatformAuditCategory.lifecycle,
        tenantId: 'tenant-1',
      )),
      3,
    );
  });

  testWidgets('search is debounced and forwarded to the repository',
      (tester) async {
    final repository = _ScriptedRepository()
      ..responses.addAll([
        Success(PlatformAuditPage(items: [_event('initial')])),
        Success(PlatformAuditPage(items: [_event('matched')])),
      ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => _now),
        platformAuditRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: PlatformAuditPageWidget(),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(repository.calls, hasLength(1));

    await tester.enterText(find.byKey(const Key('audit-search')), '  الهلال  ');
    await tester.pump(const Duration(milliseconds: 299));
    expect(repository.calls, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(repository.calls, hasLength(2));
    expect(repository.calls.last.search, 'الهلال');
    expect(find.textContaining('فريق matched'), findsOneWidget);
  });

  testWidgets('clear removes search and filters and reloads first page',
      (tester) async {
    final repository = _ScriptedRepository()
      ..responses.addAll([
        Success(PlatformAuditPage(items: [_event('initial')])),
        Success(PlatformAuditPage(items: [_event('searched')])),
        Success(PlatformAuditPage(items: [_event('cleared')])),
      ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => _now),
        platformAuditRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: PlatformAuditPageWidget(),
        ),
      ),
    ));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('audit-search')), 'بحث');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.tap(find.byKey(const Key('audit-clear')));
    await tester.pump();

    expect(repository.calls.last, PlatformAuditQuery(limit: 8));
    expect(find.textContaining('فريق cleared'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('audit-search')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('filter sheet forwards actor, category, tenant and target',
      (tester) async {
    final repository = _ScriptedRepository()
      ..responses.addAll([
        Success(PlatformAuditPage(items: [_event('initial')])),
        Success(PlatformAuditPage(items: [_event('filtered')])),
      ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => _now),
        platformAuditRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: PlatformAuditPageWidget(),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('audit-filters')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('audit-filter-category')));
    await tester.pumpAndSettle();
    await tester.tap(
        find.text(AuditCopy.category(PlatformAuditCategory.lifecycle)).last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('audit-filter-actor-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('النظام').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('audit-filter-tenant-id')),
      'tenant-filtered',
    );
    await tester.tap(find.byKey(const Key('audit-filter-target')));
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .text(AuditCopy.resource(
            PlatformAuditTargetResource.tenantLifecycle,
          ))
          .last,
    );
    await tester.pumpAndSettle();

    final apply = find.byKey(const Key('audit-filter-apply'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    final query = repository.calls.last;
    expect(query.actorKind, PlatformAuditActorKind.system);
    expect(query.category, PlatformAuditCategory.lifecycle);
    expect(query.tenantId, 'tenant-filtered');
    expect(query.targetType, PlatformAuditTargetResource.tenantLifecycle);
    // Arabic-Indic, like every other count in the product. The audit flagged
    // the log for mixing numeral systems inside one screen.
    expect(find.text('تصفية (٤)'), findsOneWidget);
  });

  testWidgets('Main Admin catalogue filters without raw wire values',
      (tester) async {
    final repository = _ScriptedRepository()
      ..responses.addAll([
        Success(PlatformAuditPage(items: [_event('initial')])),
        Success(PlatformAuditPage(items: [_event('filtered')])),
      ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        clockProvider.overrideWithValue(() => _now),
        platformAuditRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: PlatformAuditPageWidget(),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byKey(const Key('audit-filters')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('audit-filter-category')));
    await tester.pumpAndSettle();
    await tester.tap(find
        .text(AuditCopy.category(PlatformAuditCategory.accountManagement))
        .last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('audit-filter-action')));
    await tester.pumpAndSettle();
    final mainAdminAction =
        find.text(AuditCopy.action(PlatformAuditAction.mainAdminSuspended));
    await tester.scrollUntilVisible(
      mainAdminAction,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(mainAdminAction.last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('audit-filter-target')));
    await tester.pumpAndSettle();
    final mainAdminTarget = find
        .text(AuditCopy.resource(PlatformAuditTargetResource.mainAdminAccount));
    await tester.scrollUntilVisible(
      mainAdminTarget,
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(mainAdminTarget.last);
    await tester.pumpAndSettle();

    final apply = find.byKey(const Key('audit-filter-apply'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();

    final query = repository.calls.last;
    expect(query.category, PlatformAuditCategory.accountManagement);
    expect(query.action, PlatformAuditAction.mainAdminSuspended);
    expect(query.targetType, PlatformAuditTargetResource.mainAdminAccount);
    expect(find.textContaining('account_management'), findsNothing);
    expect(find.textContaining('main_admin_'), findsNothing);
  });
}
