import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_coordinator.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/core/sync/sync_transport.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/settings/presentation/widgets/sync_settings_section.dart';
import 'package:mtm/l10n/strings.dart';

/// The Sync Center's dangerous and invisible states (roadmap §6, §16).
///
/// Layout, wording and navigation are checked by hand; what is covered here
/// is what a person cannot see by looking: that one impatient double-tap
/// cannot run two syncs, that a connection lost half-way through keeps the
/// rest of the work, that a failure is preserved and a later retry actually
/// clears it, and that the screen never claims "كل التغييرات متزامنة" while
/// it is still reading the outbox.
class _ScriptedTransport implements SyncTransport {
  _ScriptedTransport(this.answers);

  /// Keyed by operation id, so a test never depends on push ordering.
  final Map<String, Result<void>> answers;
  final List<String> pushed = [];

  @override
  Future<Result<void>> push(PendingOperation operation) async {
    pushed.add(operation.operationId);
    return answers[operation.operationId] ?? const Offline<void>();
  }
}

/// Never answers, so a run stays in flight for as long as a test needs.
class _GatedTransport implements SyncTransport {
  final _gate = Completer<Result<void>>();
  final List<String> pushed = [];

  void release() => _gate.complete(const Success<void>(null));

  @override
  Future<Result<void>> push(PendingOperation operation) {
    pushed.add(operation.operationId);
    return _gate.future;
  }
}

/// An outbox that never finishes being read.
class _HangingStore implements OutboxStore {
  @override
  Future<List<PendingOperation>> readAll() =>
      Completer<List<PendingOperation>>().future;

  @override
  Future<void> remove(String operationId) async {}

  @override
  Future<void> upsert(PendingOperation operation) async {}
}

/// An outbox that cannot be read at all.
class _FailingStore implements OutboxStore {
  @override
  Future<List<PendingOperation>> readAll() async =>
      throw StateError('storage unavailable');

  @override
  Future<void> remove(String operationId) async {}

  @override
  Future<void> upsert(PendingOperation operation) async {}
}

PendingOperation _op(String id,
        {SyncState state = SyncState.pending, String? problem}) =>
    PendingOperation.create(
      kind: 'inventory.movement.add',
      entityType: 'inventory',
      entityId: 'item-1',
      idFactory: () => id,
    ).copyWith(state: state, lastProblemCode: problem);

Future<void> _pump(
  WidgetTester tester, {
  required OutboxStore store,
  required SyncTransport transport,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        outboxStoreProvider.overrideWithValue(store),
        syncTransportProvider.overrideWithValue(transport),
      ],
      child: MaterialApp(
        theme: AppTheme.light(PaletteId.medical),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ListView(children: const [SyncSettingsSection()]),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('two taps in one frame still run one sync', (tester) async {
    final transport = _GatedTransport();
    final store = InMemoryOutboxStore(seed: [_op('a')]);
    await _pump(tester, store: store, transport: transport);
    await tester.pumpAndSettle();

    // Both taps land on the same enabled button: no frame is built between
    // them, so the disabled state cannot be what saves this.
    await tester.tap(find.byKey(const Key('sync-now-button')));
    await tester.tap(find.byKey(const Key('sync-now-button')));
    await tester.pump();

    expect(transport.pushed, ['a'], reason: 'one run, one push');

    transport.release();
    await tester.pumpAndSettle();
    expect(await store.readAll(), isEmpty);
  });

  testWidgets('a second tap while a run is in flight is refused',
      (tester) async {
    final transport = _GatedTransport();
    final store = InMemoryOutboxStore(seed: [_op('a')]);
    await _pump(tester, store: store, transport: transport);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync-now-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sync-now-button')));
    await tester.pump();

    expect(transport.pushed, ['a']);

    transport.release();
    await tester.pumpAndSettle();
  });

  testWidgets(
      'a connection lost half-way keeps the rest of the work and says so',
      (tester) async {
    final transport = _ScriptedTransport({
      'a': const Success<void>(null),
      'b': const Offline<void>(),
    });
    final store = InMemoryOutboxStore(seed: [_op('a'), _op('b')]);
    await _pump(tester, store: store, transport: transport);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync-now-button')));
    await tester.pumpAndSettle();

    // Neither a clean success nor a flat failure.
    expect(find.text(S.syncPartialNote), findsOneWidget);
    expect(find.text(S.syncDoneNote), findsNothing);

    final left = await store.readAll();
    expect(left.map((o) => o.operationId), ['b'],
        reason: 'the change that did not get through is preserved');
    expect(left.single.state, SyncState.failed);
    // And the screen now says the connection is the problem.
    expect(find.byKey(const Key('sync-connection-offline')), findsOneWidget);
    expect(find.byKey(const Key('sync-needs-internet')), findsOneWidget);
  });

  testWidgets('a failed change is counted as failed, not as waiting',
      (tester) async {
    final store = InMemoryOutboxStore(seed: [
      _op('a', state: SyncState.failed, problem: 'server'),
      _op('b'),
    ]);
    await _pump(tester, store: store, transport: _ScriptedTransport(const {}));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync-count-failed')), findsOneWidget);
    expect(find.text(S.syncFailedOne), findsOneWidget);
    expect(find.byKey(const Key('sync-count-waiting')), findsOneWidget);
    expect(find.text(S.syncPendingOne), findsOneWidget);
  });

  testWidgets('retrying a failed change clears it and refreshes the status',
      (tester) async {
    final store = InMemoryOutboxStore(
      seed: [_op('a', state: SyncState.failed, problem: 'server')],
    );
    await _pump(
      tester,
      store: store,
      transport: _ScriptedTransport({'a': const Success<void>(null)}),
    );
    await tester.pumpAndSettle();

    // With nothing waiting and only a failure outstanding, the one button
    // says what it will actually do.
    expect(find.text(S.retry), findsOneWidget);
    expect(find.text(S.syncNow), findsNothing);

    await tester.tap(find.byKey(const Key('sync-now-button')));
    await tester.pumpAndSettle();

    expect(find.text(S.syncDoneNote), findsOneWidget);
    expect(await store.readAll(), isEmpty);
    // The status is re-read after the run rather than left as it was.
    expect(find.byKey(const Key('sync-count-failed')), findsNothing);
    expect(find.text(S.syncAllSynced), findsOneWidget);
    expect(find.byKey(const Key('sync-connection-online')), findsOneWidget);
  });

  testWidgets('a retry that fails again preserves the change and stays honest',
      (tester) async {
    final store = InMemoryOutboxStore(
      seed: [_op('a', state: SyncState.failed, problem: 'server')],
    );
    await _pump(
      tester,
      store: store,
      transport: _ScriptedTransport(
        {'a': const Failure<void>('boom', code: 'server')},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sync-now-button')));
    await tester.pumpAndSettle();

    expect(find.text(S.syncFailedNote), findsOneWidget);
    final left = await store.readAll();
    expect(left.single.operationId, 'a');
    expect(left.single.state, SyncState.failed);
    expect(find.text(S.syncHeadlineFailed), findsOneWidget);
  });

  testWidgets('the outbox being read is never reported as "all synced"',
      (tester) async {
    await _pump(
      tester,
      store: _HangingStore(),
      transport: _ScriptedTransport(const {}),
    );
    await tester.pump();

    expect(find.byKey(const Key('sync-status-loading')), findsOneWidget);
    expect(find.text(S.syncAllSynced), findsNothing);
    expect(find.byKey(const Key('sync-now-button')), findsNothing);
  });

  testWidgets('an unreadable outbox is a designed state, not an empty card',
      (tester) async {
    await _pump(
      tester,
      store: _FailingStore(),
      transport: _ScriptedTransport(const {}),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('sync-status-error')), findsOneWidget);
    expect(find.text(S.syncLoadFailedBody), findsOneWidget);
    expect(find.text(S.syncAllSynced), findsNothing);
    // The one action that can help, and nothing that pretends to sync.
    expect(find.byKey(const Key('sync-status-retry')), findsOneWidget);
    expect(find.byKey(const Key('sync-now-button')), findsNothing);
  });

  testWidgets('never synced is stated plainly, not shown as a failure',
      (tester) async {
    await _pump(
      tester,
      store: InMemoryOutboxStore(),
      transport: _ScriptedTransport(const {}),
    );
    await tester.pumpAndSettle();

    expect(find.text(S.syncNever), findsOneWidget);
    expect(find.text(S.syncAllSynced), findsOneWidget);
  });
}
