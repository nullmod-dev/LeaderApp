import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/saas_subscription_models.dart';
import '../domain/saas_subscription_repository.dart';

/// `/platform/tenants/:id/subscription/**`, `…/limits/**` and
/// `/platform/plans` (`docs/api/platform-tenants.md` §§11–18).
///
/// The wire splits what the app's models hold together (the subscription
/// read carries no tenant name; the limits read carries only the
/// subscription's version and overrides), so the two reads are combined
/// here. Every command needs an `Idempotency-Key` and answers the
/// subscription the server now holds.
class HttpTenantSubscriptionRepository implements TenantSubscriptionRepository {
  HttpTenantSubscriptionRepository(this._api);

  final ApiClient _api;

  /// Tenant display names already read, so a command's answer can be
  /// labelled without another round trip.
  final Map<String, String> _names = {};

  static String _tenant(String id) =>
      '/platform/tenants/${Uri.encodeComponent(id)}';

  Future<Result<String>> _nameOf(String tenantId) async {
    final known = _names[tenantId];
    if (known != null) return Success(known);
    final result = await _api.send(
      'GET',
      _tenant(tenantId),
      parse: (json) {
        final j = json as Map<String, dynamic>;
        return (j['displayName'] ?? j['displayNameSnapshot'] ?? '') as String;
      },
    );
    if (result case Success(:final data)) _names[tenantId] = data;
    return result;
  }

  static SaasPlan? _planOf(Object? raw) =>
      raw is Map<String, dynamic> ? SaasPlan.fromJson(raw) : null;

  Future<Result<TenantSubscriptionDetails>> _details(
    String tenantId,
    ApiOutcome outcome,
  ) async {
    if (outcome is! ApiReply || !outcome.ok) {
      return ApiClient.resultOf(outcome, (_) => throw StateError(''));
    }
    final name = await _nameOf(tenantId);
    if (name case Failure(:final message, :final code)) {
      return Failure(message, code: code);
    }
    if (name is Offline) return const Offline();
    return ApiClient.resultOf(outcome, (json) {
      final j = json as Map<String, dynamic>;
      return TenantSubscriptionDetails(
        tenantId: tenantId,
        tenantName: (name as Success<String>).data,
        subscription:
            SaasSubscription.fromJson(j['subscription'] as Map<String, dynamic>),
        currentPlan: _planOf(j['currentPlan']),
      );
    });
  }

  @override
  Future<Result<TenantSubscriptionDetails>> getSubscription(
    String tenantId,
  ) async =>
      _details(
        tenantId,
        await _api.exchange('GET', '${_tenant(tenantId)}/subscription'),
      );

  @override
  Future<Result<List<SaasPlan>>> listPlans() => _api.send(
        'GET',
        '/platform/plans',
        parse: (json) {
          final rows = json is Map<String, dynamic> ? json['items'] : json;
          return [
            for (final row in rows as List)
              SaasPlan.fromJson(row as Map<String, dynamic>),
          ];
        },
      );

  @override
  Future<Result<TenantLimitsSnapshot>> getLimits(String tenantId) async {
    final limits = await _api.exchange('GET', '${_tenant(tenantId)}/limits');
    return _limits(tenantId, limits);
  }

  Future<Result<TenantLimitsSnapshot>> _limits(
    String tenantId,
    ApiOutcome limits,
  ) async {
    if (limits is! ApiReply || !limits.ok) {
      return ApiClient.resultOf(limits, (_) => throw StateError(''));
    }
    final subscription =
        await _api.exchange('GET', '${_tenant(tenantId)}/subscription');
    if (subscription is! ApiReply || !subscription.ok) {
      return ApiClient.resultOf(subscription, (_) => throw StateError(''));
    }
    return ApiClient.resultOf(limits, (json) {
      final j = json as Map<String, dynamic>;
      final s = subscription.json as Map<String, dynamic>;
      final name = (j['tenantName'] as String?) ?? '';
      _names[tenantId] = name;
      final rawPlan = j['plan'] as Map<String, dynamic>;
      final plan = _planOf(s['currentPlan']) ??
          SaasPlan(
            id: rawPlan['id'] as String,
            name: (rawPlan['name'] as String?) ?? '',
            description: '',
            defaultLimits: PlanLimits.fromJson(
                rawPlan['defaultLimits'] as Map<String, dynamic>),
          );
      final usage = j['usage'] as Map<String, dynamic>;
      return TenantLimitsSnapshot(
        tenantId: tenantId,
        tenantName: name,
        subscription:
            SaasSubscription.fromJson(s['subscription'] as Map<String, dynamic>),
        plan: plan,
        usage: TenantPlanUsage({
          for (final key in PlanLimitKey.values)
            key: (usage[key.wire] as num?)?.toInt() ?? 0,
        }),
      );
    });
  }

  Future<Result<TenantSubscriptionDetails>> _command(
    SubscriptionVersionedCommand command,
    String path,
    Map<String, dynamic> body,
  ) async =>
      _details(
        command.tenantId,
        await _api.exchange(
          'POST',
          '${_tenant(command.tenantId)}/subscription/$path',
          body: {...body, 'expectedVersion': command.expectedVersion},
          idempotencyKey: ApiClient.newIdempotencyKey(),
        ),
      );

  @override
  Future<Result<TenantSubscriptionDetails>> activate(
    ActivateSubscriptionCommand command,
  ) =>
      _command(command, 'activate', {'planId': command.planId});

  @override
  Future<Result<TenantSubscriptionDetails>> extendTrial(
    ExtendTrialCommand command,
  ) =>
      _command(command, 'trial/extend', {
        'newEndsAt': command.newEndsAt.toUtc().toIso8601String(),
      });

  @override
  Future<Result<TenantSubscriptionDetails>> endTrial(
    SubscriptionVersionedCommand command,
  ) =>
      _command(command, 'trial/end', const {});

  @override
  Future<Result<TenantSubscriptionDetails>> moveToGrace(
    SubscriptionVersionedCommand command,
  ) =>
      _command(command, 'grace', const {});

  @override
  Future<Result<TenantSubscriptionDetails>> changePlan(
    ChangePlanCommand command,
  ) =>
      _command(command, 'plan', {'planId': command.planId});

  @override
  Future<Result<TenantLimitsSnapshot>> updateLimitOverride(
    UpdateLimitOverrideCommand command,
  ) async {
    final outcome = await _api.exchange(
      'PATCH',
      '${_tenant(command.tenantId)}/limits/${command.key.wire}',
      body: {
        'overrideValue': command.overrideValue,
        'expectedVersion': command.expectedVersion,
      },
      idempotencyKey: ApiClient.newIdempotencyKey(),
    );
    return _limits(command.tenantId, outcome);
  }
}
