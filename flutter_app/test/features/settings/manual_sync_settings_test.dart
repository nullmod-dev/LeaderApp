import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_conflict_classifier.dart';
import 'package:mtm/core/sync/sync_coordinator.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/core/sync/sync_transport.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/settings/presentation/widgets/sync_settings_section.dart';
import 'package:mtm/l10n/strings.dart';

class _Transport implements SyncTransport {
  _Transport(this.answer);
  Result<void> answer;
  @override
  Future<Result<void>> push(PendingOperation operation) async => answer;
}

Future<void> _pump(
  WidgetTester tester, {
  required OutboxStore store,
  required SyncTransport transport,
  VoidCallback? onSiblingTap,
  List<Override> extraOverrides = const [],
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        outboxStoreProvider.overrideWithValue(store),
        syncTransportProvider.overrideWithValue(transport),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ListView(
              children: [
                const SyncSettingsSection(),
                TextButton(
                  key: const Key('sibling-nav'),
                  onPressed: onSiblingTap ?? () {},
                  child: const Text('nav'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders the manual sync control and an all-synced state in RTL',
      (tester) async {
    await _pump(tester,
        store: InMemoryOutboxStore(), transport: _Transport(const Offline()));
    await tester.pumpAndSettle();

    expect(find.text(S.syncNow), findsOneWidget);
    expect(find.text(S.syncStatusLabel), findsOneWidget);
    expect(
      tester
          .widget<Directionality>(
            find
                .ancestor(
                  of: find.byType(SyncSettingsSection),
                  matching: find.byType(Directionality),
                )
                .first,
          )
          .textDirection,
      TextDirection.rtl,
    );
    expect(find.text(S.syncAllSynced), findsWidgets);
  });

  testWidgets('shows a pending count when work is waiting', (tester) async {
    final store = InMemoryOutboxStore(seed: [
      PendingOperation.create(
          kind: 'inventory.movement.add', idFactory: () => 'a'),
      PendingOperation.create(
          kind: 'inventory.movement.add', idFactory: () => 'b'),
    ]);
    await _pump(tester, store: store, transport: _Transport(const Offline()));
    await tester.pumpAndSettle();

    expect(
      find.text(S.syncPendingMany.replaceFirst('%d', '٢')),
      findsOneWidget,
    );
  });

  testWidgets(
      'manual sync with only a provisional transport shows no fake success',
      (tester) async {
    final store = InMemoryOutboxStore(seed: [
      PendingOperation.create(
          kind: 'inventory.movement.add', idFactory: () => 'a'),
    ]);
    await _pump(tester, store: store, transport: _Transport(const Offline()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync-now-button')));
    await tester.pump(); // start the run
    await tester.pumpAndSettle(); // finish it

    // The honest offline note, never S.syncDoneNote.
    expect(find.text(S.syncOfflineNote), findsOneWidget);
    expect(find.text(S.syncDoneNote), findsNothing);
    // The operation is still pending.
    expect(await store.readAll(), hasLength(1));
  });

  testWidgets('a real success drains the outbox and reports it',
      (tester) async {
    final store = InMemoryOutboxStore(seed: [
      PendingOperation.create(
          kind: 'inventory.movement.add', idFactory: () => 'a'),
    ]);
    await _pump(tester,
        store: store, transport: _Transport(const Success<void>(null)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync-now-button')));
    await tester.pumpAndSettle();

    expect(find.text(S.syncDoneNote), findsOneWidget);
    expect(await store.readAll(), isEmpty);
  });

  testWidgets('a running sync disables its own button but not sibling nav',
      (tester) async {
    var siblingTaps = 0;
    // A transport that never completes keeps the run in flight.
    final never = _NeverTransport();
    final store = InMemoryOutboxStore(seed: [
      PendingOperation.create(
          kind: 'inventory.movement.add', idFactory: () => 'a'),
    ]);
    await _pump(tester,
        store: store, transport: never, onSiblingTap: () => siblingTaps++);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync-now-button')));
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text(S.syncNow),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull, reason: 'sync button is busy');

    await tester.tap(find.byKey(const Key('sibling-nav')));
    expect(siblingTaps, 1, reason: 'the rest of Settings still navigates');

    never.complete();
    await tester.pumpAndSettle();
  });

  // ---- Task 2: conflict/review attention state ----

  testWidgets(
      '6+7. shows the conflict attention row and count, and Settings stays '
      'usable while conflicts exist', (tester) async {
    var siblingTaps = 0;
    final store = InMemoryOutboxStore(seed: [
      PendingOperation.create(
          kind: 'inventory.movement.add',
          idFactory: () => 'pending-1').copyWith(state: SyncState.pending),
      PendingOperation.create(kind: 'shift.assign', idFactory: () => 'c1')
          .copyWith(state: SyncState.conflict),
      PendingOperation.create(kind: 'shift.assign', idFactory: () => 'c2')
          .copyWith(state: SyncState.conflict),
    ]);
    await _pump(tester,
        store: store,
        transport: _Transport(const Offline()),
        onSiblingTap: () => siblingTaps++);
    await tester.pumpAndSettle();

    // Two conflicts, shown distinctly from the one still-pending operation.
    expect(find.byKey(const Key('sync-conflict-attention')), findsOneWidget);
    expect(
      find.text(S.syncReviewMany.replaceFirst('%d', '٢')),
      findsOneWidget,
    );
    expect(find.text(S.syncPendingOne), findsOneWidget,
        reason: 'the sync-pending count must not include the conflicts');

    // The rest of Settings — the sync button and sibling navigation — stays
    // usable while conflicts are outstanding.
    expect(
      tester
          .widget<FilledButton>(find.ancestor(
            of: find.text(S.syncNow),
            matching: find.byType(FilledButton),
          ))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('sibling-nav')));
    expect(siblingTaps, 1);
  });

  testWidgets('no attention row when nothing needs review', (tester) async {
    final store = InMemoryOutboxStore(seed: [
      PendingOperation.create(
          kind: 'inventory.movement.add', idFactory: () => 'a'),
    ]);
    await _pump(tester, store: store, transport: _Transport(const Offline()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync-conflict-attention')), findsNothing);
  });

  testWidgets(
      'a manual sync run that hits a conflict reports the honest review note',
      (tester) async {
    const staleCode = 'test_only_stale_write';
    final store = InMemoryOutboxStore(seed: [
      PendingOperation.create(kind: 'shift.assign', idFactory: () => 'c1'),
    ]);
    await _pump(
      tester,
      store: store,
      transport: _Transport(const Failure('stale', code: staleCode)),
      extraOverrides: [
        syncConflictClassifierProvider
            .overrideWithValue((code) => code == staleCode),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync-now-button')));
    await tester.pumpAndSettle();

    expect(find.text(S.syncNeedsReviewNote), findsOneWidget);
    expect(find.text(S.syncFailedNote), findsNothing);
    final stored = (await store.readAll()).single;
    expect(stored.state, SyncState.conflict);
  });
}

class _NeverTransport implements SyncTransport {
  final _gate = Completer<Result<void>>();
  void complete() => _gate.complete(const Offline<void>());

  @override
  Future<Result<void>> push(PendingOperation operation) => _gate.future;
}
