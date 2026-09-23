import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/motion/animated_counter.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/features/conflict/data/conflict_current_application.dart';
import 'package:mtm/features/conflict/data/conflict_outbox_resolver.dart';
import 'package:mtm/features/conflict/data/conflict_review_controller.dart';
import 'package:mtm/features/conflict/data/conflict_review_recording.dart';
import 'package:mtm/features/conflict/data/in_memory_conflict_review_store.dart';
import 'package:mtm/features/conflict/domain/conflict_models.dart';
import 'package:mtm/features/conflict/domain/conflict_review_entry.dart';
import 'package:mtm/features/shift/data/in_memory_shift_conflict_snapshot_store.dart';
import 'package:mtm/features/shift/data/shift_conflict_review.dart';
import 'package:mtm/features/shift/data/shift_providers.dart';
import 'package:mtm/features/shift/domain/shift_conflict_snapshot.dart';
import 'package:mtm/features/shift/domain/shift_models.dart';
import 'package:mtm/l10n/strings.dart';

/// Task 4 corrective pass §3 — the representative typed Shift conflict
/// snapshot path: a real, registered composer/applier the production app
/// installs (`main.dart`'s `shiftConflictReviewOverrides`), exercised here
/// through that exact registration — not by calling the bare functions —
/// so "the registered production adapter can consume a supplied
/// mocked/future typed snapshot" is actually proven.
T _ok<T>(Result<T> r) => r.when(
      success: (data, {stale = false}) => data,
      failure: (m, code) => fail('expected success, got failure: $m ($code)'),
      offline: (_) => fail('expected success, got offline'),
    );

/// Records every `remove` (and rejects it on demand) so the final narrow
/// correction's ordering/failure guarantees can be proven against the real
/// registered Shift applier/cleaner, not just against fakes.
class _RecordingOutboxStore implements OutboxStore {
  _RecordingOutboxStore(this._delegate, this.calls);

  final OutboxStore _delegate;
  final List<String> calls;
  bool Function(String operationId)? failRemoveWhen;

  @override
  Future<List<PendingOperation>> readAll() => _delegate.readAll();

  @override
  Future<void> upsert(PendingOperation operation) =>
      _delegate.upsert(operation);

  @override
  Future<void> remove(String operationId) async {
    calls.add('outbox.remove:$operationId');
    if (failRemoveWhen?.call(operationId) ?? false) {
      throw StateError('simulated outbox remove failure');
    }
    await _delegate.remove(operationId);
  }
}

/// Records every `remove` against the same shared `calls` list as
/// [_RecordingOutboxStore], so the two stores' relative ordering can be
/// asserted from one list.
class _RecordingSnapshotStore implements ShiftConflictSnapshotStore {
  _RecordingSnapshotStore(this._delegate, this.calls);

  final ShiftConflictSnapshotStore _delegate;
  final List<String> calls;

  @override
  Future<ShiftConflictSnapshot?> read(String conflictId) =>
      _delegate.read(conflictId);

  @override
  Future<void> upsert(String conflictId, ShiftConflictSnapshot snapshot) =>
      _delegate.upsert(conflictId, snapshot);

  @override
  Future<void> remove(String conflictId) async {
    calls.add('snapshot.remove:$conflictId');
    await _delegate.remove(conflictId);
  }
}

void main() {
  ProviderContainer buildContainer() {
    final c = ProviderContainer(overrides: [
      outboxStoreProvider.overrideWithValue(InMemoryOutboxStore()),
      conflictReviewStoreProvider
          .overrideWithValue(InMemoryConflictReviewStore()),
      ...shiftConflictReviewOverrides,
    ]);
    addTearDown(c.dispose);
    return c;
  }

  ConflictReviewEntry entryFor(String conflictId) => ConflictReviewEntry(
        conflictId: conflictId,
        entityType: 'shift',
        entityId: 'sh_1',
        recordTitle: 'الشفت · مركز حرستا',
        detectedAt: DateTime(2026, 9, 5, 10),
        differences: const [
          ConflictFieldComparison(
            fieldId: 'needed',
            label: 'العدد المطلوب',
            localValue: '٤',
            currentValue: '٦',
          ),
        ],
      );

  Future<Shift> createLocalShift(ProviderContainer c) async {
    final result = await c.read(shiftRepositoryProvider).create(
          detachmentId: 'd_dam_central',
          date: DateTime(2026, 9, 10),
          centerName: 'مركز حرستا',
          startMinutes: 8 * 60,
          endMinutes: 14 * 60,
          needed: 4,
        );
    return _ok(result);
  }

  PendingOperation conflictedOp(
          {required String entityId, String id = 'op-1'}) =>
      PendingOperation.create(
        kind: 'shift.assign',
        entityType: 'shift',
        entityId: entityId,
        idFactory: () => id,
      ).copyWith(state: SyncState.conflict, lastProblemCode: 'test_only_stale');

  group('the registered production Shift composer', () {
    test('produces a feature-approved entry from a supplied typed snapshot',
        () async {
      final c = buildContainer();
      final local = await createLocalShift(c);
      final op = conflictedOp(entityId: local.id);

      await c.read(shiftConflictSnapshotStoreProvider).upsert(
            op.operationId,
            ShiftConflictSnapshot(
              current: local.copyWith(needed: 6),
              baseVersion: '7',
              currentVersion: '8',
            ),
          );

      final composer = c.read(conflictReviewComposersProvider)['shift'];
      expect(composer, isNotNull,
          reason: 'the Shift composer must be registered');

      final entry = await composer!(op);

      expect(entry, isNotNull);
      expect(entry!.conflictId, op.operationId);
      expect(entry.entityType, 'shift');
      expect(entry.currentVersion, '8');
      expect(entry.baseVersion, '7');
      expect(entry.differences, isNotEmpty);
      expect(
        entry.differences.any((d) => d.label == S.shiftNeededLabel),
        isTrue,
      );
    });

    test('uses localized field labels through presentShiftConflict', () async {
      final c = buildContainer();
      final local = await createLocalShift(c);
      final op = conflictedOp(entityId: local.id);
      await c.read(shiftConflictSnapshotStoreProvider).upsert(
            op.operationId,
            ShiftConflictSnapshot(current: local.copyWith(needed: 9)),
          );

      final entry = await c.read(conflictReviewComposersProvider)['shift']!(op);

      final needed =
          entry!.differences.singleWhere((d) => d.fieldId == 'needed');
      expect(needed.label, S.shiftNeededLabel);
      expect(needed.localValue, toArabicIndic('4'));
      expect(needed.currentValue, toArabicIndic('9'));
    });

    test('never exposes a raw id, JSON key, or hidden field', () async {
      final c = buildContainer();
      final local = await createLocalShift(c);
      final op = conflictedOp(entityId: local.id);
      await c.read(shiftConflictSnapshotStoreProvider).upsert(
            op.operationId,
            ShiftConflictSnapshot(current: local.copyWith(needed: 6)),
          );

      final entry = await c.read(conflictReviewComposersProvider)['shift']!(op);

      final rendered = [
        entry!.recordTitle,
        if (entry.recordSubtitle != null) entry.recordSubtitle!,
        for (final d in entry.differences) ...[
          d.label,
          d.localValue,
          d.currentValue,
        ],
      ].join(' | ');

      for (final forbidden in [
        op.operationId,
        local.id,
        'shift.assign',
        'entityType'
      ]) {
        expect(rendered.contains(forbidden), isFalse,
            reason: 'the entry rendered "$forbidden"');
      }
    });

    test(
        'with no captured snapshot, the conflict stays unavailable rather '
        'than fabricated', () async {
      final c = buildContainer();
      final local = await createLocalShift(c);
      final op = conflictedOp(entityId: local.id);
      // Deliberately never upserted into shiftConflictSnapshotStoreProvider.

      final entry = await c.read(conflictReviewComposersProvider)['shift']!(op);

      expect(entry, isNull);
    });
  });

  group('the registered production Shift applier', () {
    test(
        'applies the current snapshot locally but does not clear its own '
        'snapshot', () async {
      final c = buildContainer();
      final local = await createLocalShift(c);
      final op = conflictedOp(entityId: local.id);
      final store = c.read(shiftConflictSnapshotStoreProvider);
      await store.upsert(
        op.operationId,
        ShiftConflictSnapshot(current: local.copyWith(needed: 6)),
      );

      final applier = c.read(conflictCurrentAppliersProvider)['shift'];
      expect(applier, isNotNull,
          reason: 'the Shift applier must be registered');
      final applied = await applier!(op);

      expect(applied, isTrue);
      final reread = _ok(await c.read(shiftRepositoryProvider).byId(local.id));
      expect(reread.needed, 6);
      // Cleanup is a separate, later step (`clearShiftConflictSnapshot`) —
      // the applier itself must never delete the snapshot it just used.
      expect(await store.read(op.operationId), isNotNull);
    });

    test(
        'with no captured snapshot, refuses rather than fabricating a '
        'local write', () async {
      final c = buildContainer();
      final local = await createLocalShift(c);
      final op = conflictedOp(entityId: local.id);

      final applied =
          await c.read(conflictCurrentAppliersProvider)['shift']!(op);

      expect(applied, isFalse);
      final unchanged =
          _ok(await c.read(shiftRepositoryProvider).byId(local.id));
      expect(unchanged.needed, 4);
    });

    test('a repository-rejected snapshot fails without throwing', () async {
      final c = buildContainer();
      final local = await createLocalShift(c);
      final op = conflictedOp(entityId: local.id);
      await c.read(shiftConflictSnapshotStoreProvider).upsert(
            op.operationId,
            // needed: 0 is rejected by MockShiftRepository.update's own
            // validation — an honest "could not apply", not a crash.
            ShiftConflictSnapshot(current: local.copyWith(needed: 0)),
          );

      final applied =
          await c.read(conflictCurrentAppliersProvider)['shift']!(op);

      expect(applied, isFalse);
    });

    test(
        'a shift deleted from another device is named, not flattened into a '
        'generic failure', () async {
      final c = buildContainer();
      final local = await createLocalShift(c);
      // The operation still points at the shift; the shift itself is gone,
      // which is what the repository reports as `not_found`.
      final op = conflictedOp(entityId: 'shift-that-no-longer-exists');
      await c.read(shiftConflictSnapshotStoreProvider).upsert(
            op.operationId,
            ShiftConflictSnapshot(
              current: Shift(
                id: 'shift-that-no-longer-exists',
                detachmentId: local.detachmentId,
                date: local.date,
                centerName: local.centerName,
                startMinutes: local.startMinutes,
                endMinutes: local.endMinutes,
                needed: 6,
                attendees: local.attendees,
              ),
            ),
          );

      await expectLater(
        c.read(conflictCurrentAppliersProvider)['shift']!(op),
        throwsA(isA<ConflictResolutionException>()
            .having((e) => e.reason, 'reason',
                ConflictResolutionFailure.recordDeleted)
            .having((e) => e.isStale, 'keeps the screen open', isFalse)),
      );

      // The user's own shift is untouched by the attempt.
      final unchanged =
          _ok(await c.read(shiftRepositoryProvider).byId(local.id));
      expect(unchanged.needed, 4);
    });
  });

  group('the registered production Shift snapshot cleaner', () {
    test('removes the snapshot for its operation id', () async {
      final c = buildContainer();
      final local = await createLocalShift(c);
      final op = conflictedOp(entityId: local.id);
      final store = c.read(shiftConflictSnapshotStoreProvider);
      await store.upsert(
        op.operationId,
        ShiftConflictSnapshot(current: local.copyWith(needed: 6)),
      );

      final cleaner = c.read(conflictSnapshotCleanersProvider)['shift'];
      expect(cleaner, isNotNull,
          reason: 'the Shift cleaner must be registered');
      await cleaner!(op);

      expect(await store.read(op.operationId), isNull);
    });
  });

  group('end-to-end through applyConflictResolution', () {
    /// Builds a container, creates one real local shift through it, and
    /// seeds the outbox/review stores *directly* (bypassing `enqueue`, which
    /// would mint its own id) with a matching conflicted operation — all
    /// before `outboxProvider`/`conflictReviewProvider` are ever read, so
    /// the seeded rows are what those providers first build from.
    Future<(ProviderContainer, Shift, PendingOperation)> seeded() async {
      final c = buildContainer();
      final local = await createLocalShift(c);
      final op = conflictedOp(entityId: local.id);
      await c.read(outboxStoreProvider).upsert(op);
      await c
          .read(conflictReviewStoreProvider)
          .upsert(entryFor(op.operationId));
      return (c, local, op);
    }

    test(
        'successful useLocal removes the original operation, the review '
        'entry, and the typed snapshot — while preserving the replacement',
        () async {
      final (c, local, op) = await seeded();
      await c.read(shiftConflictSnapshotStoreProvider).upsert(
            op.operationId,
            ShiftConflictSnapshot(current: local.copyWith(needed: 6)),
          );

      await c.read(conflictDecisionHandlerProvider)(
        ConflictResolutionDecision(
          conflictId: op.operationId,
          localOperationId: op.operationId,
          intent: ConflictResolutionIntent.useLocal,
          currentVersion: '8',
        ),
      );

      final ops = await c.read(outboxProvider.future);
      expect(ops, hasLength(1));
      expect(ops.single.operationId, isNot(op.operationId));
      expect(ops.single.resolvesOperationId, op.operationId);
      expect(await c.read(conflictReviewProvider.future), isEmpty);
      expect(
        await c.read(shiftConflictSnapshotStoreProvider).read(op.operationId),
        isNull,
      );
    });

    test(
        'useLocal with a missing currentVersion preserves the original '
        'operation, the review entry, and the typed snapshot', () async {
      final (c, local, op) = await seeded();
      await c.read(shiftConflictSnapshotStoreProvider).upsert(
            op.operationId,
            ShiftConflictSnapshot(current: local.copyWith(needed: 6)),
          );

      await expectLater(
        c.read(conflictDecisionHandlerProvider)(
          ConflictResolutionDecision(
            conflictId: op.operationId,
            localOperationId: op.operationId,
            intent: ConflictResolutionIntent.useLocal,
            // currentVersion omitted — null.
          ),
        ),
        throwsA(isA<StateError>()),
      );

      final ops = await c.read(outboxProvider.future);
      expect(ops.single.operationId, op.operationId);
      expect(ops.single.state, SyncState.conflict);
      expect(await c.read(conflictReviewProvider.future), hasLength(1));
      expect(
        await c.read(shiftConflictSnapshotStoreProvider).read(op.operationId),
        isNotNull,
      );
    });

    test(
        'successful useCurrent removes the typed snapshot only after the '
        'outbox operation is retired', () async {
      final calls = <String>[];
      final recordingOutbox =
          _RecordingOutboxStore(InMemoryOutboxStore(), calls);
      final recordingSnapshotStore = _RecordingSnapshotStore(
        InMemoryShiftConflictSnapshotStore(),
        calls,
      );
      final container = ProviderContainer(overrides: [
        outboxStoreProvider.overrideWithValue(recordingOutbox),
        conflictReviewStoreProvider
            .overrideWithValue(InMemoryConflictReviewStore()),
        shiftConflictSnapshotStoreProvider
            .overrideWithValue(recordingSnapshotStore),
        ...shiftConflictReviewOverrides,
      ]);
      addTearDown(container.dispose);

      // The local shift, the conflicted operation, its review entry and its
      // snapshot are all created *through this same container*, so the
      // applier's `ShiftRepository.update` lands on the record it expects.
      final local = await createLocalShift(container);
      final op = conflictedOp(entityId: local.id);
      await container.read(outboxStoreProvider).upsert(op);
      await container
          .read(conflictReviewStoreProvider)
          .upsert(entryFor(op.operationId));
      await recordingSnapshotStore.upsert(
        op.operationId,
        ShiftConflictSnapshot(current: local.copyWith(needed: 6)),
      );

      await container.read(conflictDecisionHandlerProvider)(
        ConflictResolutionDecision(
          conflictId: op.operationId,
          localOperationId: op.operationId,
          intent: ConflictResolutionIntent.useCurrent,
        ),
      );

      expect(calls, [
        'outbox.remove:${op.operationId}',
        'snapshot.remove:${op.operationId}',
      ]);
      expect(await container.read(outboxProvider.future), isEmpty);
      expect(await recordingSnapshotStore.read(op.operationId), isNull);
    });

    test(
        'if outbox retirement fails after applying the current Shift, the '
        'original operation, review entry, and typed snapshot all remain',
        () async {
      final failingOutbox = _RecordingOutboxStore(InMemoryOutboxStore(), []);
      final snapshotStore = InMemoryShiftConflictSnapshotStore();
      final container = ProviderContainer(overrides: [
        outboxStoreProvider.overrideWithValue(failingOutbox),
        conflictReviewStoreProvider
            .overrideWithValue(InMemoryConflictReviewStore()),
        shiftConflictSnapshotStoreProvider.overrideWithValue(snapshotStore),
        ...shiftConflictReviewOverrides,
      ]);
      addTearDown(container.dispose);

      final local = await createLocalShift(container);
      final op = conflictedOp(entityId: local.id);
      failingOutbox.failRemoveWhen = (id) => id == op.operationId;
      await container.read(outboxStoreProvider).upsert(op);
      await container
          .read(conflictReviewStoreProvider)
          .upsert(entryFor(op.operationId));
      await snapshotStore.upsert(
        op.operationId,
        ShiftConflictSnapshot(current: local.copyWith(needed: 6)),
      );

      await expectLater(
        container.read(conflictDecisionHandlerProvider)(
          ConflictResolutionDecision(
            conflictId: op.operationId,
            localOperationId: op.operationId,
            intent: ConflictResolutionIntent.useCurrent,
          ),
        ),
        throwsA(isA<StateError>()),
      );

      final ops = await container.read(outboxProvider.future);
      expect(ops.single.operationId, op.operationId);
      expect(ops.single.state, SyncState.conflict);
      expect(await container.read(conflictReviewProvider.future), hasLength(1));
      expect(await snapshotStore.read(op.operationId), isNotNull);
    });
  });

  test(
      'reviewLater (doing nothing) leaves a captured snapshot exactly '
      'where it was', () async {
    final c = buildContainer();
    final local = await createLocalShift(c);
    final op = conflictedOp(entityId: local.id);
    await c.read(shiftConflictSnapshotStoreProvider).upsert(
          op.operationId,
          ShiftConflictSnapshot(current: local.copyWith(needed: 6)),
        );

    // reviewLater is "calling nothing" (`conflict_outbox_resolver.dart`) —
    // the snapshot the composer already captured is untouched either way.
    final stillThere =
        await c.read(shiftConflictSnapshotStoreProvider).read(op.operationId);
    expect(stillThere, isNotNull);
  });
}
