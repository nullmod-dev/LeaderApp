import '../result/result.dart';
import 'pending_operation.dart';

/// Seam for *sending* one pending operation to the server.
///
/// THE NETWORK BOUNDARY. This is where the future HTTP layer attaches
/// `Idempotency-Key: <operation.idempotencyKey>` and replays the write. It
/// is intentionally tiny — one method, `Result<void>` — so wiring the
/// backend is: implement this once, override [syncTransportProvider], and
/// nothing in the coordinator, the outbox, or the UI changes.
///
/// The mapping a real implementation owes (mirrors
/// `AppVersionRepository` / `FRONTEND-BACKEND-INTEGRATION.md`):
///
/// - server accepted / duplicate-of-a-completed-op  → `Success(null)`
/// - no connectivity / timeout                      → `Offline()`
/// - `409 in_progress` (server still working on the same key) → a
///   `Failure` with the agreed code, treated as *retry later*, not an error
/// - `5xx` / transport error                        → `Failure(code: …)`
/// - a `409` stale write (`code: 'stale_write'`, the record's `version`
///   moved) → a `Failure` the coordinator routes to `SyncState.conflict`;
///   `sync_conflict_classifier.dart`'s default classifier already
///   recognises this code (Task 3) — only a real implementation of this
///   interface is missing
/// - a `422` same-key-different-body (invalid idempotency-key reuse) → still
///   `Backend contract decision required`, see `FRONTEND-BACKEND-
///   INTEGRATION.md` §3; must **not** be classified as `stale_write` — it is
///   a protocol fault, not a version conflict
abstract class SyncTransport {
  Future<Result<void>> push(PendingOperation operation);
}

/// The transport in the app **today**: there is no server, so every push is
/// [Offline]. This is deliberate — it keeps Manual Sync honest. Pressing
/// "مزامنة الآن" with no real transport must not show a fake "synced"
/// (roadmap §10 "Synced", verification §12); with this transport the
/// operation stays truthfully `pending` and the UI says so.
class OfflineSyncTransport implements SyncTransport {
  const OfflineSyncTransport();

  @override
  Future<Result<void>> push(PendingOperation operation) async =>
      const Offline<void>();
}
