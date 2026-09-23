import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_conflict_classifier.dart';
import 'package:mtm/core/sync/sync_coordinator.dart';
import 'package:mtm/core/sync/sync_scheduler.dart';
import 'package:mtm/core/sync/sync_state.dart';
import 'package:mtm/core/sync/sync_transport.dart';

const _staleWriteTestCode = 'test_only_stale_write';

class _ConflictTransport implements SyncTransport {
  @override
  Future<Result<void>> push(PendingOperation operation) async =>
      const Failure<void>('stale', code: _staleWriteTestCode);
}

void main() {
  testWidgets(
      '4. Auto Sync detects a conflict without navigating the user away',
      (tester) async {
    final store = InMemoryOutboxStore();
    final container = ProviderContainer(overrides: [
      outboxStoreProvider.overrideWithValue(store),
      syncTransportProvider.overrideWithValue(_ConflictTransport()),
      syncConflictClassifierProvider
          .overrideWithValue((code) => code == _staleWriteTestCode),
    ]);
    addTearDown(container.dispose);

    await container
        .read(outboxProvider.notifier)
        .enqueue(kind: 'shift.assign', entityId: 'sh_1');

    // A minimal router standing in for `app_router.dart`'s real
    // `/conflicts/:conflictId` route — enough to prove Auto Sync never
    // navigates there, without needing the whole app's auth/upgrade wiring.
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, __) => const Scaffold(body: Text('home-screen')),
        ),
        GoRoute(
          path: '/conflicts/:conflictId',
          builder: (_, __) => const Scaffold(body: Text('conflict-screen')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('home-screen'), findsOneWidget);

    // The real Auto Sync trigger path (`main.dart` calls the same
    // `SyncScheduler.request()` on launch and on every resume).
    await container.read(syncSchedulerProvider).request();
    await tester.pumpAndSettle();

    // Still on /home — Auto Sync never pushed the conflict route.
    expect(find.text('home-screen'), findsOneWidget);
    expect(find.text('conflict-screen'), findsNothing);

    // Not a vacuous pass: the conflict really was detected and classified.
    final stored = (await store.readAll()).single;
    expect(stored.state, SyncState.conflict);
  });
}
