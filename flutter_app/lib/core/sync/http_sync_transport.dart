import '../network/api_client.dart';
import '../problem/problem.dart';
import '../result/result.dart';
import 'pending_operation.dart';
import 'sync_payload_store.dart';
import 'sync_transport.dart';

/// [SyncTransport] over `POST /sync/push` (`docs/api/sync.md`).
///
/// One operation per call, because the coordinator pushes one at a time and
/// stops at the first offline answer. The operation's `idempotencyKey` is
/// its wire `operationId`, so a retry after a lost response is answered
/// `duplicate` by the server and never applied twice.
///
/// Result mapping (`docs/api/sync.md` → "Result statuses"):
///
/// | server `status`        | here                                         |
/// |------------------------|----------------------------------------------|
/// | `applied`, `duplicate` | `Success` (payload dropped)                  |
/// | `conflict`             | `Failure(stale_write)` → Needs Review        |
/// | `retry`                | `Failure(<code>)` → kept, retried later      |
/// | `rejected`             | `Failure(<code>)` → kept as failed, visible  |
class HttpSyncTransport implements SyncTransport {
  HttpSyncTransport(this._api, this._payloads);

  final ApiClient _api;
  final SyncPayloadStore _payloads;

  /// The code an operation fails with when nothing on this device can replay
  /// it: no stored payload and no receipt of an online write. It keeps the
  /// operation in the outbox as `failed` rather than inventing a success.
  static const payloadMissingCode = 'sync_payload_missing';

  @override
  Future<Result<void>> push(PendingOperation operation) async {
    final stored = await _payloads.read(operation.operationId);
    if (stored == null) {
      final entityId = operation.entityId;
      if (entityId != null &&
          await _payloads.consumeApplied(operation.kind, entityId)) {
        // Written online by the repository before it was queued: the server
        // already has it. Sending it again would record it twice.
        return const Success(null);
      }
      return const Failure('', code: payloadMissingCode);
    }

    final version = int.tryParse(operation.currentVersion ?? '') ??
        stored.version;
    final outcome = await _api.exchange(
      'POST',
      '/sync/push',
      body: {
        'operations': [
          {
            'operationId': operation.idempotencyKey,
            'kind': operation.kind,
            'payload': stored.payload,
            if (version != null) 'version': version,
          },
        ],
      },
    );

    switch (outcome) {
      case ApiUnreachable(:final offline):
        return offline
            ? const Offline()
            : Failure(failureMessage(ProblemCode.network.wire),
                code: ProblemCode.network.wire);
      case ApiReply(:final ok, :final json):
        if (!ok) {
          final code = outcome.code;
          return Failure(failureMessage(code), code: code);
        }
        final results = json is Map<String, dynamic> ? json['results'] : null;
        final first = results is List && results.isNotEmpty ? results.first : null;
        if (first is! Map<String, dynamic>) {
          return Failure(failureMessage(ProblemCode.server.wire),
              code: ProblemCode.server.wire);
        }
        final code = first['code'] as String?;
        switch (first['status']) {
          case 'applied':
          case 'duplicate':
            await _payloads.remove(operation.operationId);
            return const Success(null);
          case 'conflict':
            return Failure(failureMessage(ProblemCode.staleWrite.wire),
                code: ProblemCode.staleWrite.wire);
          case 'retry':
            final retryCode = code ?? ProblemCode.server.wire;
            return Failure(failureMessage(retryCode), code: retryCode);
          default:
            // `rejected` (terminal on the server): the write cannot succeed
            // as sent. It stays in the outbox, failed, with its code.
            final rejected = code ?? ProblemCode.validation.wire;
            return Failure(failureMessage(rejected), code: rejected);
        }
    }
  }
}
