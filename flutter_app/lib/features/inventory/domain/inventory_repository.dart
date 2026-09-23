import '../../../core/result/result.dart';
import 'inventory_models.dart';

abstract class InventoryRepository {
  Future<Result<List<InventoryItem>>> listForDetachment(String detachmentId);
  Future<Result<InventoryItem>> byId(String id);
  Future<Result<List<InventoryMovement>>> movementsForItem(String itemId);

  /// Adding an item is the setup act — deciding what this detachment stocks.
  /// The opening quantity is recorded as an inflow so the item's history
  /// starts where its stock does, rather than with an unexplained number.
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
  });

  /// Saves the editable fields: name, unit, minimum, expiry. The quantity is
  /// **not** among them — stock only ever moves through [addMovement], so the
  /// history always explains the number.
  Future<Result<InventoryItem>> update({
    required String id,
    required String name,
    required String unit,
    required int minimum,
    int? unitsPerStrip,
    int? stripsPerCarton,
    PackagingUnit? preferredUnit,
    DateTime? expiresOn,
  });

  Future<Result<void>> delete(String id);

  Future<Result<InventoryItem>> addMovement({
    required String itemId,
    required MovementDirection direction,
    required int quantity,
    required String reason,
    PackagingUnit packagingUnit = PackagingUnit.individual,
    String? source,
    String? performedBy,
    String? performedByName,
  });
}
