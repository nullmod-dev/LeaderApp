import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/platform/data/mock_platform_audit_repository.dart';
import 'package:mtm/features/platform/data/platform_audit_fixtures.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/domain/platform_audit_models.dart';
import 'package:mtm/features/platform/domain/platform_audit_repository.dart';
import 'package:mtm/features/platform/domain/platform_security_repository.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_repository.dart';
import 'package:mtm/l10n/strings.dart';

void main() {
  final now = DateTime.utc(2026, 1, 20, 12);

  PlatformAuditFixtures fixtures() => PlatformAuditFixtures(clock: () => now);

  MockPlatformAuditRepository repository({
    MockPlatformAuditMode mode = MockPlatformAuditMode.loaded,
  }) =>
      MockPlatformAuditRepository(
        fixtures: fixtures(),
        mode: mode,
        latency: Duration.zero,
      );

  Future<PlatformAuditPage> load(
    PlatformAuditRepository repository, [
    PlatformAuditQuery? query,
  ]) async {
    final result = await repository.listAuditEvents(
      query ?? PlatformAuditQuery(),
    );
    expect(result, isA<Success<PlatformAuditPage>>());
    return (result as Success<PlatformAuditPage>).data;
  }

  group('PlatformAuditFixtures', () {
    test('are deterministic from the injected clock and immutable', () {
      var calls = 0;
      final first = PlatformAuditFixtures(clock: () {
        calls++;
        return now;
      });
      final second = fixtures();

      expect(calls, 1);
      expect(
        jsonEncode(first.events.map((event) => event.toJson()).toList()),
        jsonEncode(second.events.map((event) => event.toJson()).toList()),
      );
      expect(
        () => first.events.add(first.events.first),
        throwsUnsupportedError,
      );
      expect(
        () => first.events.first.changes.add(
          const PlatformAuditChange(
            field: PlatformAuditChangeField.featureEnabled,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('contains safe actor snapshots, unknown parsing and deleted tombstone',
        () {
      final events = fixtures().events;
      final administrator = events.first.actor;
      expect(administrator, isA<PlatformAuditAdministratorActor>());
      expect(
        (administrator as PlatformAuditAdministratorActor).id,
        'u_demo_platform',
      );
      expect(administrator.displayName, 'مدير منصة ${S.productNameAr}');

      final unknown = events.singleWhere(
        (event) => event.action == PlatformAuditAction.unknown,
      );
      expect(unknown.actor, isA<PlatformAuditUnknownActor>());
      expect(unknown.target.type, PlatformAuditTargetResource.unknown);
      expect(unknown.target.id, isEmpty);
      expect(unknown.target.displayName, isNull);
      expect(unknown.changes.single.before, isA<PlatformAuditRedactedValue>());

      final finalized = events.singleWhere(
        (event) => event.action == PlatformAuditAction.deletionFinalized,
      );
      expect(finalized.actor, isA<PlatformAuditSystemActor>());
      expect(finalized.tenant?.id, 'saas_retired');
      expect(finalized.tenant?.isDeleted, isTrue);
      expect(finalized.target.id, contains('saas_retired'));
    });
  });

  group('ordering and pagination', () {
    test('sorts by occurredAt descending then event id descending', () async {
      final page = await load(repository());

      for (var index = 1; index < page.items.length; index++) {
        final previous = page.items[index - 1];
        final current = page.items[index];
        final timeOrder = previous.occurredAt.compareTo(current.occurredAt);
        expect(timeOrder, greaterThanOrEqualTo(0));
        if (timeOrder == 0) {
          expect(previous.id.compareTo(current.id), greaterThan(0));
        }
      }
      expect(
        page.items
            .where((event) =>
                event.occurredAt == now.subtract(const Duration(hours: 2)))
            .map((event) => event.id),
        ['audit_009', 'audit_008'],
      );
    });

    test('opaque cursor pages without overlap and anchors after filtering',
        () async {
      final repo = repository();
      final first = await load(
        repo,
        PlatformAuditQuery(tenantId: 'saas_hilal', limit: 2),
      );
      expect(first.nextCursor, isNotNull);
      expect(first.nextCursor, isNot(contains(first.items.last.id)));

      final second = await load(
        repo,
        PlatformAuditQuery(
          tenantId: 'saas_hilal',
          limit: 2,
          cursor: first.nextCursor,
        ),
      );
      expect(
        first.items.map((event) => event.id).toSet().intersection(
              second.items.map((event) => event.id).toSet(),
            ),
        isEmpty,
      );
      expect(second.items, isNotEmpty);
      expect(second.items.every((event) => event.tenant?.id == 'saas_hilal'),
          isTrue);
    });

    test('rejects malformed and filtered-out cursor anchors', () async {
      final repo = repository();
      final malformed = await repo.listAuditEvents(
        PlatformAuditQuery(cursor: 'not+a+cursor'),
      );
      expect(malformed, isA<Failure<PlatformAuditPage>>());
      expect((malformed as Failure<PlatformAuditPage>).code, 'validation');

      final unfiltered = await load(repo, PlatformAuditQuery(limit: 1));
      final notFound = await repo.listAuditEvents(
        PlatformAuditQuery(
          tenantId: 'saas_najd',
          cursor: unfiltered.nextCursor,
        ),
      );
      expect(notFound, isA<Failure<PlatformAuditPage>>());
      expect((notFound as Failure<PlatformAuditPage>).code, 'validation');

      final forged = base64Url
          .encode(utf8.encode(jsonEncode({'v': 1, 'at': 1, 'id': 'missing'})))
          .replaceAll('=', '');
      final missing = await repo.listAuditEvents(
        PlatformAuditQuery(cursor: forged),
      );
      expect(missing, isA<Failure<PlatformAuditPage>>());
      expect((missing as Failure<PlatformAuditPage>).code, 'validation');
    });
  });

  group('filters', () {
    test('filters administrator, system and unknown actors plus actor id',
        () async {
      final repo = repository();
      final administrators = await load(
        repo,
        PlatformAuditQuery(
          actorKind: PlatformAuditActorKind.platformAdministrator,
          actorId: 'u_demo_platform',
        ),
      );
      expect(administrators.items, isNotEmpty);
      expect(
        administrators.items.every(
          (event) =>
              event.actor is PlatformAuditAdministratorActor &&
              (event.actor as PlatformAuditAdministratorActor).id ==
                  'u_demo_platform',
        ),
        isTrue,
      );
      expect(
        (await load(
          repo,
          PlatformAuditQuery(
            actorKind: PlatformAuditActorKind.system,
            actorId: 'u_demo_platform',
          ),
        ))
            .items,
        isEmpty,
      );
      expect(
        (await load(
          repo,
          PlatformAuditQuery(actorKind: PlatformAuditActorKind.system),
        ))
            .items
            .single
            .action,
        PlatformAuditAction.deletionFinalized,
      );
      expect(
        (await load(
          repo,
          PlatformAuditQuery(actorKind: PlatformAuditActorKind.unknown),
        ))
            .items
            .single
            .action,
        PlatformAuditAction.unknown,
      );
    });

    test('filters action and derived category', () async {
      final repo = repository();
      final action = await load(
        repo,
        PlatformAuditQuery(action: PlatformAuditAction.planChanged),
      );
      expect(action.items.single.action, PlatformAuditAction.planChanged);

      final category = await load(
        repo,
        PlatformAuditQuery(category: PlatformAuditCategory.entitlement),
      );
      expect(category.items, hasLength(2));
      expect(
        category.items.every(
          (event) => event.category == PlatformAuditCategory.entitlement,
        ),
        isTrue,
      );
    });

    test('filters tenant and target resource', () async {
      final repo = repository();
      final tenant = await load(
        repo,
        PlatformAuditQuery(tenantId: 'saas_najd'),
      );
      expect(tenant.items, isNotEmpty);
      expect(
        tenant.items.every((event) => event.tenant?.id == 'saas_najd'),
        isTrue,
      );

      final resource = await load(
        repo,
        PlatformAuditQuery(
          targetType: PlatformAuditTargetResource.tenantFeature,
        ),
      );
      expect(
          resource.items.single.action, PlatformAuditAction.featureFlagChanged);
    });

    test('uses inclusive from and exclusive before bounds', () async {
      final repo = repository();
      final boundary = now.subtract(const Duration(hours: 2));
      final from = await load(repo, PlatformAuditQuery(from: boundary));
      expect(from.items.map((event) => event.id),
          containsAll(['audit_009', 'audit_008']));

      final before = await load(repo, PlatformAuditQuery(before: boundary));
      expect(
          before.items.map((event) => event.id), isNot(contains('audit_009')));
      expect(before.items.every((event) => event.occurredAt.isBefore(boundary)),
          isTrue);
    });

    test('normalizes safe search fields and never searches changes', () async {
      final repo = repository();
      final arabic = await load(
        repo,
        PlatformAuditQuery(search: 'مدير   منصه'),
      );
      expect(arabic.items, isNotEmpty);
      expect(
        arabic.items.every(
          (event) => event.actor is PlatformAuditAdministratorActor,
        ),
        isTrue,
      );
      expect(
        (await load(repo, PlatformAuditQuery(search: 'audit_003')))
            .items
            .single
            .id,
        'audit_003',
      );
      expect(
        (await load(repo, PlatformAuditQuery(search: 'saas_retired')))
            .items
            .single
            .tenant
            ?.isDeleted,
        isTrue,
      );
      expect(
        (await load(repo, PlatformAuditQuery(search: 'mtm_advanced'))).items,
        isEmpty,
        reason: 'typed before/after change values are not searchable',
      );
      expect(
        (await load(repo, PlatformAuditQuery(search: 'deletion_pending')))
            .items,
        isEmpty,
        reason: 'lifecycle change values are not searchable',
      );
    });
  });

  group('result modes and isolation', () {
    test('returns loaded, empty, stale, offline cache and failure shapes',
        () async {
      expect(await repository().listAuditEvents(PlatformAuditQuery()),
          isA<Success<PlatformAuditPage>>());

      final empty = await repository(mode: MockPlatformAuditMode.empty)
          .listAuditEvents(PlatformAuditQuery());
      expect((empty as Success<PlatformAuditPage>).data.items, isEmpty);

      final stale = await repository(mode: MockPlatformAuditMode.stale)
          .listAuditEvents(PlatformAuditQuery());
      expect((stale as Success<PlatformAuditPage>).stale, isTrue);

      final cached = await repository(
        mode: MockPlatformAuditMode.offlineWithCache,
      ).listAuditEvents(PlatformAuditQuery());
      expect(cached, isA<Offline<PlatformAuditPage>>());
      expect((cached as Offline<PlatformAuditPage>).cached?.items, isNotEmpty);

      final offline = await repository(
        mode: MockPlatformAuditMode.offlineWithoutCache,
      ).listAuditEvents(PlatformAuditQuery());
      expect(offline, isA<Offline<PlatformAuditPage>>());
      expect((offline as Offline<PlatformAuditPage>).cached, isNull);

      final failure = await repository(mode: MockPlatformAuditMode.failure)
          .listAuditEvents(PlatformAuditQuery());
      expect(failure, isA<Failure<PlatformAuditPage>>());
      expect((failure as Failure<PlatformAuditPage>).code, 'server');
    });

    test('audit read does not mutate an independent tenant store', () async {
      final store = PlatformTenantStore(clock: () => now);
      final before = jsonEncode(
        store.tenants.map((tenant) => tenant.toJson()).toList(),
      );

      await load(repository());

      final after = jsonEncode(
        store.tenants.map((tenant) => tenant.toJson()).toList(),
      );
      expect(after, before);
      expect(repository(), isNot(isA<PlatformSecurityRepository>()));
      expect(repository(), isNot(isA<TenantLifecycleRepository>()));
    });
  });
}
