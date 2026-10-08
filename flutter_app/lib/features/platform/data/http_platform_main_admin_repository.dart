import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/platform_main_admin_models.dart';
import '../domain/platform_main_admin_repository.dart';

/// `/platform/tenants/:id/main-admin/**` (`docs/api/platform-tenants.md`
/// §§21–26). The seat's `revision` is the concurrency token; the command's
/// own `idempotencyKey` travels unchanged; recent authentication for
/// reactivate/replace is checked by the server.
class HttpPlatformMainAdminRepository implements PlatformMainAdminRepository {
  HttpPlatformMainAdminRepository(this._api);

  final ApiClient _api;

  static String _seat(String tenantId) =>
      '/platform/tenants/${Uri.encodeComponent(tenantId)}/main-admin';

  static const Map<String, MainAdminMutationEffect> _effects = {
    'setup_resent': MainAdminMutationEffect.setupResent,
    'suspended': MainAdminMutationEffect.suspended,
    'reactivated': MainAdminMutationEffect.reactivated,
    'replacement_started': MainAdminMutationEffect.replacementStarted,
    'replaced': MainAdminMutationEffect.replaced,
    'replacement_cancelled': MainAdminMutationEffect.replacementCancelled,
    'setup_completed': MainAdminMutationEffect.setupCompleted,
  };

  @override
  Future<Result<MainAdminAccountSnapshot>> load(String tenantId) => _api.send(
        'GET',
        _seat(tenantId),
        parse: (json) =>
            MainAdminAccountSnapshot.fromJson(json as Map<String, dynamic>),
      );

  Future<Result<MainAdminMutationResult>> _command(
    MainAdminCommand command,
    String path,
    Map<String, dynamic> body,
  ) async {
    final outcome = await _api.exchange(
      'POST',
      '${_seat(command.tenantId)}/$path',
      body: {...body, 'expectedRevision': command.expectedRevision},
      idempotencyKey: command.idempotencyKey,
    );
    final replayed = outcome is ApiReply &&
        outcome.headers['idempotent-replayed'] == 'true';
    return ApiClient.resultOf(outcome, (json) {
      final j = json as Map<String, dynamic>;
      final effect = _effects[j['effect']];
      if (effect == null) {
        throw FormatException('unknown main admin effect', j['effect']);
      }
      final result = MainAdminMutationResult(
        snapshot: MainAdminAccountSnapshot.fromJson(
            j['snapshot'] as Map<String, dynamic>),
        effect: effect,
        changed: true,
      );
      return replayed ? result.asIdempotentReplay() : result;
    });
  }

  @override
  Future<Result<MainAdminMutationResult>> resendSetup(
    ResendMainAdminSetupCommand command,
  ) =>
      _command(command, 'setup/resend', {'target': command.target.wire});

  @override
  Future<Result<MainAdminMutationResult>> suspend(
    SuspendMainAdminCommand command,
  ) =>
      _command(command, 'suspend', {'reason': command.reason});

  @override
  Future<Result<MainAdminMutationResult>> reactivate(
    ReactivateMainAdminCommand command,
  ) =>
      _command(command, 'reactivate', const {});

  @override
  Future<Result<MainAdminMutationResult>> replace(
    ReplaceMainAdminCommand command,
  ) {
    final designate = command.designate.normalized;
    return _command(command, 'replacements', {
      'designate': {
        'displayName': designate.displayName,
        'loginEmail': designate.loginEmail,
      },
      'reason': command.reason,
    });
  }

  @override
  Future<Result<MainAdminMutationResult>> cancelReplacement(
    CancelMainAdminReplacementCommand command,
  ) =>
      _command(
        command,
        'replacements/${Uri.encodeComponent(command.replacementId)}/cancel',
        const {},
      );
}
