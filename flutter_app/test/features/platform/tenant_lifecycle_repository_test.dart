import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/platform/data/mock_tenant_lifecycle_repository.dart';
import 'package:mtm/features/platform/data/platform_tenant_store.dart';
import 'package:mtm/features/platform/domain/saas_tenant_models.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_repository.dart';

void main() {
  var now = DateTime.utc(2026, 9, 9, 12);

  PlatformTenantStore store() => PlatformTenantStore(clock: () => now);

  MockTenantLifecycleRepository repo(
    PlatformTenantStore store, {
    MockTenantLifecycleMode mode = MockTenantLifecycleMode.loaded,
  }) =>
      MockTenantLifecycleRepository(
        store: store,
        clock: () => now,
        mode: mode,
        latency: Duration.zero,
      );

  T unwrap<T>(Result<T> result) => result.when(
        success: (data, {stale = false}) => data,
        failure: (message, code) => throw TestFailure('$code: $message'),
        offline: (_) => throw TestFailure('offline'),
      );

  String? failureCode<T>(Result<T> result) => result.when(
        success: (_, {stale = false}) => null,
        failure: (_, code) => code,
        offline: (_) => 'offline',
      );

  setUp(() => now = DateTime.utc(2026, 9, 9, 12));

  group('suspend and reactivate', () {
    test('mutate only lifecycle and create focused history', () async {
      final shared = store();
      final repository = repo(shared);
      final before = shared.byId('saas_afiah')!;
      final subscription = before.subscription.toJson();
      final features = shared.featuresOf(before.id)!.toJson();
      final counts = before.counts.toJson();

      final suspended = unwrap(await repository.suspend(SuspendTenantCommand(
        tenantId: before.id,
        expectedVersion: before.tenantVersion,
        idempotencyKey: 'suspend-1',
        reason: 'مراجعة أمنية موثقة',
      )));
      expect(suspended.lifecycle.status, SaasTenantStatus.suspended);
      expect(shared.tenantSummary().suspended, 2);
      expect(shared.byId(before.id)!.subscription.toJson(), subscription);
      expect(shared.byId(before.id)!.counts.toJson(), counts);
      expect(shared.featuresOf(before.id)!.toJson(), features);
      expect(
        shared.historyOf(shared.byId(before.id)!).first.type,
        SaasTenantEventType.tenantSuspended,
      );

      now = now.add(const Duration(seconds: 1));
      final reactivated = unwrap(
        await repository.reactivate(ReactivateTenantCommand(
          tenantId: before.id,
          expectedVersion: suspended.lifecycle.version,
          idempotencyKey: 'reactivate-1',
        )),
      );
      expect(reactivated.lifecycle.status, SaasTenantStatus.active);
      expect(shared.tenantSummary().suspended, 1);
      expect(shared.byId(before.id)!.subscription.toJson(), subscription);
      expect(shared.featuresOf(before.id)!.toJson(), features);
      expect(shared.byId(before.id)!.counts.toJson(), counts);
      expect(
        shared.historyOf(shared.byId(before.id)!).first.type,
        SaasTenantEventType.tenantReactivated,
      );
    });

    test('requires a concise reason', () async {
      final shared = store();
      final before = shared.byId('saas_hilal')!;
      final result = await repo(shared).suspend(SuspendTenantCommand(
        tenantId: before.id,
        expectedVersion: before.tenantVersion,
        idempotencyKey: 'suspend-invalid',
        reason: '   ',
      ));
      expect(
        failureCode(result),
        TenantLifecycleProblemCode.invalidReason.wire,
      );
      expect(shared.byId(before.id)!.tenantStatus, SaasTenantStatus.active);
    });
  });

  group('pending deletion', () {
    test('retains every canonical summary/configuration during grace',
        () async {
      final shared = store();
      final before = shared.byId('saas_afiah')!;
      final beforeJson = before.toJson();
      final features = shared.featuresOf(before.id)!.toJson();

      final result = unwrap(
        await repo(shared).beginDeletion(BeginTenantDeletionCommand(
          tenantId: before.id,
          expectedVersion: before.tenantVersion,
          idempotencyKey: 'delete-request-1',
          reason: 'طلب إنهاء موثق',
        )),
      );
      final pending = shared.byId(before.id)!;
      expect(result.lifecycle.status, SaasTenantStatus.deletionPending);
      expect(pending.displayName, before.displayName);
      expect(pending.mainAdmin.toJson(), before.mainAdmin.toJson());
      expect(pending.subscription.toJson(), before.subscription.toJson());
      expect(pending.usage.toJson(), before.usage.toJson());
      expect(pending.counts.toJson(), before.counts.toJson());
      expect(shared.featuresOf(before.id)!.toJson(), features);
      expect(pending.toJson(), isNot(beforeJson),
          reason: 'only lifecycle and updatedAt change');
      expect(result.lifecycle.deletion?.scheduledFor,
          now.add(kProvisionalTenantDeletionGrace));
      expect(
        shared.historyOf(pending).first.type,
        SaasTenantEventType.deletionRequested,
      );
    });

    test('cancels back to the exact previous suspended state', () async {
      final shared = store();
      final repository = repo(shared);
      final suspended = shared.byId('saas_rukn')!;
      final suspensionJson = suspended.lifecycle.suspension!.toJson();
      final pending = unwrap(
        await repository.beginDeletion(BeginTenantDeletionCommand(
          tenantId: suspended.id,
          expectedVersion: suspended.tenantVersion,
          idempotencyKey: 'delete-suspended',
          reason: 'طلب إنهاء موثق',
        )),
      );
      now = now.add(const Duration(days: 1));
      final cancelled = unwrap(
        await repository.cancelDeletion(CancelTenantDeletionCommand(
          tenantId: suspended.id,
          expectedVersion: pending.lifecycle.version,
          idempotencyKey: 'cancel-delete-suspended',
        )),
      );
      expect(cancelled.lifecycle.status, SaasTenantStatus.suspended);
      expect(cancelled.lifecycle.suspension!.toJson(), suspensionJson);
      expect(
        shared.historyOf(shared.byId(suspended.id)!).first.type,
        SaasTenantEventType.deletionCancelled,
      );
    });
  });

  group('concurrency, idempotency, and offline refusal', () {
    test('stale version never overwrites the fresh lifecycle', () async {
      final shared = store();
      final repository = repo(shared);
      final before = shared.byId('saas_hilal')!;
      await repository.suspend(SuspendTenantCommand(
        tenantId: before.id,
        expectedVersion: before.tenantVersion,
        idempotencyKey: 'operator-2-suspend',
        reason: 'سبب موثق',
      ));
      final stale = await repository.beginDeletion(
        BeginTenantDeletionCommand(
          tenantId: before.id,
          expectedVersion: before.tenantVersion,
          idempotencyKey: 'operator-1-delete',
          reason: 'سبب موثق',
        ),
      );
      expect(
        failureCode(stale),
        TenantLifecycleProblemCode.staleTenant.wire,
      );
      expect(shared.byId(before.id)!.tenantStatus, SaasTenantStatus.suspended);
    });

    test('same idempotency key replays success without a second event',
        () async {
      final shared = store();
      final repository = repo(shared);
      final before = shared.byId('saas_hilal')!;
      final command = SuspendTenantCommand(
        tenantId: before.id,
        expectedVersion: before.tenantVersion,
        idempotencyKey: 'stable-key',
        reason: 'سبب موثق',
      );
      final first = unwrap(await repository.suspend(command));
      final eventCount = shared.historyOf(shared.byId(before.id)!).length;
      final replay = unwrap(await repository.suspend(command));
      expect(first.changed, isTrue);
      expect(replay.changed, isFalse);
      expect(replay.idempotentReplay, isTrue);
      expect(shared.historyOf(shared.byId(before.id)!), hasLength(eventCount));
    });

    test('reusing a key for a different request is refused', () async {
      final shared = store();
      final repository = repo(shared);
      final before = shared.byId('saas_hilal')!;
      await repository.suspend(SuspendTenantCommand(
        tenantId: before.id,
        expectedVersion: before.tenantVersion,
        idempotencyKey: 'same-key',
        reason: 'السبب الأول',
      ));
      final conflict = await repository.suspend(SuspendTenantCommand(
        tenantId: before.id,
        expectedVersion: before.tenantVersion,
        idempotencyKey: 'same-key',
        reason: 'سبب مختلف',
      ));
      expect(
        failureCode(conflict),
        TenantLifecycleProblemCode.idempotencyConflict.wire,
      );
    });

    test('offline never queues or claims a lifecycle write', () async {
      final shared = store();
      final before = shared.byId('saas_hilal')!;
      final result = await repo(
        shared,
        mode: MockTenantLifecycleMode.offline,
      ).suspend(SuspendTenantCommand(
        tenantId: before.id,
        expectedVersion: before.tenantVersion,
        idempotencyKey: 'offline',
        reason: 'سبب موثق',
      ));
      expect(result.isOffline, isTrue);
      expect(shared.byId(before.id)!.lifecycle, same(before.lifecycle));
    });
  });

  group('final deletion mock semantics', () {
    test('is not early and then leaves only a minimal tombstone', () async {
      final shared = store();
      final repository = repo(shared);
      final before = shared.byId('saas_hilal')!;
      final oldCode = before.teamCode;
      final pending = unwrap(
        await repository.beginDeletion(BeginTenantDeletionCommand(
          tenantId: before.id,
          expectedVersion: before.tenantVersion,
          idempotencyKey: 'begin-final',
          reason: 'طلب حذف نهائي موثق',
        )),
      );

      final early = await repository.finalizeDeletion(
        FinalizeTenantDeletionCommand(
          tenantId: before.id,
          expectedVersion: pending.lifecycle.version,
          idempotencyKey: 'final-early',
        ),
      );
      expect(
        failureCode(early),
        TenantLifecycleProblemCode.deletionNotEffective.wire,
      );
      expect(shared.byId(before.id), isNotNull);

      now = pending.lifecycle.deletion!.scheduledFor;
      final finalized = unwrap(
        await repository.finalizeDeletion(FinalizeTenantDeletionCommand(
          tenantId: before.id,
          expectedVersion: pending.lifecycle.version,
          idempotencyKey: 'final-effective',
        )),
      );
      expect(finalized.lifecycle.status, SaasTenantStatus.deleted);
      expect(shared.byId(before.id), isNull);
      expect(shared.tombstoneById(before.id), same(finalized.tombstone));
      expect(shared.featuresOf(before.id), isNull);
      expect(shared.teamCodeLinksToTenant(oldCode), isFalse);
      expect(shared.isTeamCodeTaken(oldCode), isTrue,
          reason: 'retired Team Codes are not immediately reusable');
      expect(shared.deletedHistoryOf(before.id)!.first.type,
          SaasTenantEventType.tenantDeleted);

      final tombstoneJson = finalized.tombstone!.toJson().toString();
      for (final forbidden in [
        'teamCode',
        'mainAdmin',
        'subscription',
        'features',
        'counts',
        'usage',
        'reason',
        'scheduledFor',
        'previousStatus',
        'suspension',
      ]) {
        expect(tombstoneJson.contains(forbidden), isFalse, reason: forbidden);
      }
    });
  });
}
