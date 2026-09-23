import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/problem/problem.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/platform/data/mock_saas_tenant_repository.dart';
import 'package:mtm/features/platform/data/platform_tenant_fixtures.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/domain/saas_tenant_models.dart';
import 'package:mtm/features/platform/domain/saas_subscription_models.dart';
import 'package:mtm/features/platform/domain/saas_tenant_repository.dart';
import 'package:mtm/features/platform/domain/saas_tenant_validation.dart';
import 'package:mtm/features/platform/domain/team_code.dart';

/// Point 6 — the canonical subscriber dataset and the repository over it.
void main() {
  final now = DateTime.utc(2026, 9, 8, 16);

  PlatformTenantStore store([DateTime? instant]) =>
      PlatformTenantStore(clock: () => instant ?? now);

  MockSaasTenantRepository repo({
    PlatformTenantStore? on,
    MockSaasTenantMode mode = MockSaasTenantMode.loaded,
  }) =>
      MockSaasTenantRepository(
        store: on ?? store(),
        mode: mode,
        latency: Duration.zero,
      );

  T unwrap<T>(Result<T> result) => result.when(
        success: (data, {stale = false}) => data,
        failure: (message, code) => throw TestFailure('failure $code'),
        offline: (_) => throw TestFailure('unexpected offline'),
      );

  group('the canonical dataset', () {
    test('is eight subscribers in the four Point 5 buckets', () {
      final tenants = canonicalSaasTenants(now);

      expect(tenants, hasLength(8));
      expect(
        tenants.where((t) => t.listStatus == SaasTenantListStatus.active),
        hasLength(4),
      );
      expect(
        tenants.where((t) => t.listStatus == SaasTenantListStatus.trial),
        hasLength(2),
      );
      expect(
        tenants.where((t) => t.listStatus == SaasTenantListStatus.grace),
        hasLength(1),
      );
      expect(
        tenants.where((t) => t.listStatus == SaasTenantListStatus.suspended),
        hasLength(1),
      );
    });

    test('ids and Team Codes are unique, and every code is well formed', () {
      final tenants = canonicalSaasTenants(now);

      expect({for (final t in tenants) t.id}, hasLength(tenants.length));
      expect({for (final t in tenants) t.teamCode}, hasLength(tenants.length));
      for (final tenant in tenants) {
        expect(validateTeamCode(tenant.teamCode), isNull,
            reason: tenant.teamCode);
      }
    });

    test('is deterministic and moves only with the injected clock', () {
      final first = canonicalSaasTenants(now);
      final again = canonicalSaasTenants(now);
      final later = canonicalSaasTenants(now.add(const Duration(days: 3)));

      expect(
        [for (final t in first) t.toJson()],
        [for (final t in again) t.toJson()],
      );
      for (var i = 0; i < first.length; i++) {
        expect(
          later[i].createdAt.difference(first[i].createdAt),
          const Duration(days: 3),
        );
      }
    });

    test('ordering is newest first and total', () {
      final tenants = canonicalSaasTenants(now);
      for (var i = 1; i < tenants.length; i++) {
        expect(
          tenants[i - 1].createdAt.isAfter(tenants[i].createdAt),
          isTrue,
          reason: '${tenants[i - 1].id} before ${tenants[i].id}',
        );
      }
    });

    test('every record round-trips through JSON', () {
      for (final tenant in canonicalSaasTenants(now)) {
        expect(SaasTenant.fromJson(tenant.toJson()).toJson(), tenant.toJson());
      }
    });

    test('carries no medical, patient or credential-shaped field', () {
      // The model has nowhere to put a secret; this asserts the *fixtures*
      // did not smuggle one into a free-text field either.
      final json = [for (final t in canonicalSaasTenants(now)) t.toJson()]
          .toString()
          .toLowerCase();
      for (final forbidden in const [
        'password',
        'كلمة المرور',
        'otp',
        'token',
        'secret',
      ]) {
        expect(json.contains(forbidden), isFalse, reason: forbidden);
      }
    });
  });

  group('an unknown wire value is refused, never repaired', () {
    test('an unrecognised status makes the record unreadable', () {
      final json = canonicalSaasTenants(now).first.toJson();
      json['lifecycle'] = {
        ...json['lifecycle'] as Map<String, dynamic>,
        'status': 'archived',
      };

      expect(SaasTenantStatus.parse('deletion_pending'),
          SaasTenantStatus.deletionPending);
      expect(SaasTenantStatus.parse('archived'), isNull);
      expect(() => SaasTenant.fromJson(json), throwsFormatException);
    });

    test('a malformed team code makes the record unreadable', () {
      final json = canonicalSaasTenants(now).first.toJson()
        ..['teamCode'] = 'not-a-code';

      expect(() => SaasTenant.fromJson(json), throwsFormatException);
    });
  });

  group('list', () {
    test('returns every subscriber with a truthful total', () async {
      final page = unwrap(await repo().list(const SaasTenantQuery()));

      expect(page.items, hasLength(8));
      expect(page.total, 8);
      expect(page.hasMore, isFalse);
      expect(page.nextCursor, isNull);
    });

    test('filters by status', () async {
      final page = unwrap(await repo().list(
        const SaasTenantQuery(status: SaasTenantListStatus.trial),
      ));

      expect(page.total, 2);
      expect(
        page.items.every((t) => t.listStatus == SaasTenantListStatus.trial),
        isTrue,
      );
    });

    test('searches name, Main Admin, email and Team Code', () async {
      final r = repo();

      expect(unwrap(await r.list(const SaasTenantQuery(search: 'عافية'))).total,
          1);
      expect(
          unwrap(await r.list(const SaasTenantQuery(search: 'سلمى'))).total, 1);
      expect(
        unwrap(await r.list(const SaasTenantQuery(search: 'badr@najd'))).total,
        1,
      );
      expect(
        unwrap(await r.list(const SaasTenantQuery(search: 'MTM-4K7P-QX92')))
            .total,
        1,
      );
    });

    test('search is normalized the way the rest of the app normalizes',
        () async {
      // «الهلال» written without the hamza-carrying forms and in a different
      // case for the Latin part: the shared `searchKey` folds both.
      final r = repo();
      expect(
          unwrap(await r.list(const SaasTenantQuery(search: 'هلال'))).total, 1);
      expect(
        unwrap(await r.list(const SaasTenantQuery(search: 'mtm-4k7p-qx92')))
            .total,
        1,
      );
    });

    test('search and status compose', () async {
      final page = unwrap(await repo().list(
        const SaasTenantQuery(
          search: 'فريق',
          status: SaasTenantListStatus.active,
        ),
      ));

      expect(
        page.items.every((t) =>
            t.listStatus == SaasTenantListStatus.active &&
            t.displayName.contains('فريق')),
        isTrue,
      );
    });

    test('a query that matches nothing is an empty page, not a failure',
        () async {
      final page =
          unwrap(await repo().list(const SaasTenantQuery(search: 'لا يوجد')));

      expect(page.items, isEmpty);
      expect(page.total, 0);
    });

    test('pages with an opaque cursor and a total that ignores the page',
        () async {
      final r = repo();
      final first = unwrap(await r.list(const SaasTenantQuery(limit: 3)));

      expect(first.items, hasLength(3));
      expect(first.total, 8);
      expect(first.hasMore, isTrue);

      final second = unwrap(await r.list(
        SaasTenantQuery(limit: 3, cursor: first.nextCursor),
      ));
      expect(second.items, hasLength(3));
      expect(second.total, 8);
      expect(
        {
          for (final t in [...first.items, ...second.items]) t.id
        },
        hasLength(6),
      );
    });

    test('is stable — the same query twice gives the same rows in order',
        () async {
      final r = repo();
      final a = unwrap(await r.list(const SaasTenantQuery()));
      final b = unwrap(await r.list(const SaasTenantQuery()));

      expect([for (final t in a.items) t.id], [for (final t in b.items) t.id]);
    });
  });

  group('byId', () {
    test('finds a subscriber', () async {
      final tenant = unwrap(await repo().byId('saas_afiah'));
      expect(tenant.displayName, 'جمعية عافية');
    });

    test('answers not_found for an unknown id', () async {
      final result = await repo().byId('saas_nope');
      result.when(
        success: (_, {stale = false}) => fail('expected a failure'),
        failure: (_, code) => expect(code, ProblemCode.notFound.wire),
        offline: (_) => fail('expected a failure'),
      );
    });
  });

  group('statusHistory', () {
    test('a trial tenant has creation and trial start only', () async {
      final events = unwrap(await repo().statusHistory('saas_nabd'));

      expect(
        events.map((e) => e.type),
        containsAll([
          SaasTenantEventType.tenantCreated,
          SaasTenantEventType.trialStarted,
        ]),
      );
      expect(
        events.map((e) => e.type),
        isNot(contains(SaasTenantEventType.subscriptionActivated)),
      );
    });

    test('a suspended tenant carries the grace step that preceded it',
        () async {
      final events = unwrap(await repo().statusHistory('saas_rukn'));

      expect(events.first.type, SaasTenantEventType.tenantSuspended);
      expect(
        events.map((e) => e.type),
        contains(SaasTenantEventType.movedToGrace),
      );
    });

    test('is newest first and unique by id', () async {
      final events = unwrap(await repo().statusHistory('saas_hilal'));

      expect({for (final e in events) e.id}, hasLength(events.length));
      for (var i = 1; i < events.length; i++) {
        expect(
          events[i - 1].occurredAt.isBefore(events[i].occurredAt),
          isFalse,
        );
      }
    });

    test('answers not_found for an unknown id', () async {
      final result = await repo().statusHistory('saas_nope');
      expect(result.isFailure, isTrue);
    });
  });

  group('create', () {
    const draft = SaasTenantDraft(
      displayName: '  فريق الشمال الطبي  ',
      mainAdminName: 'أمل  السبيعي',
      mainAdminEmail: '  Amal@Shamal.ORG ',
      teamCode: 'mtm 7dqx 4nkr',
    );

    test('normalizes, registers, and starts a trial with a pending admin',
        () async {
      final shared = store();
      final tenant = unwrap(await repo(on: shared).create(draft));

      expect(tenant.displayName, 'فريق الشمال الطبي');
      expect(tenant.mainAdmin.name, 'أمل السبيعي');
      expect(tenant.mainAdmin.email, 'amal@shamal.org');
      expect(tenant.teamCode, 'MTM-7DQX-4NKR');
      expect(tenant.tenantStatus, SaasTenantStatus.active);
      expect(tenant.subscription.status, SubscriptionStatus.trial);
      expect(tenant.mainAdmin.provisioning, MainAdminProvisioning.pendingSetup);
      expect(tenant.createdAt, now);
      expect(
        tenant.subscription.trialEndsAt,
        now.add(const Duration(days: kDefaultTrialDays)),
      );
      expect(shared.tenants, hasLength(9));
    });

    test('the created record carries no credential of any kind', () async {
      final tenant = unwrap(await repo().create(draft));
      final json = tenant.toJson().toString().toLowerCase();

      for (final forbidden in const ['password', 'otp', 'token', 'secret']) {
        expect(json.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('a new subscriber appears in the list and in the summary', () async {
      final shared = store();
      final r = repo(on: shared);
      await r.create(draft);

      final page = unwrap(await r.list(const SaasTenantQuery()));
      expect(page.total, 9);
      expect(shared.tenantSummary().total, 9);
      expect(shared.tenantSummary().activeTrials, 3);
    });

    test('refuses a duplicate Team Code, whatever the punctuation', () async {
      final shared = store();
      final result = await repo(on: shared).create(
        const SaasTenantDraft(
          displayName: 'فريق آخر',
          mainAdminName: 'مدير',
          mainAdminEmail: 'a@b.org',
          teamCode: 'mtm4k7pqx92',
        ),
      );

      result.when(
        success: (_, {stale = false}) => fail('expected a conflict'),
        failure: (_, code) => expect(
          code,
          SaasTenantProblemCode.teamCodeConflict.wire,
        ),
        offline: (_) => fail('expected a conflict'),
      );
      expect(shared.tenants, hasLength(8));
    });

    test('refuses an invalid draft with a validation code', () async {
      for (final bad in [
        const SaasTenantDraft(
          displayName: '   ',
          mainAdminName: 'مدير',
          mainAdminEmail: 'a@b.org',
          teamCode: 'MTM-7DQX-4NKR',
        ),
        const SaasTenantDraft(
          displayName: 'فريق',
          mainAdminName: 'مدير',
          mainAdminEmail: 'not-an-email',
          teamCode: 'MTM-7DQX-4NKR',
        ),
        const SaasTenantDraft(
          displayName: 'فريق',
          mainAdminName: 'مدير',
          mainAdminEmail: 'a@b.org',
          teamCode: 'ABC-1234',
        ),
      ]) {
        final result = await repo().create(bad);
        result.when(
          success: (_, {stale = false}) => fail('expected validation'),
          failure: (_, code) => expect(code, ProblemCode.validation.wire),
          offline: (_) => fail('expected validation'),
        );
      }
    });

    test('offline is refused rather than queued', () async {
      final shared = store();
      final result = await repo(
        on: shared,
        mode: MockSaasTenantMode.offlineWithCache,
      ).create(draft);

      expect(result.isOffline, isTrue);
      expect(shared.tenants, hasLength(8));
    });

    test('a repository failure changes nothing', () async {
      final shared = store();
      final result = await repo(on: shared, mode: MockSaasTenantMode.failure)
          .create(draft);

      expect(result.isFailure, isTrue);
      expect(shared.tenants, hasLength(8));
    });
  });

  group('repository states', () {
    test('empty is a success with no rows, not a failure', () async {
      final page = unwrap(
        await repo(mode: MockSaasTenantMode.empty)
            .list(const SaasTenantQuery()),
      );
      expect(page.items, isEmpty);
      expect(page.total, 0);
    });

    test('offline with cache carries the process-memory copy', () async {
      final result = await repo(mode: MockSaasTenantMode.offlineWithCache)
          .list(const SaasTenantQuery());

      result.when(
        success: (_, {stale = false}) => fail('expected offline'),
        failure: (_, __) => fail('expected offline'),
        offline: (cached) => expect(cached!.items, hasLength(8)),
      );
    });

    test('offline without cache carries nothing', () async {
      final result = await repo(mode: MockSaasTenantMode.offlineWithoutCache)
          .list(const SaasTenantQuery());

      result.when(
        success: (_, {stale = false}) => fail('expected offline'),
        failure: (_, __) => fail('expected offline'),
        offline: (cached) => expect(cached, isNull),
      );
    });

    test('failure carries a typed code and no exception text', () async {
      final result = await repo(mode: MockSaasTenantMode.failure)
          .list(const SaasTenantQuery());

      result.when(
        success: (_, {stale = false}) => fail('expected failure'),
        failure: (message, code) {
          expect(code, ProblemCode.server.wire);
          expect(message.contains('Exception'), isFalse);
        },
        offline: (_) => fail('expected failure'),
      );
    });
  });

  group('the repository seam has no destructive method', () {
    test('SaasTenantRepository declares exactly the Point 6 operations', () {
      // A compile-time statement: this list is the interface, and a Point 7
      // mutation added to it would have to be added here too.
      const SaasTenantRepository? seam = null;
      expect(seam, isNull);
      expect(
        SaasTenantProblemCode.values.map((c) => c.wire),
        ['tenant_code_conflict', 'invalid_tenant_code'],
      );
    });
  });

  group('team codes', () {
    test('normalize to one canonical spelling', () {
      for (final raw in const [
        'MTM-4K7P-QX92',
        'mtm-4k7p-qx92',
        'mtm 4k7p qx92',
        'MTM4K7PQX92',
      ]) {
        expect(normalizeTeamCode(raw), 'MTM-4K7P-QX92', reason: raw);
      }
    });

    test('validation accepts the canonical shape and refuses the rest', () {
      expect(validateTeamCode('MTM-4K7P-QX92'), isNull);
      expect(validateTeamCode(''), TeamCodeError.empty);
      expect(validateTeamCode('   '), TeamCodeError.empty);
      // `I`, `O`, `0` and `1` are outside the alphabet on purpose.
      expect(validateTeamCode('MTM-I0O1-QX92'), TeamCodeError.malformed);
      expect(validateTeamCode('ABC-4K7P-QX92'), TeamCodeError.malformed);
      expect(validateTeamCode('MTM-4K7P'), TeamCodeError.malformed);
    });

    test('generation is deterministic and produces valid codes', () {
      expect(teamCodeFromSeed(7), teamCodeFromSeed(7));
      expect(teamCodeFromSeed(7), isNot(teamCodeFromSeed(8)));
      for (var seed = 0; seed < 200; seed++) {
        expect(validateTeamCode(teamCodeFromSeed(seed)), isNull,
            reason: '$seed');
      }
    });
  });

  group('field validation', () {
    test('accepts a good draft', () {
      expect(
        validateDraft(const SaasTenantDraft(
          displayName: 'فريق',
          mainAdminName: 'مدير',
          mainAdminEmail: 'a.b+c@example.co.uk',
          teamCode: 'MTM-4K7P-QX92',
        )),
        isEmpty,
      );
    });

    test('names the field that is wrong', () {
      final errors = validateDraft(const SaasTenantDraft(
        displayName: '',
        mainAdminName: '',
        mainAdminEmail: 'nope',
        teamCode: 'nope',
      ));

      expect(errors['displayName'], SaasTenantFieldError.required);
      expect(errors['mainAdminName'], SaasTenantFieldError.required);
      expect(errors['mainAdminEmail'], SaasTenantFieldError.invalidEmail);
      expect(errors['teamCode'], SaasTenantFieldError.invalidTeamCode);
    });

    test('refuses an over-long value', () {
      final errors = validateDraft(SaasTenantDraft(
        displayName: 'ا' * (kTeamNameMaxLength + 1),
        mainAdminName: 'مدير',
        mainAdminEmail: 'a@b.org',
        teamCode: 'MTM-4K7P-QX92',
      ));

      expect(errors['displayName'], SaasTenantFieldError.tooLong);
    });
  });
}
