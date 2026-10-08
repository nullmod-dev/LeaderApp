import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The request body of one queued write, kept beside — never inside — its
/// [PendingOperation](pending_operation.dart).
///
/// `PendingOperation` is payload-free on purpose (its own doc says why); a
/// replay through `POST /sync/push` still needs the body. The backend guide's
/// fix #1 (`FRONTEND-INTEGRATION-GUIDE.md` §12): keep it in a local store
/// keyed by `operationId`, and let the transport assemble
/// `{operationId, kind, payload, version}` from it.
@immutable
class StoredSyncPayload {
  const StoredSyncPayload(this.payload, {this.version});

  final Map<String, dynamic> payload;

  /// The optimistic-concurrency version the write was made against, sent as
  /// `version` (`docs/api/sync.md` → Request).
  final int? version;
}

/// Payloads waiting for replay, plus receipts of writes that already reached
/// the server online.
///
/// **The receipt half is fix #2 (decision D7, Option 1).** The storage screen
/// records a movement through the repository — which, against the backend,
/// writes it online — and only then enqueues the same movement. With the
/// mock that enqueue was the only way the movement could ever reach a server;
/// here it would send it a second time. So the online write leaves a receipt
/// for `(kind, entityId)`, and the transport answers an operation that has a
/// receipt but no payload as *already applied*, without a request. An
/// operation with **neither** is not guessed at: it stays failed in the
/// outbox, so a write that never reached the server is never silently
/// dropped.
///
/// Process memory, like the default `InMemoryOutboxStore` it sits next to: a
/// payload never outlives the queue entry it belongs to.
abstract class SyncPayloadStore {
  Future<void> put(
    String operationId,
    Map<String, dynamic> payload, {
    int? version,
  });

  Future<StoredSyncPayload?> read(String operationId);

  Future<void> remove(String operationId);

  /// The server already holds one write of [kind] for [entityId].
  Future<void> recordApplied(String kind, String entityId);

  /// Spends one receipt for `(kind, entityId)`. `true` when there was one.
  Future<bool> consumeApplied(String kind, String entityId);
}

class InMemorySyncPayloadStore implements SyncPayloadStore {
  final Map<String, StoredSyncPayload> _payloads = {};
  final Map<String, int> _receipts = {};

  static String _key(String kind, String entityId) => '$kind\u0000$entityId';

  @override
  Future<void> put(
    String operationId,
    Map<String, dynamic> payload, {
    int? version,
  }) async {
    _payloads[operationId] =
        StoredSyncPayload(Map.unmodifiable(payload), version: version);
  }

  @override
  Future<StoredSyncPayload?> read(String operationId) async =>
      _payloads[operationId];

  @override
  Future<void> remove(String operationId) async {
    _payloads.remove(operationId);
  }

  @override
  Future<void> recordApplied(String kind, String entityId) async {
    final key = _key(kind, entityId);
    _receipts[key] = (_receipts[key] ?? 0) + 1;
  }

  @override
  Future<bool> consumeApplied(String kind, String entityId) async {
    final key = _key(kind, entityId);
    final count = _receipts[key] ?? 0;
    if (count <= 0) return false;
    if (count == 1) {
      _receipts.remove(key);
    } else {
      _receipts[key] = count - 1;
    }
    return true;
  }
}

final syncPayloadStoreProvider = Provider<SyncPayloadStore>((ref) {
  return InMemorySyncPayloadStore();
});
