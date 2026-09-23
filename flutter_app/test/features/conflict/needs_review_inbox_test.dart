import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/sync/conflict_review_recorder.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_conflict_classifier.dart';
import 'package:mtm/core/sync/sync_coordinator.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/core/sync/sync_transport.dart';
import 'package:mtm/features/conflict/data/conflict_current_application.dart';
import 'package:mtm/features/conflict/data/conflict_outbox_resolver.dart';
import 'package:mtm/features/conflict/data/conflict_review_controller.dart';
import 'package:mtm/features/conflict/data/conflict_review_recording.dart';
import 'package:mtm/features/conflict/data/in_memory_conflict_review_store.dart';
import 'package:mtm/features/conflict/domain/conflict_models.dart';
import 'package:mtm/features/conflict/domain/conflict_review_entry.dart';
import 'package:mtm/features/conflict/domain/conflict_review_store.dart';
import 'package:mtm/features/conflict/domain/needs_review_item.dart';
import 'package:mtm/l10n/strings.dart';

/// Task 4 — the durable Needs Review foundation: what is stored when a
/// conflict is detected, how the inbox is derived from the outbox, and what
/// each decision does to the stored metadata.
///
/// A private wire code, never a real one, drives the classifier — the same
/// idiom `conflict_outbox_test.dart` uses so no test asserts a production
/// string.
const _conflictCode = 'test_only_stale';

class _Transport implements SyncTransport {
  _Transport(this.answer);
  Result<void> answer;
  @override
  Future<Result<void>> push(PendingOperation operation) async => answer;
}

ConflictReviewEntry entryFor(
  String conflictId, {
  String entityType = 'shift',
  String recordTitle = 'الشفت · مركز داريا',
  DateTime? detectedAt,
}) =>
    ConflictReviewEntry(
      conflictId: conflictId,
      entityType: entityType,
      entityId: 'sh_1',
      recordTitle: recordTitle,
      recordSubtitle: 'الجمعة · ٥ سبتمبر',
      detectedAt: detectedAt ?? DateTime(2026, 9, 5, 10),
      baseVersion: '7',
      currentVersion: '8',
      differences: const [
        ConflictFieldComparison(
          fieldId: 'needed',
          label: 'العدد المطلوب',
          localValue: '٤',
          currentValue: '٦',
        ),
      ],
    );

void main() {
  ProviderContainer containerWith({
    List<PendingOperation> operations = const [],
    List<ConflictReviewEntry> entries = const [],
    ConflictReviewStore? reviewStore,
    OutboxStore? outboxStore,
    List<Override> extra = const [],
  }) {
    final c = ProviderContainer(overrides: [
      outboxStoreProvider.overrideWithValue(
          outboxStore ?? InMemoryOutboxStore(seed: operations)),
      conflictReviewStoreProvider.overrideWithValue(
          reviewStore ?? InMemoryConflictReviewStore(seed: entries)),
      ...extra,
    ]);
    addTearDown(c.dispose);
    return c;
  }

  PendingOperation conflicted(
    String id, {
    String kind = 'shift.assign',
    String? entityType = 'shift',
    DateTime? attemptedAt,
  }) =>
      PendingOperation.create(
        kind: kind,
        entityType: entityType,
        entityId: 'sh_1',
        idFactory: () => id,
        clock: () => DateTime(2026, 9, 5, 9),
      ).copyWith(
        state: SyncState.conflict,
        lastAttemptAt: attemptedAt ?? DateTime(2026, 9, 5, 10),
      );

  Future<List<NeedsReviewItem>> itemsOf(ProviderContainer c) async {
    await c.read(outboxProvider.future);
    await c.read(conflictReviewProvider.future);
    return c.read(needsReviewItemsProvider).requireValue;
  }

  group('durable review entry', () {
    test('round-trips through JSON with only approved, formatted values', () {
      final restored = ConflictReviewEntry.fromJson(entryFor('op-1').toJson());

      expect(restored.conflictId, 'op-1');
      expect(restored.recordTitle, 'الشفت · مركز داريا');
      expect(restored.currentVersion, '8');
      expect(restored.differences.single.label, 'العدد المطلوب');
      expect(restored.differences.single.localValue, '٤');
      expect(
        restored.differences.single.valueDirection,
        ConflictValueDirection.natural,
      );
    });

    test('an unknown stored value direction degrades to the ambient one', () {
      final json = entryFor('op-1').toJson();
      (json['differences'] as List).first['valueDirection'] = 'rtl-ish';

      expect(
        ConflictReviewEntry.fromJson(json).differences.single.valueDirection,
        ConflictValueDirection.natural,
      );
    });

    test('rebuilds the Task 1 presentation with conflictId as the operation',
        () {
      final presentation = entryFor('op-1').toPresentation();

      // FRONTEND-BACKEND-INTEGRATION.md §5.4: one identity, not two.
      expect(presentation.conflictId, 'op-1');
      expect(presentation.localOperationId, 'op-1');
      expect(presentation.differences, hasLength(1));
    });

    test('a second detection supersedes rather than stacks', () async {
      final store = InMemoryConflictReviewStore(seed: [entryFor('op-1')]);
      await store.upsert(entryFor('op-1', recordTitle: 'الشفت · مركز جرمانا'));

      final rows = await store.readAll();
      expect(rows, hasLength(1));
      expect(rows.single.recordTitle, 'الشفت · مركز جرمانا');
    });
  });

  group('the inbox is derived from the outbox', () {
    test('lists conflicted operations only, newest conflict first', () async {
      final c = containerWith(
        operations: [
          conflicted('op-old', attemptedAt: DateTime(2026, 9, 5, 8)),
          conflicted('op-new', attemptedAt: DateTime(2026, 9, 5, 12)),
          PendingOperation.create(
            kind: 'inventory.movement.add',
            entityType: 'inventory_item',
            entityId: 'i1',
            idFactory: () => 'op-pending',
          ),
        ],
        entries: [entryFor('op-old'), entryFor('op-new')],
      );

      final items = await itemsOf(c);
      expect(items.map((i) => i.conflictId), ['op-new', 'op-old']);
    });

    test('its length is always the Settings count', () async {
      final c = containerWith(
        operations: [conflicted('op-1'), conflicted('op-2')],
        entries: [entryFor('op-1')],
      );

      final items = await itemsOf(c);
      expect(items, hasLength(c.read(conflictOperationsCountProvider)));
    });

    test('a conflict with no stored metadata is listed, not hidden', () async {
      final c = containerWith(operations: [conflicted('op-1')]);

      final item = (await itemsOf(c)).single;
      expect(item.isReviewable, isFalse);
      expect(item.entry, isNull);
      // Falls back to localized copy, never the raw grouping tag.
      expect(item.title, S.needsReviewRecordShift);
    });

    test('a stored entry whose operation is gone is never resurfaced',
        () async {
      final c = containerWith(entries: [entryFor('op-vanished')]);

      expect(await itemsOf(c), isEmpty);
    });

    test('is loading until both sources have loaded', () {
      final c = containerWith(operations: [conflicted('op-1')]);

      expect(c.read(needsReviewItemsProvider).isLoading, isTrue);
    });
  });

  group('record labels never leak an internal tag', () {
    test('known domains resolve to Arabic copy', () {
      expect(
        needsReviewRecordLabel(entityType: 'shift', kind: 'shift.assign'),
        S.needsReviewRecordShift,
      );
      expect(
        needsReviewRecordLabel(
            entityType: 'inventory_item', kind: 'inventory.movement.add'),
        S.needsReviewRecordInventory,
      );
      expect(
        needsReviewRecordLabel(entityType: 'team_member', kind: 'team.edit'),
        S.needsReviewRecordMember,
      );
    });

    test('an unmapped domain degrades to safe generic copy', () {
      expect(
        needsReviewRecordLabel(entityType: 'workshop', kind: 'workshop.edit'),
        S.needsReviewRecordGeneric,
      );
    });

    test('a missing entityType falls back to the kind namespace, not the kind',
        () {
      final label = needsReviewRecordLabel(kind: 'shift.attendance.mark');
      expect(label, S.needsReviewRecordShift);
      expect(label, isNot(contains('shift.')));
    });
  });

  group('decisions and the stored entry share one lifetime', () {
    Future<ProviderContainer> resolvedWith(
      ConflictResolutionIntent intent, {
      List<Override> extra = const [],
    }) async {
      final c = containerWith(
        operations: [conflicted('op-1')],
        entries: [entryFor('op-1')],
        extra: extra,
      );
      await itemsOf(c);
      await c.read(conflictDecisionHandlerProvider)(
        ConflictResolutionDecision(
          conflictId: 'op-1',
          localOperationId: 'op-1',
          intent: intent,
          currentVersion: '8',
        ),
      );
      return c;
    }

    test(
        'useLocal supersedes the operation with a new one and forgets its '
        'entry', () async {
      final c = await resolvedWith(ConflictResolutionIntent.useLocal);

      final ops = await c.read(outboxProvider.future);
      expect(ops.single.state, SyncState.pending);
      // §5.5: a brand-new operation, referencing the original — never the
      // same identity requeued.
      expect(ops.single.operationId, isNot('op-1'));
      expect(ops.single.resolvesOperationId, 'op-1');
      expect(await c.read(conflictReviewProvider.future), isEmpty);
      expect(c.read(needsReviewItemsProvider).requireValue, isEmpty);
    });

    test(
        'useCurrent applies the current snapshot, drops the operation, and '
        'forgets its entry', () async {
      final applied = <String>[];
      final c = await resolvedWith(
        ConflictResolutionIntent.useCurrent,
        extra: [
          conflictCurrentAppliersProvider.overrideWithValue({
            'shift': (op) async {
              applied.add(op.operationId);
              return true;
            },
          }),
        ],
      );

      expect(applied, ['op-1']);
      expect(await c.read(outboxProvider.future), isEmpty);
      expect(await c.read(conflictReviewProvider.future), isEmpty);
    });

    test(
        'useCurrent with no registered applier preserves the operation and '
        'its entry — local work is never silently discarded', () async {
      await expectLater(
        resolvedWith(ConflictResolutionIntent.useCurrent),
        throwsA(isA<StateError>()),
      );
    });

    test('reviewLater keeps both, so the row is still on the list', () async {
      final c = await resolvedWith(ConflictResolutionIntent.reviewLater);

      expect((await c.read(outboxProvider.future)).single.state,
          SyncState.conflict);
      final items = c.read(needsReviewItemsProvider).requireValue;
      expect(items.single.conflictId, 'op-1');
      expect(items.single.isReviewable, isTrue);
    });

    test('an unresolved conflict and its metadata survive a relaunch',
        () async {
      final outboxStore = InMemoryOutboxStore(seed: [conflicted('op-1')]);
      final reviewStore = InMemoryConflictReviewStore(seed: [entryFor('op-1')]);

      final first =
          containerWith(outboxStore: outboxStore, reviewStore: reviewStore);
      await first.read(conflictDecisionHandlerProvider)(
        const ConflictResolutionDecision(
          conflictId: 'op-1',
          localOperationId: 'op-1',
          intent: ConflictResolutionIntent.reviewLater,
        ),
      );
      first.dispose();

      // A second container over the same stores models an app relaunch.
      final second =
          containerWith(outboxStore: outboxStore, reviewStore: reviewStore);
      final items = await itemsOf(second);
      expect(items.single.conflictId, 'op-1');
      expect(items.single.entry!.recordTitle, 'الشفت · مركز داريا');
    });
  });

  group('detection stores review metadata without navigating', () {
    ProviderContainer syncing({
      required Map<String, ConflictReviewComposer> composers,
      ConflictReviewStore? reviewStore,
    }) =>
        containerWith(
          operations: [
            PendingOperation.create(
              kind: 'shift.assign',
              entityType: 'shift',
              entityId: 'sh_1',
              idFactory: () => 'op-1',
            ),
          ],
          reviewStore: reviewStore,
          extra: [
            syncTransportProvider.overrideWithValue(
              _Transport(const Failure('conflict', code: _conflictCode)),
            ),
            syncConflictClassifierProvider
                .overrideWithValue((code) => code == _conflictCode),
            conflictReviewComposersProvider.overrideWithValue(composers),
            ...conflictReviewOverrides,
          ],
        );

    test('a classified conflict is recorded through the feature composer',
        () async {
      PendingOperation? seen;
      final c = syncing(composers: {
        'shift': (op) async {
          seen = op;
          return entryFor(op.operationId);
        },
      });
      await c.read(outboxProvider.future);

      final summary = await c
          .read(syncCoordinatorProvider.notifier)
          .syncNow(trigger: SyncTrigger.auto);

      expect(summary.outcome, SyncRunOutcome.needsReview);
      expect(seen!.operationId, 'op-1');
      final items = await itemsOf(c);
      expect(items.single.isReviewable, isTrue);
      expect(items.single.title, 'الشفت · مركز داريا');
    });

    test('no composer for the domain still preserves and counts the conflict',
        () async {
      final c = syncing(composers: const {});
      await c.read(outboxProvider.future);

      await c
          .read(syncCoordinatorProvider.notifier)
          .syncNow(trigger: SyncTrigger.auto);

      expect(c.read(conflictOperationsCountProvider), 1);
      expect(await c.read(conflictReviewProvider.future), isEmpty);
      expect((await itemsOf(c)).single.isReviewable, isFalse);
    });

    test('a composer that throws cannot lose the conflict or fail the run',
        () async {
      final c = syncing(composers: {
        'shift': (op) async => throw StateError('snapshot unavailable'),
      });
      await c.read(outboxProvider.future);

      final summary = await c
          .read(syncCoordinatorProvider.notifier)
          .syncNow(trigger: SyncTrigger.auto);

      expect(summary.outcome, SyncRunOutcome.needsReview);
      final ops = await c.read(outboxProvider.future);
      expect(ops.single.state, SyncState.conflict);
      expect(ops.single.idempotencyKey, 'op-1');
      expect((await itemsOf(c)).single.isReviewable, isFalse);
    });

    test('the default recorder is a no-op, so core sync stores nothing',
        () async {
      final c = containerWith(operations: [
        PendingOperation.create(
          kind: 'shift.assign',
          entityType: 'shift',
          idFactory: () => 'op-1',
        ),
      ], extra: [
        syncTransportProvider.overrideWithValue(
          _Transport(const Failure('conflict', code: _conflictCode)),
        ),
        syncConflictClassifierProvider
            .overrideWithValue((code) => code == _conflictCode),
      ]);
      await c.read(outboxProvider.future);
      expect(c.read(conflictReviewRecorderProvider),
          same(noopConflictReviewRecorder));

      await c
          .read(syncCoordinatorProvider.notifier)
          .syncNow(trigger: SyncTrigger.auto);

      expect(c.read(conflictOperationsCountProvider), 1);
      expect(await c.read(conflictReviewProvider.future), isEmpty);
    });

    test('the shipped composer registry fabricates nothing', () {
      final c = containerWith();
      expect(c.read(conflictReviewComposersProvider), isEmpty);
    });
  });
}
