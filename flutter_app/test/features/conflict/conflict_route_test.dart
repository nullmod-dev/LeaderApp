import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/conflict/data/conflict_review_controller.dart';
import 'package:mtm/features/conflict/data/in_memory_conflict_review_store.dart';
import 'package:mtm/features/conflict/domain/conflict_models.dart';
import 'package:mtm/features/conflict/domain/conflict_review_entry.dart';
import 'package:mtm/features/conflict/presentation/conflict_resolution_page.dart';
import 'package:mtm/features/conflict/presentation/conflict_resolution_route.dart';
import 'package:mtm/l10n/strings.dart';

/// Entering `/conflicts/:conflictId` without the typed arguments that
/// normally come with it — a restored deep link, a relaunch onto a saved
/// location (roadmap §7, §16.10, §16.11).
///
/// The rule: rebuild the conflict from the one place conflicts live, or say
/// it is not available. Never fabricate a comparison, never crash.
void main() {
  const conflictId = 'op-1';

  ConflictReviewEntry entry() => ConflictReviewEntry(
        conflictId: conflictId,
        entityType: 'shift',
        entityId: 'sh_1',
        recordTitle: 'الشفت · مركز داريا',
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

  PendingOperation op({SyncState state = SyncState.conflict}) =>
      PendingOperation.create(
        kind: 'shift.assign',
        entityType: 'shift',
        entityId: 'sh_1',
        idFactory: () => conflictId,
      ).copyWith(state: state);

  Future<void> pump(
    WidgetTester tester, {
    required String? id,
    List<PendingOperation> operations = const [],
    List<ConflictReviewEntry> entries = const [],
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        outboxStoreProvider
            .overrideWithValue(InMemoryOutboxStore(seed: operations)),
        conflictReviewStoreProvider
            .overrideWithValue(InMemoryConflictReviewStore(seed: entries)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ConflictResolutionRoute(conflictId: id),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a still-waiting conflict is rebuilt from what is stored',
      (tester) async {
    await pump(
      tester,
      id: conflictId,
      operations: [op()],
      entries: [entry()],
    );

    expect(find.byType(ConflictResolutionPage), findsOneWidget);
    expect(find.text(S.conflictTitle), findsOneWidget);
    expect(find.text(entry().recordTitle), findsOneWidget);
  });

  testWidgets('a conflict that has since been resolved is not fabricated',
      (tester) async {
    // Metadata left over, but nothing is waiting on a decision any more.
    await pump(tester,
        id: conflictId, operations: const [], entries: [entry()]);

    expect(find.byType(ConflictUnavailablePage), findsOneWidget);
    expect(find.text(S.conflictUnavailableTitle), findsOneWidget);
  });

  testWidgets('a conflict with nothing safe to compare is not opened',
      (tester) async {
    await pump(tester, id: conflictId, operations: [op()], entries: const []);

    expect(find.byType(ConflictUnavailablePage), findsOneWidget);
    expect(find.byType(ConflictResolutionPage), findsNothing);
  });

  testWidgets('an unknown or missing id lands somewhere safe', (tester) async {
    await pump(tester, id: 'not-a-conflict', operations: [
      op()
    ], entries: [
      entry(),
    ]);
    expect(find.byType(ConflictUnavailablePage), findsOneWidget);

    await pump(tester, id: null);
    expect(find.byType(ConflictUnavailablePage), findsOneWidget);
  });
}
