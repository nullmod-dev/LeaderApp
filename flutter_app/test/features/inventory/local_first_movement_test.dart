import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/sync/outbox_controller.dart';
import 'package:mtm/core/sync/outbox_store.dart';
import 'package:mtm/core/sync/pending_operation.dart';
import 'package:mtm/core/sync/sync_coordinator.dart';
import 'package:mtm/core/sync/sync_transport.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/inventory/data/inventory_providers.dart';
import 'package:mtm/features/inventory/domain/inventory_models.dart';
import 'package:mtm/features/inventory/domain/inventory_repository.dart';
import 'package:mtm/features/detachment/presentation/tabs/detachment_storage_tab.dart';
import 'package:mtm/l10n/strings.dart';

/// The representative local-first integration: recording a stock movement
/// stores it locally *and* registers one pending sync operation, without
/// waiting on (or having) a server.

/// Zero-latency in-memory inventory so the tab paints its content on the
/// first frame (no infinite loading shimmer to fight in the pump loop).
class _FastInventory implements InventoryRepository {
  final _items = <InventoryItem>[
    const InventoryItem(
      id: 'i1',
      detachmentId: 'd_dam_central',
      name: 'أدرينالين ١ ملغ/مل',
      unit: 'أمبولة',
      currentStock: 10,
      minimum: 4,
      expiresOn: null,
      level: StockLevel.ok,
    ),
  ];
  final _movements = <InventoryMovement>[];

  @override
  Future<Result<List<InventoryItem>>> listForDetachment(String d) async =>
      Success(_items.where((i) => i.detachmentId == d).toList());

  @override
  Future<Result<InventoryItem>> byId(String id) async =>
      Success(_items.firstWhere((i) => i.id == id));

  @override
  Future<Result<List<InventoryMovement>>> movementsForItem(String id) async =>
      Success(_movements.where((m) => m.itemId == id).toList());

  @override
  Future<Result<InventoryItem>> addMovement({
    required String itemId,
    required MovementDirection direction,
    required int quantity,
    required String reason,
    PackagingUnit packagingUnit = PackagingUnit.individual,
    String? source,
    String? performedBy,
    String? performedByName,
  }) async {
    final idx = _items.indexWhere((i) => i.id == itemId);
    final before = _items[idx];
    final delta = direction == MovementDirection.inflow ? quantity : -quantity;
    _items[idx] = before.copyWith(currentStock: before.currentStock + delta);
    _movements.add(InventoryMovement(
      id: 'mv${_movements.length}',
      itemId: itemId,
      direction: direction,
      quantity: quantity,
      reason: reason,
      at: DateTime(2026, 9, 4),
    ));
    return Success(_items[idx]);
  }

  @override
  Future<Result<InventoryItem>> create({
    required String detachmentId,
    required String name,
    required String unit,
    required int openingStock,
    required int minimum,
    PackagingUnit openingUnit = PackagingUnit.individual,
    int unitsPerStrip = 1,
    int stripsPerCarton = 1,
    DateTime? expiresOn,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Result<InventoryItem>> update({
    required String id,
    required String name,
    required String unit,
    required int minimum,
    int? unitsPerStrip,
    int? stripsPerCarton,
    PackagingUnit? preferredUnit,
    DateTime? expiresOn,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Result<void>> delete(String id) async => throw UnimplementedError();
}

class _RejectingTransport implements SyncTransport {
  int pushes = 0;
  @override
  Future<Result<void>> push(PendingOperation operation) async {
    pushes++;
    return const Offline<void>();
  }
}

void main() {
  testWidgets(
      'recording a movement writes locally and enqueues exactly one '
      'pending operation — no server needed', (tester) async {
    final store = InMemoryOutboxStore();
    final transport = _RejectingTransport();
    final inventory = _FastInventory();
    final container = ProviderContainer(overrides: [
      capabilitiesProvider
          .overrideWithValue(const Capabilities(global: Cap.all)),
      inventoryRepositoryProvider.overrideWithValue(inventory),
      outboxStoreProvider.overrideWithValue(store),
      syncTransportProvider.overrideWithValue(transport),
    ]);
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/d',
      routes: [
        GoRoute(
          path: '/d',
          builder: (context, state) => const Scaffold(
            body: DetachmentStorageTab(detachmentId: 'd_dam_central'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light(PaletteId.medical),
        routerConfig: router,
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // Open the item sheet.
    await tester.tap(find.text('أدرينالين ١ ملغ/مل').first);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.widgetWithText(FilledButton, S.record), findsOneWidget,
        reason: 'the record-movement sheet is open');

    // Quantity (the sheet field, not the list search box) + record.
    // Default direction is outflow.
    await tester.enterText(find.widgetWithText(TextField, S.quantity), '2');
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.widgetWithText(FilledButton, S.record));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // 1. The write landed locally: stock moved 10 -> 8.
    final after = (await inventory.byId('i1')).when(
      success: (d, {stale = false}) => d,
      failure: (m, c) => fail('$m ($c)'),
      offline: (_) => fail('offline'),
    );
    expect(after.currentStock, 8);

    // 2. Exactly one pending operation, describing the movement — no payload.
    final ops = await store.readAll();
    expect(ops, hasLength(1));
    expect(ops.single.kind, 'inventory.movement.add');
    expect(ops.single.entityType, 'inventory_item');
    expect(ops.single.entityId, 'i1');
    expect(container.read(pendingOperationsCountProvider), 1);

    // 3. The user was told, honestly, that it still has to sync.
    expect(find.text(S.savedPendingSync), findsOneWidget);

    // 4. A background sync was nudged, but the local write never waited on
    //    it (the transport only ever returns Offline).
    expect(transport.pushes, greaterThanOrEqualTo(1));
    expect((await store.readAll()).single.isUnsynced, isTrue);
  });
}
