import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/platform/data/mock_platform_break_glass_repository.dart';
import 'package:mtm/features/platform/data/mock_tenant_lifecycle_repository.dart';
import 'package:mtm/features/platform/data/platform_break_glass_fixtures.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/domain/platform_break_glass_models.dart';
import 'package:mtm/features/platform/domain/platform_break_glass_repository.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';

void main() {
  var now = DateTime.utc(2026, 9, 11, 9);
  final actor = BreakGlassInitiator(
    accountId: 'u_demo_platform',
    displayName: 'مدير منصة MTM',
  );
  const read = {BreakGlassScope.tenantOperationalRead};

  setUp(() => now = DateTime.utc(2026, 9, 11, 9));

  PlatformTenantStore store() => PlatformTenantStore(clock: () => now);

  MockPlatformBreakGlassRepository repo(
    PlatformTenantStore store, {
    MockBreakGlassMode mode = MockBreakGlassMode.loaded,
    BreakGlassFixtureScenario seed = BreakGlassFixtureScenario.none,
    BreakGlassInitiator? initiator,
    bool signedOut = false,
  }) =>
      MockPlatformBreakGlassRepository(
        store: store,
        clock: () => now,
        actor: signedOut ? null : (initiator ?? actor),
        mode: mode,
        seed: seed,
        latency: Duration.zero,
      );

  ActivateBreakGlassCommand activation(
    PlatformTenantStore store, {
    String tenantId = 'saas_hilal',
    String key = 'attempt-1',
    String reason = 'تعذّر على قائد الفريق الوصول',
    int? version,
  }) =>
      ActivateBreakGlassCommand(
        tenantId: tenantId,
        expectedTenantVersion: version ?? store.byId(tenantId)!.tenantVersion,
        scopes: read,
        reason: reason,
        idempotencyKey: breakGlassActivationIdempotencyKey(key),
      );

  EndBreakGlassCommand ending(BreakGlassGrant grant) => EndBreakGlassCommand(
        grantId: grant.id,
        expectedRevision: grant.revision,
        idempotencyKey: breakGlassEndIdempotencyKey(
          grantId: grant.id,
          expectedRevision: grant.revision,
        ),
      );

  T unwrap<T>(Result<T> result) => result.when(
        success: (data, {stale = false}) => data,
        failure: (message, code) => throw TestFailure('$code: $message'),
        offline: (_) => throw TestFailure('offline'),
      );

  String? code<T>(Result<T> result) => result.when(
        success: (_, {stale = false}) => null,
        failure: (_, code) => code,
        offline: (_) => 'offline',
      );

  group('activate / read / end', () {
    test('grant times come only from the injected clock', () async {
      final shared = store();
      final repository = repo(shared);
      expect(unwrap(await repository.loadCurrent()).grant, isNull);

      final result = unwrap(await repository.activate(activation(shared)));
      expect(result.changed, isTrue);
      final grant = result.grant;
      expect(grant.issuedAt, now);
      expect(grant.expiresAt, now.add(kProvisionalBreakGlassGrantDuration));
      expect(grant.tenant.tenantId, 'saas_hilal');
      expect(grant.tenant.displayName, shared.byId('saas_hilal')!.displayName);
      expect(grant.initiator.accountId, actor.accountId);

      final current = unwrap(await repository.loadCurrent());
      expect(current.grant!.id, grant.id);
      expect(current.readAt, now);

      now = now.add(const Duration(minutes: 3));
      final ended = unwrap(await repository.end(ending(grant))).grant;
      expect(ended.status, BreakGlassGrantStatus.ended);
      expect(ended.endReason, BreakGlassEndReason.endedByInitiator);
      expect(ended.endedAt, now);
      expect(unwrap(await repository.loadCurrent()).grant!.status,
          BreakGlassGrantStatus.ended);
    });

    test('expiry is recorded by the authority, and ending it is refused',
        () async {
      final shared = store();
      final repository = repo(shared);
      final grant = unwrap(await repository.activate(activation(shared))).grant;

      now = grant.expiresAt;
      final current = unwrap(await repository.loadCurrent()).grant!;
      expect(current.status, BreakGlassGrantStatus.expired);
      expect(
          code(await repository.end(ending(grant))), 'break_glass_not_active');

      final renewed = unwrap(await repository.activate(
        activation(shared, key: 'attempt-2', reason: 'سبب جديد موثق'),
      ))
          .grant;
      expect(renewed.id, isNot(grant.id));
      expect(renewed.status, BreakGlassGrantStatus.active);
    });
  });

  group('concurrency and idempotency', () {
    test('same key + same command replays; different command conflicts',
        () async {
      final shared = store();
      final repository = repo(shared);
      final first = unwrap(await repository.activate(activation(shared)));
      final replay = unwrap(await repository.activate(activation(shared)));
      expect(replay.idempotentReplay, isTrue);
      expect(replay.changed, isFalse);
      expect(replay.grant.id, first.grant.id);

      expect(
        code(await repository.activate(
          activation(shared, reason: 'سبب مختلف'),
        )),
        'idempotency_conflict',
      );
      expect(
        code(await repository.activate(activation(shared, key: 'attempt-2'))),
        'break_glass_already_active',
      );
    });

    test('stale tenant version and stale grant revision never overwrite',
        () async {
      final shared = store();
      final repository = repo(shared);
      final version = shared.byId('saas_hilal')!.tenantVersion;
      expect(
        code(await repository.activate(
          activation(shared, version: version + 1),
        )),
        'stale_tenant',
      );
      final grant = unwrap(await repository.activate(activation(shared))).grant;
      final stale = EndBreakGlassCommand(
        grantId: grant.id,
        expectedRevision: grant.revision + 1,
        idempotencyKey: 'end-stale',
      );
      expect(code(await repository.end(stale)), 'stale_break_glass');
      expect(unwrap(await repository.loadCurrent()).grant!.isActiveAt(now),
          isTrue);
      expect(
        code(await repository.end(const EndBreakGlassCommand(
          grantId: 'bg_other',
          expectedRevision: 1,
          idempotencyKey: 'end-other',
        ))),
        'break_glass_not_found',
      );
    });
  });

  group('online-only, authorization, recent auth', () {
    test('offline refuses commands and never manufactures authority', () async {
      final shared = store();
      final online = repo(shared);
      expect(unwrap(await online.loadCurrent()).grant, isNull);

      final offline = repo(shared, mode: MockBreakGlassMode.offline);
      expect(await offline.activate(activation(shared)),
          isA<Offline<BreakGlassMutationResult>>());
      final read = await offline.loadCurrent();
      expect(read, isA<Offline<BreakGlassSnapshot>>());
      expect((read as Offline<BreakGlassSnapshot>).cached, isNull);
    });

    test('stale reads are flagged and never treated as confirmed', () async {
      final shared = store();
      final repository = MockPlatformBreakGlassRepository(
        store: shared,
        clock: () => now,
        actor: actor,
        latency: Duration.zero,
        seed: BreakGlassFixtureScenario.active,
      );
      final fresh = unwrap(await repository.loadCurrent());
      expect(fresh.grant, isNotNull);
      final stale = await repo(
        shared,
        mode: MockBreakGlassMode.stale,
        seed: BreakGlassFixtureScenario.active,
      ).loadCurrent();
      expect((stale as Success<BreakGlassSnapshot>).stale, isTrue);
    });

    test('recent authentication and permission are typed outcomes', () async {
      final shared = store();
      expect(
        code(await repo(shared, mode: MockBreakGlassMode.recentAuthRequired)
            .activate(activation(shared))),
        'recent_authentication_required',
      );
      expect(
        code(await repo(shared, mode: MockBreakGlassMode.notPermitted)
            .activate(activation(shared))),
        'not_permitted',
      );
      final signedOut = repo(shared, signedOut: true);
      expect(code(await signedOut.loadCurrent()), 'not_permitted');
      expect(
          code(await signedOut.activate(activation(shared))), 'not_permitted');
      expect(
          code(await repo(shared, mode: MockBreakGlassMode.failure)
              .loadCurrent()),
          'server');
    });
  });

  group('tenant lifecycle precedence', () {
    test('suspended and deletion-pending tenants are not eligible', () async {
      final shared = store();
      final repository = repo(shared);
      expect(
          code(await repository
              .activate(activation(shared, tenantId: 'saas_rukn'))),
          'tenant_not_eligible');

      final lifecycle = MockTenantLifecycleRepository(
        store: shared,
        clock: () => now,
        latency: Duration.zero,
      );
      final najd = shared.byId('saas_najd')!;
      await lifecycle.beginDeletion(BeginTenantDeletionCommand(
        tenantId: najd.id,
        expectedVersion: najd.tenantVersion,
        idempotencyKey: 'begin-najd',
        reason: 'طلب حذف موثق',
      ));
      expect(shared.byId('saas_najd')!.tenantStatus,
          SaasTenantStatus.deletionPending);
      expect(
          code(await repository
              .activate(activation(shared, tenantId: 'saas_najd'))),
          'tenant_not_eligible');
    });

    test('a deleted tenant is refused and never resurrected', () async {
      final shared = store();
      final lifecycle = MockTenantLifecycleRepository(
        store: shared,
        clock: () => now,
        latency: Duration.zero,
      );
      final najd = shared.byId('saas_najd')!;
      await lifecycle.beginDeletion(BeginTenantDeletionCommand(
        tenantId: najd.id,
        expectedVersion: najd.tenantVersion,
        idempotencyKey: 'begin',
        reason: 'طلب حذف موثق',
      ));
      now = now.add(kProvisionalTenantDeletionGrace);
      final pending = shared.byId('saas_najd')!;
      await lifecycle.finalizeDeletion(FinalizeTenantDeletionCommand(
        tenantId: pending.id,
        expectedVersion: pending.tenantVersion,
        idempotencyKey: 'finalize',
      ));
      final tombstone = shared.tombstoneById('saas_najd')!.toJson();

      final repository = repo(shared);
      expect(
        code(await repository.activate(activation(shared,
            tenantId: 'saas_najd', version: pending.tenantVersion + 1))),
        'tenant_already_deleted',
      );
      expect(shared.byId('saas_najd'), isNull);
      expect(shared.tombstoneById('saas_najd')!.toJson(), tombstone);
      expect(unwrap(await repository.loadCurrent()).grant, isNull);
    });

    test('a tenant leaving active ends the live grant authoritatively',
        () async {
      final shared = store();
      final repository = repo(shared);
      final grant = unwrap(await repository.activate(activation(shared))).grant;
      final lifecycle = MockTenantLifecycleRepository(
        store: shared,
        clock: () => now,
        latency: Duration.zero,
      );
      await lifecycle.suspend(SuspendTenantCommand(
        tenantId: grant.tenant.tenantId,
        expectedVersion: shared.byId(grant.tenant.tenantId)!.tenantVersion,
        idempotencyKey: 'suspend',
        reason: 'مراجعة موثقة',
      ));
      final current = unwrap(await repository.loadCurrent()).grant!;
      expect(current.status, BreakGlassGrantStatus.ended);
      expect(current.endReason, BreakGlassEndReason.tenantUnavailable);
    });
  });

  group('separation', () {
    test('activate and end change no tenant, commercial or history state',
        () async {
      final shared = store();
      final before = shared.byId('saas_hilal')!;
      final snapshot = (
        tenant: before.toJson(),
        features: shared.featuresOf(before.id)!.toJson(),
        history: shared.historyOf(before).map((e) => e.id).toList(),
        summary: shared.tenantSummary().suspended,
      );
      final repository = repo(shared);
      final grant = unwrap(await repository.activate(activation(shared))).grant;
      unwrap(await repository.end(ending(grant)));

      final after = shared.byId('saas_hilal')!;
      expect(after.toJson(), snapshot.tenant);
      expect(shared.featuresOf(after.id)!.toJson(), snapshot.features);
      expect(
          shared.historyOf(after).map((e) => e.id).toList(), snapshot.history);
      expect(shared.tenantSummary().suspended, snapshot.summary);
    });

    test(
        'break-glass sources depend on no tenant operational, audit or '
        'security repository', () {
      const files = [
        'lib/features/platform/domain/platform_break_glass_models.dart',
        'lib/features/platform/domain/platform_break_glass_repository.dart',
        'lib/features/platform/data/platform_break_glass_fixtures.dart',
        'lib/features/platform/data/mock_platform_break_glass_repository.dart',
        'lib/features/platform/data/platform_break_glass_providers.dart',
      ];
      const forbidden = [
        'features/detachment',
        'features/member',
        'features/shift',
        'features/attendance',
        'features/storage',
        'features/workshop',
        'features/announcement',
        'platform_audit',
        'platform_security',
        'platform_health',
        'saas_subscription_repository',
        'tenant_feature_repository',
        'sync/',
        'outbox',
      ];
      for (final path in files) {
        final imports = File(path)
            .readAsLinesSync()
            .where((line) => line.startsWith('import '));
        for (final line in imports) {
          for (final token in forbidden) {
            expect(line.contains(token), isFalse, reason: '$path → $line');
          }
        }
      }
    });
  });

  group('fixtures', () {
    test('each scenario seeds the documented state', () async {
      Future<BreakGlassGrant?> seeded(BreakGlassFixtureScenario s) async =>
          unwrap(await repo(store(), seed: s).loadCurrent()).grant;

      expect(await seeded(BreakGlassFixtureScenario.none), isNull);
      final active = (await seeded(BreakGlassFixtureScenario.active))!;
      expect(active.isActiveAt(now), isTrue);
      expect(active.remainingAt(now) > kBreakGlassNearExpiryWindow, isTrue);
      final near = (await seeded(BreakGlassFixtureScenario.nearExpiry))!;
      expect(near.isActiveAt(now), isTrue);
      expect(near.remainingAt(now) <= kBreakGlassNearExpiryWindow, isTrue);
      expect((await seeded(BreakGlassFixtureScenario.expired))!.status,
          BreakGlassGrantStatus.expired);
      expect((await seeded(BreakGlassFixtureScenario.ended))!.endReason,
          BreakGlassEndReason.endedByInitiator);
      expect((await seeded(BreakGlassFixtureScenario.revoked))!.endReason,
          BreakGlassEndReason.revokedByPlatform);
      expect((await seeded(BreakGlassFixtureScenario.unsupported))!.status,
          BreakGlassGrantStatus.unknown);
    });
  });
}
