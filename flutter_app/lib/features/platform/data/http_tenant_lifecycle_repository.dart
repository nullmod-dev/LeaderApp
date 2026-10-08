import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/tenant_lifecycle_models.dart';
import '../domain/tenant_lifecycle_repository.dart';

/// `/platform/tenants/:id/lifecycle/**` (`docs/api/platform-tenants.md`
/// §§6–10). The state machine, the deletion window and the final cascade are
/// the server's; the command's own `idempotencyKey` travels unchanged.
class HttpTenantLifecycleRepository implements TenantLifecycleRepository {
  HttpTenantLifecycleRepository(this._api);

  final ApiClient _api;

  Future<Result<TenantLifecycleMutationResult>> _command(
    TenantLifecycleCommand command,
    String action,
    Map<String, dynamic> body,
  ) async {
    final outcome = await _api.exchange(
      'POST',
      '/platform/tenants/${Uri.encodeComponent(command.tenantId)}'
          '/lifecycle/$action',
      body: {...body, 'expectedVersion': command.expectedVersion},
      idempotencyKey: command.idempotencyKey,
    );
    final replayed = outcome is ApiReply &&
        outcome.headers['idempotent-replayed'] == 'true';
    return ApiClient.resultOf(
      outcome,
      (json) => _result(json as Map<String, dynamic>, replayed: replayed),
    );
  }

  static TenantLifecycleMutationResult _result(
    Map<String, dynamic> j, {
    required bool replayed,
  }) {
    final tombstone = j['tombstone'];
    final result = TenantLifecycleMutationResult(
      tenantId: j['tenantId'] as String,
      displayNameSnapshot: j['displayNameSnapshot'] as String,
      lifecycle: SaasTenantLifecycle.fromJson(
          j['lifecycle'] as Map<String, dynamic>),
      changed: (j['changed'] as bool?) ?? true,
      tombstone: tombstone is Map<String, dynamic>
          ? DeletedTenantTombstone(
              tenantId: tombstone['tenantId'] as String,
              displayNameSnapshot: tombstone['displayNameSnapshot'] as String,
              deletedAt: DateTime.parse(tombstone['deletedAt'] as String),
              lifecycleVersion: (tombstone['lifecycleVersion'] as num).toInt(),
              historyReference: tombstone['historyReference'] as String,
            )
          : null,
    );
    return replayed ? result.asIdempotentReplay() : result;
  }

  @override
  Future<Result<TenantLifecycleMutationResult>> suspend(
    SuspendTenantCommand command,
  ) =>
      _command(command, 'suspend', {'reason': command.reason});

  @override
  Future<Result<TenantLifecycleMutationResult>> reactivate(
    ReactivateTenantCommand command,
  ) =>
      _command(command, 'reactivate', const {});

  @override
  Future<Result<TenantLifecycleMutationResult>> beginDeletion(
    BeginTenantDeletionCommand command,
  ) =>
      _command(command, 'deletion/begin', {'reason': command.reason});

  @override
  Future<Result<TenantLifecycleMutationResult>> cancelDeletion(
    CancelTenantDeletionCommand command,
  ) =>
      _command(command, 'deletion/cancel', const {});

  @override
  Future<Result<TenantLifecycleMutationResult>> finalizeDeletion(
    FinalizeTenantDeletionCommand command,
  ) =>
      _command(command, 'deletion/finalize', const {});
}
