import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/platform_break_glass_models.dart';
import '../domain/platform_break_glass_repository.dart';

/// `/platform/break-glass/**` (`docs/api/break-glass.md`). The grant is
/// bound to the server session that activated it; expiry, settlement and
/// every viewer read are enforced on the server.
class HttpPlatformBreakGlassRepository implements PlatformBreakGlassRepository {
  HttpPlatformBreakGlassRepository(this._api);

  final ApiClient _api;

  @override
  Future<Result<BreakGlassSnapshot>> loadCurrent() => _api.send(
        'GET',
        '/platform/break-glass/current',
        parse: (json) {
          final j = json as Map<String, dynamic>;
          final grant = j['grant'];
          return BreakGlassSnapshot(
            grant: grant is Map<String, dynamic>
                ? BreakGlassGrant.fromJson(grant)
                : null,
            readAt: DateTime.parse(j['readAt'] as String).toUtc(),
          );
        },
      );

  Future<Result<BreakGlassMutationResult>> _command(
    String path,
    Map<String, dynamic> body,
    String idempotencyKey,
  ) async {
    final outcome = await _api.exchange('POST', path,
        body: body, idempotencyKey: idempotencyKey);
    final replayed = outcome is ApiReply &&
        outcome.headers['idempotent-replayed'] == 'true';
    return ApiClient.resultOf(outcome, (json) {
      final result = BreakGlassMutationResult(
        grant: BreakGlassGrant.fromJson(json as Map<String, dynamic>),
        changed: true,
      );
      return replayed ? result.asIdempotentReplay() : result;
    });
  }

  @override
  Future<Result<BreakGlassMutationResult>> activate(
    ActivateBreakGlassCommand command,
  ) =>
      _command(
        '/platform/break-glass/grants',
        {
          'tenantId': command.tenantId,
          'expectedTenantVersion': command.expectedTenantVersion,
          'scopes': [for (final s in command.scopes) s.wire],
          'reason': command.reason,
        },
        command.idempotencyKey,
      );

  @override
  Future<Result<BreakGlassMutationResult>> end(EndBreakGlassCommand command) =>
      _command(
        '/platform/break-glass/grants/'
            '${Uri.encodeComponent(command.grantId)}/end',
        {'expectedRevision': command.expectedRevision},
        command.idempotencyKey,
      );
}
