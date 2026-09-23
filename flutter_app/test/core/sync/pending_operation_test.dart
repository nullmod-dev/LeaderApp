import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/core/sync/uuid_v7.dart';

void main() {
  group('PendingOperation.create', () {
    test('mints one identity used for both the row and the wire key', () {
      final op = PendingOperation.create(kind: 'inventory.movement.add');
      expect(isUuidV7(op.operationId), isTrue);
      expect(op.idempotencyKey, op.operationId);
      expect(op.state, SyncState.pending);
      expect(op.attemptCount, 0);
    });

    test('idFactory is honoured so tests can pin the value', () {
      var n = 0;
      final op = PendingOperation.create(
        kind: 'k',
        idFactory: () => 'op-${n++}',
      );
      expect(op.operationId, 'op-0');
      expect(op.idempotencyKey, 'op-0');
    });

    test('carries no payload field — only sync metadata', () {
      final json = PendingOperation.create(
        kind: 'shift.attendance.mark',
        entityType: 'shift',
        entityId: 'sh_1',
      ).toJson();
      expect(
        json.keys,
        unorderedEquals([
          'operationId',
          'idempotencyKey',
          'kind',
          'createdAt',
          'entityType',
          'entityId',
          'state',
          'attemptCount',
        ]),
      );
    });
  });

  group('identity stability', () {
    test('copyWith never changes the operation or idempotency identity', () {
      final op = PendingOperation.create(kind: 'k', idFactory: () => 'fixed');
      final after = op
          .copyWith(state: SyncState.syncing)
          .copyWith(
              state: SyncState.failed,
              attemptCount: 3,
              lastProblemCode: 'offline')
          .copyWith(state: SyncState.pending);
      expect(after.operationId, 'fixed');
      expect(after.idempotencyKey, 'fixed');
      expect(after.attemptCount, 3);
      expect(after.lastProblemCode, 'offline');
    });

    test('round-trips through JSON unchanged', () {
      final op = PendingOperation.create(
        kind: 'inventory.movement.add',
        entityType: 'inventory_item',
        entityId: 'i1',
        clock: () => DateTime(2026, 9, 4, 9),
        idFactory: () => '0192f0c1-2345-7abc-8def-0123456789ab',
      ).copyWith(
          state: SyncState.failed,
          attemptCount: 2,
          lastAttemptAt: DateTime(2026, 9, 4, 10),
          lastProblemCode: 'server');
      final back = PendingOperation.fromJson(op.toJson());
      expect(back, op);
      // The serialized form is itself stable.
      expect(back.toJson(), op.toJson());
    });
  });

  group(
      'resolvesOperationId / currentVersion (Task 4 corrective — the '
      'useLocal replacement identity)', () {
    test('an ordinary enqueue carries neither', () {
      final op = PendingOperation.create(kind: 'shift.assign');
      expect(op.resolvesOperationId, isNull);
      expect(op.currentVersion, isNull);
      expect(op.isConflictResolution, isFalse);
    });

    test('a replacement operation carries both and reports itself as one', () {
      final op = PendingOperation.create(
        kind: 'shift.assign',
        resolvesOperationId: 'op-original',
        currentVersion: '8',
      );
      expect(op.resolvesOperationId, 'op-original');
      expect(op.currentVersion, '8');
      expect(op.isConflictResolution, isTrue);
    });

    test('copyWith never drops the reference or the version', () {
      final op = PendingOperation.create(
        kind: 'shift.assign',
        resolvesOperationId: 'op-original',
        currentVersion: '8',
      ).copyWith(state: SyncState.failed, lastProblemCode: 'offline');
      expect(op.resolvesOperationId, 'op-original');
      expect(op.currentVersion, '8');
    });

    test('round-trips through JSON, present only when set', () {
      final withRef = PendingOperation.create(
        kind: 'shift.assign',
        resolvesOperationId: 'op-original',
        currentVersion: '8',
        clock: () => DateTime(2026, 9, 5, 9),
        idFactory: () => 'op-new',
      );
      final json = withRef.toJson();
      expect(json['resolvesOperationId'], 'op-original');
      expect(json['currentVersion'], '8');
      expect(PendingOperation.fromJson(json), withRef);

      final ordinary =
          PendingOperation.create(kind: 'shift.assign', idFactory: () => 'x');
      expect(ordinary.toJson().containsKey('resolvesOperationId'), isFalse);
      expect(ordinary.toJson().containsKey('currentVersion'), isFalse);
    });

    test(
        'an operation serialized before this pair of fields existed still '
        'decodes safely', () {
      final legacyJson = <String, dynamic>{
        'operationId': 'op-legacy',
        'idempotencyKey': 'op-legacy',
        'kind': 'shift.assign',
        'createdAt': DateTime(2026, 8, 1).toUtc().toIso8601String(),
        'state': 'conflict',
        'attemptCount': 1,
      };

      final restored = PendingOperation.fromJson(legacyJson);

      expect(restored.resolvesOperationId, isNull);
      expect(restored.currentVersion, isNull);
      expect(restored.isConflictResolution, isFalse);
      expect(restored.state, SyncState.conflict);
    });
  });

  group('SyncState.fromWire', () {
    test('an unknown state is kept as pending, never treated as done', () {
      // `needsReview` remains genuinely unmodelled (Task 2 added `conflict`
      // only — see `sync_state.dart`), so it is still the right "does not
      // exist yet" probe here.
      expect(SyncState.fromWire('needsReview'), SyncState.pending);
      expect(SyncState.fromWire(null), SyncState.pending);
      expect(SyncState.fromWire('synced'), SyncState.synced);
    });

    test('conflict is a known, recognised wire value (Task 2)', () {
      expect(SyncState.fromWire('conflict'), SyncState.conflict);
    });

    test('isUnsynced covers everything except synced', () {
      expect(SyncState.pending.isUnsynced, isTrue);
      expect(SyncState.syncing.isUnsynced, isTrue);
      expect(SyncState.failed.isUnsynced, isTrue);
      expect(SyncState.conflict.isUnsynced, isTrue);
      expect(SyncState.synced.isUnsynced, isFalse);
    });

    test('isRetryable excludes conflict but includes the ordinary states', () {
      expect(SyncState.pending.isRetryable, isTrue);
      expect(SyncState.syncing.isRetryable, isTrue);
      expect(SyncState.failed.isRetryable, isTrue);
      expect(SyncState.conflict.isRetryable, isFalse);
      expect(SyncState.synced.isRetryable, isFalse);
    });

    test('needsReview is true only for conflict', () {
      expect(SyncState.conflict.needsReview, isTrue);
      expect(SyncState.pending.needsReview, isFalse);
      expect(SyncState.failed.needsReview, isFalse);
      expect(SyncState.synced.needsReview, isFalse);
    });
  });
}
