import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/inventory/data/mock_inventory_repository.dart';
import 'package:mtm/features/inventory/domain/inventory_models.dart';

T _success<T>(Result<T> result) => result.when(
      success: (data, {stale = false}) => data,
      failure: (message, code) => fail('$message ($code)'),
      offline: (_) => fail('offline'),
    );

String? _code<T>(Result<T> result) => result.when(
      success: (_, {stale = false}) => null,
      failure: (_, code) => code,
      offline: (_) => 'offline',
    );

void main() {
  test('cartons and strips convert with integer base-unit arithmetic', () {
    const packaging = MedicinePackaging(
      stripsPerCarton: 10,
      unitsPerStrip: 12,
    );
    expect(packaging.baseUnitsFor(1, PackagingUnit.carton), 120);
    expect(packaging.baseUnitsFor(3, PackagingUnit.strip), 36);
    expect(packaging.baseUnitsFor(5, PackagingUnit.individual), 5);
    final breakdown = packaging.breakdown(287);
    expect((breakdown.cartons, breakdown.strips, breakdown.individuals),
        (2, 3, 11));
  });

  test('mixed-unit withdrawals are audited and never make stock negative',
      () async {
    final repository = MockInventoryRepository();
    final medicine = _success(await repository.create(
      detachmentId: 'd_test',
      name: 'Medicine',
      unit: 'unit',
      openingStock: 3,
      openingUnit: PackagingUnit.carton,
      unitsPerStrip: 12,
      stripsPerCarton: 10,
      minimum: 12,
    ));
    expect(medicine.currentStock, 360);

    _success(await repository.addMovement(
      itemId: medicine.id,
      direction: MovementDirection.outflow,
      quantity: 2,
      packagingUnit: PackagingUnit.carton,
      reason: 'two cartons',
    ));
    _success(await repository.addMovement(
      itemId: medicine.id,
      direction: MovementDirection.outflow,
      quantity: 3,
      packagingUnit: PackagingUnit.strip,
      reason: 'three strips',
    ));
    final after = _success(await repository.addMovement(
      itemId: medicine.id,
      direction: MovementDirection.outflow,
      quantity: 5,
      packagingUnit: PackagingUnit.individual,
      reason: 'five units',
    ));
    expect(after.currentStock, 79);

    final rejected = await repository.addMovement(
      itemId: medicine.id,
      direction: MovementDirection.outflow,
      quantity: 1,
      packagingUnit: PackagingUnit.carton,
      reason: 'too much',
    );
    expect(_code(rejected), 'insufficient_stock');
    expect(_success(await repository.byId(medicine.id)).currentStock, 79);

    final movements = _success(await repository.movementsForItem(medicine.id));
    final stripMovement = movements.firstWhere(
      (movement) => movement.packagingUnit == PackagingUnit.strip,
    );
    expect(stripMovement.quantity, 3);
    expect(stripMovement.convertedBaseUnitQuantity, 36);
    expect(stripMovement.stockBefore, 120);
    expect(stripMovement.stockAfter, 84);
  });

  test('legacy inventory JSON receives safe one-to-one packaging defaults', () {
    final item = InventoryItem.fromJson({
      'id': 'old',
      'detachmentId': 'd',
      'name': 'Old item',
      'unit': 'piece',
      'currentStock': 7,
      'minimum': 2,
      'expiresOn': null,
      'level': 'ok',
    });
    expect(item.unitsPerStrip, 1);
    expect(item.stripsPerCarton, 1);
    expect(item.preferredUnit, PackagingUnit.individual);
    expect(item.stockBreakdown.individuals, 7);

    final movement = InventoryMovement.fromJson({
      'id': 'move',
      'itemId': 'old',
      'direction': 'outflow',
      'quantity': 2,
      'reason': 'legacy',
      'at': '2026-09-02T12:00:00.000',
    });
    expect(movement.convertedBaseUnitQuantity, 2);
    expect(movement.packagingUnit, PackagingUnit.individual);
  });

  test('packaging metadata is required before a package unit can be chosen',
      () async {
    final repository = MockInventoryRepository();
    final noStripSize = await repository.create(
      detachmentId: 'd_test',
      name: 'No strip size',
      unit: 'unit',
      openingStock: 2,
      openingUnit: PackagingUnit.strip,
      minimum: 1,
    );
    expect(_code(noStripSize), 'packaging_required');

    final noCartonSize = await repository.create(
      detachmentId: 'd_test',
      name: 'No carton size',
      unit: 'unit',
      openingStock: 2,
      openingUnit: PackagingUnit.carton,
      unitsPerStrip: 10,
      minimum: 1,
    );
    expect(_code(noCartonSize), 'packaging_required');

    final loose = _success(await repository.create(
      detachmentId: 'd_test',
      name: 'Loose item',
      unit: 'unit',
      openingStock: 20,
      minimum: 1,
    ));
    expect(
      _code(await repository.update(
        id: loose.id,
        name: loose.name,
        unit: loose.unit,
        minimum: loose.minimum,
        preferredUnit: PackagingUnit.carton,
      )),
      'packaging_required',
    );
    expect(
      _code(await repository.addMovement(
        itemId: loose.id,
        direction: MovementDirection.outflow,
        quantity: 1,
        packagingUnit: PackagingUnit.strip,
        reason: 'strip of a loose item',
      )),
      'packaging_unavailable',
    );
    // The rejected movement changed nothing.
    expect(_success(await repository.byId(loose.id)).currentStock, 20);
  });

  test('only whole positive quantities move stock', () async {
    final repository = MockInventoryRepository();
    final item = _success(await repository.create(
      detachmentId: 'd_test',
      name: 'Counted item',
      unit: 'unit',
      openingStock: 10,
      minimum: 1,
    ));
    for (final quantity in [0, -1, -40]) {
      expect(
        _code(await repository.addMovement(
          itemId: item.id,
          direction: MovementDirection.outflow,
          quantity: quantity,
          reason: 'rejected',
        )),
        'validation',
        reason: 'quantity $quantity must be refused',
      );
    }
    expect(_success(await repository.byId(item.id)).currentStock, 10);
  });

  test('every movement carries a complete audit record', () async {
    final repository = MockInventoryRepository();
    final before = DateTime.now().subtract(const Duration(seconds: 1));
    final item = _success(await repository.create(
      detachmentId: 'd_test',
      name: 'Audited medicine',
      unit: 'unit',
      openingStock: 2,
      openingUnit: PackagingUnit.carton,
      unitsPerStrip: 10,
      stripsPerCarton: 5,
      minimum: 10,
    ));
    _success(await repository.addMovement(
      itemId: item.id,
      direction: MovementDirection.outflow,
      quantity: 3,
      packagingUnit: PackagingUnit.strip,
      reason: 'field dressing',
      source: 'mobile_app',
      performedBy: 'u_1',
      performedByName: 'ليلى ياسين',
    ));

    final movements = _success(await repository.movementsForItem(item.id));
    expect(movements, hasLength(2));

    final opening = movements.last;
    expect(opening.direction, MovementDirection.inflow);
    expect(opening.quantity, 2);
    expect(opening.packagingUnit, PackagingUnit.carton);
    expect(opening.convertedBaseUnitQuantity, 100);
    expect(opening.stockBefore, 0);
    expect(opening.stockAfter, 100);
    expect(opening.source, 'inventory_setup');

    final withdrawal = movements.first;
    expect(withdrawal.itemId, item.id);
    expect(withdrawal.itemName, 'Audited medicine');
    expect(withdrawal.direction, MovementDirection.outflow);
    expect(withdrawal.quantity, 3);
    expect(withdrawal.packagingUnit, PackagingUnit.strip);
    expect(withdrawal.convertedBaseUnitQuantity, 30);
    expect(withdrawal.stockBefore, 100);
    expect(withdrawal.stockAfter, 70);
    expect(withdrawal.reason, 'field dressing');
    expect(withdrawal.source, 'mobile_app');
    expect(withdrawal.performedBy, 'u_1');
    expect(withdrawal.performedByName, 'ليلى ياسين');
    expect(withdrawal.at.isAfter(before), isTrue);

    // The audit survives the wire.
    final restored = InventoryMovement.fromJson(withdrawal.toJson());
    expect(restored.performedBy, 'u_1');
    expect(restored.performedByName, 'ليلى ياسين');
    expect(restored.stockBefore, 100);
    expect(restored.stockAfter, 70);
    expect(restored.convertedBaseUnitQuantity, 30);
  });
}
