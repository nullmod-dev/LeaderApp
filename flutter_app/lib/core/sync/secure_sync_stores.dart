import 'dart:async';
import 'dart:convert';

import '../storage/secure_store.dart';
import 'outbox_store.dart';
import 'pending_operation.dart';
import 'sync_payload_store.dart';

/// The outbox and its payloads, kept across an app restart.
///
/// **Why the secure store.** The outbox is owed work, and its payloads are
/// team data (a member's name, a stock movement). `OutboxStore`'s contract
/// keeps both out of the plain preferences bucket theme and motion level use;
/// until the encrypted database the future `/sync` queue lives in exists, the
/// platform secure store (Keystore / Keychain backed) is the encrypted place
/// this build already has. A queue is small — a handful of offline writes —
/// so one JSON record per store is enough.
///
/// **One queue per account.** Both keys carry the account id. A shared phone
/// must never replay one account's queued writes under another account's
/// session; the next account simply starts from its own (usually empty)
/// queue, and the first account's owed work is still there when it signs in
/// again. Keys follow the persisted `mtm.*` convention.
///
/// Writes are serialised: every change is read-modify-write of one record,
/// and two overlapping upserts must not drop each other.
abstract final class SecureSyncKeys {
  static String outbox(String accountId) => 'mtm.sync.outbox.v1.$accountId';
  static String payloads(String accountId) => 'mtm.sync.payloads.v1.$accountId';
}

/// Runs [action]s one after another.
class _Serial {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }
}

class SecureOutboxStore implements OutboxStore {
  SecureOutboxStore(this._store, {required String accountId})
      : _key = SecureSyncKeys.outbox(accountId);

  final SecureStore _store;
  final String _key;
  final _Serial _serial = _Serial();
  Map<String, PendingOperation>? _rows;

  Future<Map<String, PendingOperation>> _load() async {
    final cached = _rows;
    if (cached != null) return cached;
    final rows = <String, PendingOperation>{};
    try {
      final raw = await _store.readString(_key);
      if (raw != null) {
        for (final item in jsonDecode(raw) as List) {
          try {
            final op = PendingOperation.fromJson(item as Map<String, dynamic>);
            rows[op.operationId] = op;
          } on Object {
            // One unreadable row must not cost the rest of the queue.
          }
        }
      }
    } on Object {
      // A corrupt record reads as an empty queue rather than a crash.
    }
    return _rows = rows;
  }

  Future<void> _save(Map<String, PendingOperation> rows) => rows.isEmpty
      ? _store.remove(_key)
      : _store.writeString(
          _key, jsonEncode([for (final op in rows.values) op.toJson()]));

  @override
  Future<List<PendingOperation>> readAll() => _serial.run(() async {
        final list = (await _load()).values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return List.unmodifiable(list);
      });

  @override
  Future<void> upsert(PendingOperation operation) => _serial.run(() async {
        final rows = await _load();
        rows[operation.operationId] = operation;
        await _save(rows);
      });

  @override
  Future<void> remove(String operationId) => _serial.run(() async {
        final rows = await _load();
        if (rows.remove(operationId) == null) return;
        await _save(rows);
      });
}

class SecureSyncPayloadStore implements SyncPayloadStore {
  SecureSyncPayloadStore(this._store, {required String accountId})
      : _key = SecureSyncKeys.payloads(accountId);

  final SecureStore _store;
  final String _key;
  final _Serial _serial = _Serial();
  Map<String, StoredSyncPayload>? _payloads;
  Map<String, int>? _receipts;

  static String _receiptKey(String kind, String entityId) =>
      '$kind\u0000$entityId';

  Future<void> _load() async {
    if (_payloads != null) return;
    final payloads = <String, StoredSyncPayload>{};
    final receipts = <String, int>{};
    try {
      final raw = await _store.readString(_key);
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        for (final MapEntry(:key, :value)
            in (j['payloads'] as Map<String, dynamic>? ?? const {}).entries) {
          final row = value as Map<String, dynamic>;
          payloads[key] = StoredSyncPayload(
            Map.unmodifiable(row['payload'] as Map<String, dynamic>),
            version: (row['version'] as num?)?.toInt(),
          );
        }
        for (final MapEntry(:key, :value)
            in (j['receipts'] as Map<String, dynamic>? ?? const {}).entries) {
          receipts[key] = (value as num).toInt();
        }
      }
    } on Object {
      // A corrupt record reads as empty: an operation with no payload and no
      // receipt stays failed in the outbox — never silently dropped.
    }
    _payloads = payloads;
    _receipts = receipts;
  }

  Future<void> _save() {
    final payloads = _payloads!;
    final receipts = _receipts!;
    if (payloads.isEmpty && receipts.isEmpty) return _store.remove(_key);
    return _store.writeString(
      _key,
      jsonEncode({
        'payloads': {
          for (final MapEntry(:key, :value) in payloads.entries)
            key: {
              'payload': value.payload,
              if (value.version != null) 'version': value.version,
            },
        },
        'receipts': receipts,
      }),
    );
  }

  @override
  Future<void> put(
    String operationId,
    Map<String, dynamic> payload, {
    int? version,
  }) =>
      _serial.run(() async {
        await _load();
        _payloads![operationId] =
            StoredSyncPayload(Map.unmodifiable(payload), version: version);
        await _save();
      });

  @override
  Future<StoredSyncPayload?> read(String operationId) =>
      _serial.run(() async {
        await _load();
        return _payloads![operationId];
      });

  @override
  Future<void> remove(String operationId) => _serial.run(() async {
        await _load();
        if (_payloads!.remove(operationId) == null) return;
        await _save();
      });

  @override
  Future<void> recordApplied(String kind, String entityId) =>
      _serial.run(() async {
        await _load();
        final key = _receiptKey(kind, entityId);
        _receipts![key] = (_receipts![key] ?? 0) + 1;
        await _save();
      });

  @override
  Future<bool> consumeApplied(String kind, String entityId) =>
      _serial.run(() async {
        await _load();
        final key = _receiptKey(kind, entityId);
        final count = _receipts![key] ?? 0;
        if (count <= 0) return false;
        if (count == 1) {
          _receipts!.remove(key);
        } else {
          _receipts![key] = count - 1;
        }
        await _save();
        return true;
      });
}
