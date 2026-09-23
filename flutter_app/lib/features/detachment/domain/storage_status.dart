import '../../inventory/domain/inventory_models.dart';

/// A one-word health verdict for the stock a detachment holds.
///
/// Derived, never stored: it is a fold over the same [StockLevel] and expiry
/// data the storage tab already renders per item, so the strip under the
/// detail-shell app bar can never contradict the list one tap away. Kept as
/// its own value set rather than reusing [StockLevel] because the question is
/// different — "is anything wrong in this store" rather than "how much of this
/// item is left".
enum StorageStatus {
  /// No items on record for this detachment.
  empty,

  /// Every item is at or above its minimum and nothing is near expiry.
  healthy,

  /// Something is within [expiringWithinDays] of expiring, but stock levels
  /// are otherwise fine.
  expiring,

  /// At least one item is below its minimum.
  low,

  /// At least one item has run out.
  depleted,
}

/// Same reorder horizon the storage tab's amber expiry text uses.
const int storageExpiringWithinDays = 30;

/// Worst-wins: a depleted item outranks a low one, which outranks an expiring
/// one. Expiry only shows through once levels are healthy, because an empty
/// item that also happens to be expiring is still first an empty item.
StorageStatus storageStatusOf(List<InventoryItem> items) {
  if (items.isEmpty) return StorageStatus.empty;

  var anyLow = false;
  var anyExpiring = false;
  for (final item in items) {
    if (item.level == StockLevel.empty) return StorageStatus.depleted;
    if (item.level == StockLevel.low) anyLow = true;
    final days = item.daysToExpiry;
    if (days != null && days <= storageExpiringWithinDays) anyExpiring = true;
  }
  if (anyLow) return StorageStatus.low;
  if (anyExpiring) return StorageStatus.expiring;
  return StorageStatus.healthy;
}
