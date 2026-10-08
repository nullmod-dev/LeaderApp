import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../../../core/sync/sync_payload_store.dart';
import '../domain/inventory_models.dart';
import '../domain/inventory_repository.dart';

/// `/detachments/:id/inventory-*` and `/inventory-items/**`
/// (`docs/api/inventory.md`). Stock only ever moves through [addMovement];
/// the server's conditional update makes two concurrent outflows safe.
class HttpInventoryRepository implements InventoryRepository {
  HttpInventoryRepository(this._api, this._payloads);

  final ApiClient _api;
  final SyncPayloadStore _payloads;

  /// The outbox kind the storage screen enqueues after a movement.
  static const movementKind = 'inventory.movement.add';

  static InventoryItem _item(Object? json) =>
      InventoryItem.fromJson(json as Map<String, dynamic>);

  static String _path(String id) =>
      '/inventory-items/${Uri.encodeComponent(id)}';

  /// A calendar day on the wire: `YYYY-MM-DD`, never an instant.
  static String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Future<Result<List<InventoryItem>>> listForDetachment(String detachmentId) =>
      _api.send(
        'GET',
        '/detachments/${Uri.encodeComponent(detachmentId)}/inventory-items',
        parse: (json) => [for (final row in json as List) _item(row)],
      );

  @override
  Future<Result<InventoryItem>> byId(String id) =>
      _api.send('GET', _path(id), parse: _item);

  @override
  Future<Result<List<InventoryMovement>>> movementsForItem(String itemId) =>
      _api.send(
        'GET',
        '${_path(itemId)}/movements',
        query: const {'limit': '200'},
        parse: (json) => [
          for (final row in json as List)
            InventoryMovement.fromJson(row as Map<String, dynamic>),
        ],
      );

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
  }) =>
      _api.send(
        'POST',
        '/inventory-items',
        body: {
          'detachmentId': detachmentId,
          'name': name,
          'unit': unit,
          'openingStock': openingStock,
          'openingUnit': openingUnit.name,
          'minimum': minimum,
          'unitsPerStrip': unitsPerStrip,
          'stripsPerCarton': stripsPerCarton,
          if (expiresOn != null) 'expiresOn': _day(expiresOn),
        },
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: _item,
      );

  /// `PUT`: name, unit and minimum always; packaging, preferred unit and
  /// expiry only when given — absent means unchanged, as in the mock.
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
  }) =>
      _api.send(
        'PUT',
        _path(id),
        body: {
          'id': id,
          'name': name,
          'unit': unit,
          'minimum': minimum,
          if (unitsPerStrip != null) 'unitsPerStrip': unitsPerStrip,
          if (stripsPerCarton != null) 'stripsPerCarton': stripsPerCarton,
          if (preferredUnit != null) 'preferredUnit': preferredUnit.name,
          if (expiresOn != null) 'expiresOn': _day(expiresOn),
        },
        parse: _item,
      );

  @override
  Future<Result<void>> delete(String id) =>
      _api.send('DELETE', _path(id), parse: (_) {});

  /// Written online, with its own `Idempotency-Key`. On success the movement
  /// leaves a receipt in the [SyncPayloadStore], so the outbox entry the
  /// storage screen files right after is recognised as already applied and
  /// never sent a second time (decision D7). `performedBy` is the session's,
  /// taken by the server — the arguments are not sent.
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
    final result = await _api.send(
      'POST',
      '${_path(itemId)}/movements',
      body: {
        'itemId': itemId,
        'direction': direction.name,
        'quantity': quantity,
        'reason': reason,
        'packagingUnit': packagingUnit.name,
        if (source != null) 'source': source,
      },
      idempotencyKey: ApiClient.newIdempotencyKey(),
      parse: _item,
    );
    if (result.isSuccess) await _payloads.recordApplied(movementKind, itemId);
    return result;
  }
}
