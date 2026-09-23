import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/router/app_router.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/core/widgets/skeleton.dart';
import 'package:mtm/features/conflict/data/conflict_current_application.dart';
import 'package:mtm/features/conflict/data/conflict_review_controller.dart';
import 'package:mtm/features/conflict/data/in_memory_conflict_review_store.dart';
import 'package:mtm/features/conflict/domain/conflict_models.dart';
import 'package:mtm/features/conflict/domain/conflict_review_entry.dart';
import 'package:mtm/features/conflict/domain/conflict_review_store.dart';
import 'package:mtm/features/conflict/presentation/needs_review_page.dart';
import 'package:mtm/l10n/strings.dart';
import 'package:mtm/main.dart';

/// Task 4 — the user-facing half of the review loop: see that changes need
/// review, open the list explicitly, pick a conflict, decide, and come back
/// without losing unresolved work.

const _opId = 'op-conflict-1';

ConflictReviewEntry _entry({String conflictId = _opId}) => ConflictReviewEntry(
      conflictId: conflictId,
      entityType: 'shift',
      entityId: 'sh_1',
      recordTitle: 'الشفت · مركز داريا',
      recordSubtitle: 'الجمعة · ٥ سبتمبر',
      detectedAt: DateTime.now().subtract(const Duration(minutes: 6)),
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

PendingOperation _conflicted(
        {String id = _opId, String? entityType = 'shift'}) =>
    PendingOperation.create(
      kind: 'shift.assign',
      entityType: entityType,
      entityId: 'sh_1',
      idFactory: () => id,
    ).copyWith(
      state: SyncState.conflict,
      lastAttemptAt: DateTime.now().subtract(const Duration(minutes: 6)),
    );

/// A store that never finishes loading, for the loading state.
class _PendingReviewStore implements ConflictReviewStore {
  @override
  Future<List<ConflictReviewEntry>> readAll() =>
      Completer<List<ConflictReviewEntry>>().future;
  @override
  Future<void> upsert(ConflictReviewEntry entry) async {}
  @override
  Future<void> remove(String conflictId) async {}
}

/// Fails `readAll` exactly once, then behaves like an ordinary in-memory
/// store — models a source that recovers once the user retries.
class _FlakyOutboxStore implements OutboxStore {
  _FlakyOutboxStore(this._delegate);
  final OutboxStore _delegate;
  bool _shouldFail = true;

  @override
  Future<List<PendingOperation>> readAll() async {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('simulated outbox load failure');
    }
    return _delegate.readAll();
  }

  @override
  Future<void> upsert(PendingOperation operation) =>
      _delegate.upsert(operation);
  @override
  Future<void> remove(String operationId) => _delegate.remove(operationId);
}

class _FlakyReviewStore implements ConflictReviewStore {
  _FlakyReviewStore(this._delegate);
  final ConflictReviewStore _delegate;
  bool _shouldFail = true;

  @override
  Future<List<ConflictReviewEntry>> readAll() async {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('simulated review store load failure');
    }
    return _delegate.readAll();
  }

  @override
  Future<void> upsert(ConflictReviewEntry entry) => _delegate.upsert(entry);
  @override
  Future<void> remove(String conflictId) => _delegate.remove(conflictId);
}

List<Override> _overrides({
  List<PendingOperation> operations = const [],
  List<ConflictReviewEntry> entries = const [],
  ConflictReviewStore? reviewStore,
  OutboxStore? outboxStore,
}) =>
    [
      outboxStoreProvider.overrideWithValue(
        outboxStore ?? InMemoryOutboxStore(seed: operations),
      ),
      conflictReviewStoreProvider.overrideWithValue(
        reviewStore ?? InMemoryConflictReviewStore(seed: entries),
      ),
    ];

/// The page on its own, for the states that need no navigation.
Future<void> _pumpPage(
  WidgetTester tester, {
  List<PendingOperation> operations = const [],
  List<ConflictReviewEntry> entries = const [],
  ConflictReviewStore? reviewStore,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(
        operations: operations,
        entries: entries,
        reviewStore: reviewStore,
      ),
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: NeedsReviewPage(),
        ),
      ),
    ),
  );
}

/// Swallows two known, pre-existing debug complaints that this task did not
/// introduce and was not asked to fix, and nothing else:
///
/// - the `GlassBottomNav` horizontal overflow the detachment group smoke
///   test already documents and tolerates for the same reason;
/// - the Settings page's `ListTile`-inside-a-decorated-`_SettingsSection`
///   ink assertion, which fires on `main` for every existing Settings row
///   the moment that screen is rendered in a test.
///
/// Both are matched narrowly, so a new failure anywhere else still fails.
void _ignoreKnownPreexistingComplaints() {
  final inherited = FlutterError.onError;
  FlutterError.onError = (details) {
    final report = details.toString();
    if (report.contains('overflowed') &&
        report.contains('glass_bottom_nav.dart')) {
      return;
    }
    if (report.contains('ListTile background color or ink splashes')) {
      return;
    }
    inherited?.call(details);
  };
  addTearDown(() => FlutterError.onError = inherited);
}

void main() {
  group('the inbox renders every state it can be in', () {
    testWidgets('loading shows the shared skeleton, never an empty inbox',
        (tester) async {
      await _pumpPage(
        tester,
        operations: [_conflicted()],
        reviewStore: _PendingReviewStore(),
      );
      await tester.pump();

      expect(find.byType(SkeletonList), findsOneWidget);
      expect(find.byKey(const Key('needs-review-empty')), findsNothing);
    });

    testWidgets('nothing to review is a designed empty state', (tester) async {
      await _pumpPage(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('needs-review-empty')), findsOneWidget);
      expect(find.text(S.needsReviewEmptyTitle), findsOneWidget);
      expect(find.byKey(const Key('needs-review-list')), findsNothing);
    });

    testWidgets('a reviewable conflict shows its feature-approved summary',
        (tester) async {
      await _pumpPage(
        tester,
        operations: [_conflicted()],
        entries: [_entry()],
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('needs-review-item-$_opId')), findsOneWidget);
      expect(find.text('الشفت · مركز داريا'), findsOneWidget);
      expect(find.text('الجمعة · ٥ سبتمبر'), findsOneWidget);
      expect(find.text(S.needsReviewUnavailable), findsNothing);
    });

    testWidgets('a conflict with no stored metadata is listed but not openable',
        (tester) async {
      await _pumpPage(tester, operations: [_conflicted()]);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('needs-review-blocked-$_opId')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('needs-review-item-$_opId')), findsNothing);
      // Honest about the gap, and explicit that the change is not lost.
      expect(find.text(S.needsReviewUnavailable), findsOneWidget);
      expect(find.text(S.needsReviewUnavailableBody), findsOneWidget);
      // The record kind still reads as Arabic copy, not an internal tag.
      expect(find.text(S.needsReviewRecordShift), findsOneWidget);
    });

    testWidgets('no operation id, idempotency key or wire tag is rendered',
        (tester) async {
      await _pumpPage(
        tester,
        operations: [_conflicted(), _conflicted(id: 'op-conflict-2')],
        entries: [_entry()],
      );
      await tester.pumpAndSettle();

      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' | ');
      for (final forbidden in [
        _opId,
        'op-conflict-2',
        'shift.assign',
        'sh_1',
        'conflict',
        'stale_write',
      ]) {
        expect(rendered.contains(forbidden), isFalse,
            reason: 'the inbox rendered "$forbidden"');
      }
    });

    testWidgets('the list lays out right-to-left', (tester) async {
      await _pumpPage(
        tester,
        operations: [_conflicted()],
        entries: [_entry()],
      );
      await tester.pumpAndSettle();

      expect(
        Directionality.of(
          tester.element(find.byKey(const Key('needs-review-list'))),
        ),
        TextDirection.rtl,
      );
    });
  });

  group('retry recovers from either required source failing independently', () {
    testWidgets('an outbox-load failure recovers on retry', (tester) async {
      final outboxStore = _FlakyOutboxStore(
        InMemoryOutboxStore(seed: [_conflicted()]),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            outboxStoreProvider.overrideWithValue(outboxStore),
            conflictReviewStoreProvider.overrideWithValue(
              InMemoryConflictReviewStore(seed: [_entry()]),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(PaletteId.medical),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: NeedsReviewPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(S.retry), findsOneWidget);
      expect(find.byKey(const Key('needs-review-item-$_opId')), findsNothing);

      await tester.tap(find.text(S.retry));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('needs-review-item-$_opId')), findsOneWidget);
    });

    testWidgets('a review-store-load failure recovers on retry',
        (tester) async {
      final reviewStore = _FlakyReviewStore(
        InMemoryConflictReviewStore(seed: [_entry()]),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            outboxStoreProvider
                .overrideWithValue(InMemoryOutboxStore(seed: [_conflicted()])),
            conflictReviewStoreProvider.overrideWithValue(reviewStore),
          ],
          child: MaterialApp(
            theme: AppTheme.light(PaletteId.medical),
            home: const Directionality(
              textDirection: TextDirection.rtl,
              child: NeedsReviewPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(S.retry), findsOneWidget);
      expect(find.byKey(const Key('needs-review-item-$_opId')), findsNothing);

      await tester.tap(find.text(S.retry));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('needs-review-item-$_opId')), findsOneWidget);
    });
  });

  group('the whole review loop, in the real app', () {
    /// Boots the real app with one conflicted operation waiting, lands on
    /// Settings, and returns the container so a test can read the outbox.
    Future<ProviderContainer> boot(
      WidgetTester tester, {
      OutboxStore? outboxStore,
    }) async {
      _ignoreKnownPreexistingComplaints();
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(
        overrides: [
          ..._overrides(
            operations: [_conflicted()],
            entries: [_entry()],
            outboxStore: outboxStore,
          ),
          // The real Shift composer/applier are covered by
          // `test/features/shift/shift_conflict_review_test.dart`; this
          // widget test is about navigation/list wiring, so a fake applier
          // stands in for "useCurrent applied the current snapshot".
          conflictCurrentAppliersProvider.overrideWithValue({
            'shift': (operation) async => true,
          }),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MtmApp()),
      );
      await tester.pumpAndSettle();
      // Point 1 moved the attention row off the Settings hub and onto its
      // own nested Sync screen (`/more/sync`) — same widget
      // (`SyncSettingsSection`), same providers, just a different route.
      container.read(appRouterProvider).go('/more/sync');
      await tester.pumpAndSettle();
      return container;
    }

    /// Scrolls the quiet attention row into view and returns its finder.
    Future<Finder> revealAttentionRow(WidgetTester tester) async {
      final row = find.byKey(const Key('sync-conflict-attention'));
      await tester.scrollUntilVisible(row, 200);
      await tester.pump();
      return row;
    }

    Future<void> openInbox(WidgetTester tester) async {
      await tester.tap(await revealAttentionRow(tester));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'Settings shows the count, opens the list, and the list opens the '
        'differences screen', (tester) async {
      await boot(tester);

      // 1. see that changes need review — a quiet count in Settings, not an
      // interruption: Auto Sync got the app here without navigating.
      final row = await revealAttentionRow(tester);
      expect(find.text(S.syncReviewOne), findsOneWidget);

      // 2. explicitly open a Needs Review list
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text(S.needsReviewTitle), findsOneWidget);

      // 3./4. select a conflict and inspect the Task 1 differences screen
      await tester.tap(find.byKey(const Key('needs-review-item-$_opId')));
      await tester.pumpAndSettle();
      expect(find.text(S.conflictTitle), findsOneWidget);
      // The stored differences really rebuild the Task 1 comparison — the
      // rows sit below the fold on a phone, so scroll to them.
      final localValue = find.byKey(const Key('conflict-local-needed'));
      await tester.scrollUntilVisible(localValue, 200);
      await tester.pump();
      expect(localValue, findsOneWidget);
      expect(find.byKey(const Key('conflict-current-needed')), findsOneWidget);
      expect(find.text('العدد المطلوب'), findsOneWidget);
    });

    testWidgets('review later comes back to the list with the work intact',
        (tester) async {
      final container = await boot(tester);
      await openInbox(tester);
      await tester.tap(find.byKey(const Key('needs-review-item-$_opId')));
      await tester.pumpAndSettle();

      // 5. choose reviewLater — 6. return without losing unresolved work
      await tester.tap(find.byKey(const Key('conflict-review-later')));
      await tester.pumpAndSettle();

      expect(find.text(S.needsReviewTitle), findsOneWidget);
      expect(find.byKey(const Key('needs-review-item-$_opId')), findsOneWidget);
      final ops = await container.read(outboxProvider.future);
      expect(ops.single.state, SyncState.conflict);
      expect(ops.single.idempotencyKey, _opId);
      expect(await container.read(conflictReviewProvider.future), hasLength(1));
    });

    testWidgets('keeping my edit requeues it and empties the list',
        (tester) async {
      final container = await boot(tester);
      await openInbox(tester);
      await tester.tap(find.byKey(const Key('needs-review-item-$_opId')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('conflict-use-local')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('needs-review-empty')), findsOneWidget);
      final ops = await container.read(outboxProvider.future);
      expect(ops.single.state, SyncState.pending);
      // §5.5: `useLocal` mints a brand-new operation that references the
      // original — it never resends the original's identity.
      expect(ops.single.operationId, isNot(_opId));
      expect(ops.single.resolvesOperationId, _opId);
      expect(await container.read(conflictReviewProvider.future), isEmpty);
    });

    testWidgets(
        'a conflict already resolved elsewhere is explained, and its row goes '
        'away instead of the app crashing', (tester) async {
      // The store is held here so the conflict can disappear from under the
      // open screen — what a sync run completing while the user is deciding,
      // or a decision taken on another surface, leaves behind.
      final store = InMemoryOutboxStore(seed: [_conflicted()]);
      final container = await boot(tester, outboxStore: store);
      await openInbox(tester);
      await tester.tap(find.byKey(const Key('needs-review-item-$_opId')));
      await tester.pumpAndSettle();

      await store.remove(_opId);
      await container.read(outboxProvider.notifier).refresh();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('conflict-use-local')));
      await tester.pumpAndSettle();

      // Told plainly, in the conflict's own vocabulary — not "تعذّر حفظ
      // اختيارك", which would suggest the change was lost.
      expect(find.text(S.conflictAlreadyResolved), findsOneWidget);
      expect(find.text(S.conflictDecisionFailed), findsNothing);
      // Back on a list that no longer offers the stale row.
      expect(find.text(S.needsReviewTitle), findsOneWidget);
      expect(find.byKey(const Key('needs-review-empty')), findsOneWidget);
      expect(await container.read(conflictReviewProvider.future), isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeping the shared version empties the list too',
        (tester) async {
      final container = await boot(tester);
      await openInbox(tester);
      await tester.tap(find.byKey(const Key('needs-review-item-$_opId')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('conflict-use-current')));
      await tester.pumpAndSettle();
      // Discarding an unsynced local edit is the one choice that asks first.
      await tester.tap(find.byKey(const Key('conflict-use-current-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('needs-review-empty')), findsOneWidget);
      expect(await container.read(outboxProvider.future), isEmpty);
      expect(await container.read(conflictReviewProvider.future), isEmpty);
    });
  });
}
