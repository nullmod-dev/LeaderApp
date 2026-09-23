import 'pending_operation.dart';

/// Persistence seam for the local write outbox — the one list of
/// [PendingOperation]s that both Auto Sync and Manual Sync act on.
///
/// THE SEAM. A shipping build backs this with the encrypted local database
/// (SQLCipher) that the future `/sync` queue also lives in: the outbox is
/// exactly the client half of that queue, so a real implementation is a
/// table `pending_operations` keyed by `operationId`, not a new store.
/// Until that database exists, [InMemoryOutboxStore] stands in with the
/// same lifetime limitation as `MockSettingsRepository` /
/// `MockAppVersionGateStore`.
///
/// Deliberately its own interface and **not** part of `SettingsRepository`:
/// settings are user-chosen preferences, an outbox is owed work. It also
/// must not go in the ordinary key-value preferences bucket that theme and
/// motion level use — `DATA-NEEDS.md` §3.3 reserves that for non-sensitive
/// UI state, and while this record holds no payload, the queue it grows
/// into does.
abstract class OutboxStore {
  /// Every operation still on file, oldest first. A synced operation is
  /// removed by [remove]; nothing here filters by state.
  Future<List<PendingOperation>> readAll();

  /// Inserts a new operation or replaces an existing one with the same
  /// [PendingOperation.operationId]. The only write path — attempt
  /// bookkeeping and state changes come back through here.
  Future<void> upsert(PendingOperation operation);

  /// Drops one operation once the server has accepted it (or, later, once
  /// the conflict / review flow has disposed of it).
  Future<void> remove(String operationId);
}

/// In-memory [OutboxStore]. MOCK — holds operations for the lifetime of the
/// object only. A second `ProviderContainer` built over the *same instance*
/// models an app relaunch (the idiom `forced_upgrade_test.dart` uses), which
/// is enough to prove identity survives a restart; it is **not** durable
/// across an OS process restart. A concrete store writes
/// `PendingOperation.toJson()` to the encrypted DB.
class InMemoryOutboxStore implements OutboxStore {
  InMemoryOutboxStore({List<PendingOperation>? seed})
      : _rows = {
          for (final op in seed ?? const <PendingOperation>[])
            op.operationId: op
        };

  final Map<String, PendingOperation> _rows;

  @override
  Future<List<PendingOperation>> readAll() async {
    final list = _rows.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return List.unmodifiable(list);
  }

  @override
  Future<void> upsert(PendingOperation operation) async {
    _rows[operation.operationId] = operation;
  }

  @override
  Future<void> remove(String operationId) async {
    _rows.remove(operationId);
  }
}
