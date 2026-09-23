import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/access/capability_guard.dart';
import 'package:mtm/core/theme/app_palette.dart';
import 'package:mtm/core/theme/app_theme.dart';
import 'package:mtm/features/detachment/presentation/tabs/detachment_storage_tab.dart';
import 'package:mtm/features/inventory/data/inventory_providers.dart';
import 'package:mtm/features/inventory/data/mock_inventory_repository.dart';
import 'package:mtm/features/inventory/domain/inventory_models.dart';
import 'package:mtm/l10n/strings.dart';

const _item = InventoryItem(
  id: 'i-test',
  detachmentId: 'd-test',
  name: 'شاش طبي',
  unit: 'رول',
  currentStock: 12,
  minimum: 4,
  expiresOn: null,
  level: StockLevel.ok,
);

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required List<InventoryItem> items,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          capabilitiesProvider.overrideWithValue(
            const Capabilities(global: Cap.all),
          ),
          inventoryRepositoryProvider.overrideWithValue(
            MockInventoryRepository(items: items, movements: const []),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(PaletteId.medical),
          home: const Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: DetachmentStorageTab(detachmentId: 'd-test'),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('search with no match is distinct and can be cleared',
      (tester) async {
    await pump(tester, items: const [_item]);
    expect(find.text(_item.name), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('inventory-search')),
      'صنف غير موجود',
    );
    await tester.pump();

    expect(find.byKey(const Key('inventory-no-results')), findsOneWidget);
    expect(find.byKey(const Key('inventory-empty')), findsNothing);
    expect(find.text(_item.name), findsNothing);

    await tester.tap(find.text(S.clearInventoryFilters));
    await tester.pump();
    expect(find.byKey(const Key('inventory-no-results')), findsNothing);
    expect(find.text(_item.name), findsOneWidget);
  });

  testWidgets('a genuinely empty inventory keeps the empty-store state',
      (tester) async {
    await pump(tester, items: const []);
    expect(find.byKey(const Key('inventory-empty')), findsOneWidget);
    expect(find.byKey(const Key('inventory-no-results')), findsNothing);
    expect(find.byKey(const Key('inventory-search')), findsNothing);
  });
}
