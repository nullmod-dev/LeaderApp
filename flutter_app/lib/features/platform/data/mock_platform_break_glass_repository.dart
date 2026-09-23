import '../../../core/access/saas_tenant_status.dart';
import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../domain/platform_break_glass_models.dart';
import '../domain/platform_break_glass_repository.dart';
import 'platform_break_glass_fixtures.dart';
import 'platform_tenant_store.dart';

enum MockBreakGlassMode {
  loaded,
  stale,
  offline,
  failure,
  notPermitted,
  recentAuthRequired,
}

/// Process-memory stand-in for the backend grant service.
///
/// One instance represents one Super Admin session: the provider builds a new
/// instance whenever the signed-in account changes, so a grant can never
/// outlive the session that obtained it. It reads the canonical
/// [PlatformTenantStore] for target identity and lifecycle and never writes
/// to it — break-glass changes no tenant, subscription, feature, limit, or
/// history record, and appends nothing to Platform Audit.
class MockPlatformBreakGlassRepository implements PlatformBreakGlassRepository {
  MockPlatformBreakGlassRepository({
    required this.store,
    required this.clock,
    required this.actor,
    this.duration = kProvisionalBreakGlassGrantDuration,
    this.mode = MockBreakGlassMode.loaded,
    this.seed = BreakGlassFixtureScenario.none,
    this.latency = const Duration(milliseconds: 280),
  });

  final PlatformTenantStore store;
  final DateTime Function() clock;

  /// The signed-in Super Admin, or `null` when there is no platform session.
  final BreakGlassInitiator? actor;
  final Duration duration;
  final MockBreakGlassMode mode;
  final BreakGlassFixtureScenario seed;
  final Duration latency;

  BreakGlassGrant? _grant;
  bool _seeded = false;
  int _issued = 0;
  BreakGlassSnapshot? _lastSnapshot;
  final Map<String, _CachedMutation> _idempotency = {};

  Future<void> _wait() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  DateTime get _now => clock().toUtc();

  @override
  Future<Result<BreakGlassSnapshot>> loadCurrent() async {
    await _wait();
    if (actor == null || mode == MockBreakGlassMode.notPermitted) {
      return _failure(BreakGlassProblemCode.notPermitted);
    }
    if (mode == MockBreakGlassMode.offline) {
      return Offline(cached: _lastSnapshot);
    }
    if (mode == MockBreakGlassMode.failure) return _serverFailure();

    _reconcile();
    final snapshot = BreakGlassSnapshot(grant: _grant, readAt: _now);
    _lastSnapshot = snapshot;
    return Success(snapshot, stale: mode == MockBreakGlassMode.stale);
  }

  @override
  Future<Result<BreakGlassMutationResult>> activate(
    ActivateBreakGlassCommand command,
  ) async {
    await _wait();
    final refused = _refuseTransport<BreakGlassMutationResult>();
    if (refused != null) return refused;
    if (mode == MockBreakGlassMode.recentAuthRequired) {
      return _failure(BreakGlassProblemCode.recentAuthenticationRequired);
    }
    if (command.tenantId.trim().isEmpty ||
        command.expectedTenantVersion < 1 ||
        command.idempotencyKey.trim().isEmpty) {
      return _validationFailure();
    }
    final reason = normalizeBreakGlassReason(command.reason);
    if (!isValidBreakGlassReason(reason)) {
      return _failure(BreakGlassProblemCode.invalidReason);
    }
    if (command.scopes.isEmpty) {
      return _failure(BreakGlassProblemCode.invalidScope);
    }

    final scopes = [for (final scope in command.scopes) scope.wire]..sort();
    final fingerprint = [
      'activate',
      command.tenantId,
      command.expectedTenantVersion,
      scopes.join(','),
      reason,
    ].join('|');
    final replay = _replay(command.idempotencyKey, fingerprint);
    if (replay != null) return replay;

    _reconcile();
    final tenant = store.byId(command.tenantId);
    if (tenant == null) {
      return _failure(
        store.tombstoneById(command.tenantId) != null
            ? BreakGlassProblemCode.tenantAlreadyDeleted
            : BreakGlassProblemCode.tenantNotFound,
      );
    }
    if (tenant.tenantVersion != command.expectedTenantVersion) {
      return _failure(BreakGlassProblemCode.staleTenant);
    }

    final decision = BreakGlassPolicy.activate(
      grantId: 'bg_${_now.millisecondsSinceEpoch}_${++_issued}',
      tenant: BreakGlassTenantReference(
        tenantId: tenant.id,
        displayName: tenant.displayName,
      ),
      tenantStatus: tenant.tenantStatus,
      scopes: command.scopes,
      reason: reason,
      initiator: actor!,
      now: _now,
      current: _grant,
      duration: duration,
    );
    return _commit(decision, command.idempotencyKey, fingerprint);
  }

  @override
  Future<Result<BreakGlassMutationResult>> end(
    EndBreakGlassCommand command,
  ) async {
    await _wait();
    final refused = _refuseTransport<BreakGlassMutationResult>();
    if (refused != null) return refused;
    if (command.grantId.trim().isEmpty ||
        command.expectedRevision < 1 ||
        command.idempotencyKey.trim().isEmpty) {
      return _validationFailure();
    }

    final fingerprint =
        ['end', command.grantId, command.expectedRevision].join('|');
    final replay = _replay(command.idempotencyKey, fingerprint);
    if (replay != null) return replay;

    _reconcile();
    final grant = _grant;
    if (grant == null || grant.id != command.grantId) {
      return _failure(BreakGlassProblemCode.grantNotFound);
    }
    if (!grant.isActiveAt(_now)) {
      return _failure(BreakGlassProblemCode.grantNotActive);
    }
    if (grant.revision != command.expectedRevision) {
      return _failure(BreakGlassProblemCode.staleGrant);
    }
    return _commit(
      BreakGlassPolicy.end(grant: grant, now: _now),
      command.idempotencyKey,
      fingerprint,
    );
  }

  /// Applies what the backend does on its own: records time-based expiry and
  /// ends an active grant whose target tenant has left `active`.
  void _reconcile() {
    if (!_seeded) {
      _seeded = true;
      _grant = _seedGrant();
    }
    final grant = _grant;
    if (grant == null) return;
    final settled = BreakGlassPolicy.settle(grant, _now);
    if (settled.isActiveAt(_now) &&
        store.lifecycleStatusOf(settled.tenant.tenantId) !=
            SaasTenantStatus.active) {
      final decision = BreakGlassPolicy.terminate(
        grant: settled,
        reason: BreakGlassEndReason.tenantUnavailable,
        now: _now,
      );
      _grant = (decision as BreakGlassTransitionAllowed).grant;
      return;
    }
    _grant = settled;
  }

  BreakGlassGrant? _seedGrant() {
    if (seed == BreakGlassFixtureScenario.none) return null;
    final tenant = store.byId(BreakGlassFixtures.tenantId);
    if (tenant == null) return null;
    return BreakGlassFixtures.seed(
      seed,
      now: _now,
      tenant: BreakGlassTenantReference(
        tenantId: tenant.id,
        displayName: tenant.displayName,
      ),
      initiator: actor!,
      duration: duration,
    );
  }

  Result<BreakGlassMutationResult> _commit(
    BreakGlassTransitionDecision decision,
    String idempotencyKey,
    String fingerprint,
  ) {
    switch (decision) {
      case BreakGlassTransitionRefused(:final problem):
        return _failure(switch (problem) {
          BreakGlassTransitionProblem.tenantNotFound =>
            BreakGlassProblemCode.tenantNotFound,
          BreakGlassTransitionProblem.tenantNotEligible =>
            BreakGlassProblemCode.tenantNotEligible,
          BreakGlassTransitionProblem.tenantDeleted =>
            BreakGlassProblemCode.tenantAlreadyDeleted,
          BreakGlassTransitionProblem.invalidReason =>
            BreakGlassProblemCode.invalidReason,
          BreakGlassTransitionProblem.invalidScope =>
            BreakGlassProblemCode.invalidScope,
          BreakGlassTransitionProblem.grantAlreadyActive =>
            BreakGlassProblemCode.grantAlreadyActive,
          BreakGlassTransitionProblem.grantNotActive =>
            BreakGlassProblemCode.grantNotActive,
        });
      case BreakGlassTransitionAllowed(:final grant):
        _grant = grant;
        final result = BreakGlassMutationResult(grant: grant, changed: true);
        _idempotency[idempotencyKey] = _CachedMutation(
          fingerprint: fingerprint,
          result: result,
        );
        return Success(result);
    }
  }

  Result<BreakGlassMutationResult>? _replay(String key, String fingerprint) {
    final cached = _idempotency[key];
    if (cached == null) return null;
    if (cached.fingerprint != fingerprint) {
      return _failure(BreakGlassProblemCode.idempotencyConflict);
    }
    return Success(cached.result.asIdempotentReplay());
  }

  Result<T>? _refuseTransport<T>() {
    if (actor == null || mode == MockBreakGlassMode.notPermitted) {
      return _failure(BreakGlassProblemCode.notPermitted);
    }
    if (mode == MockBreakGlassMode.offline) return Offline<T>();
    if (mode == MockBreakGlassMode.failure) return _serverFailure();
    return null;
  }

  static Failure<T> _failure<T>(BreakGlassProblemCode code) =>
      Failure(_messages[code]!, code: code.wire);

  static Failure<T> _validationFailure<T>() => Failure(
        'طلب الوصول الطارئ غير صالح.',
        code: ProblemCode.validation.wire,
      );

  static Failure<T> _serverFailure<T>() => Failure(
        'تعذّر إتمام العملية بأمان.',
        code: ProblemCode.server.wire,
      );

  static const _messages = {
    BreakGlassProblemCode.tenantNotFound: 'الفريق غير موجود.',
    BreakGlassProblemCode.tenantNotEligible:
        'لا يسمح وضع الفريق الحالي بالوصول الطارئ.',
    BreakGlassProblemCode.tenantAlreadyDeleted:
        'اكتمل حذف الفريق ولا يمكن الوصول إليه.',
    BreakGlassProblemCode.invalidReason: 'أدخل سببًا إداريًا موجزًا وصالحًا.',
    BreakGlassProblemCode.invalidScope: 'نطاق الوصول المطلوب غير صالح.',
    BreakGlassProblemCode.grantAlreadyActive:
        'لديك وصول طارئ نشط بالفعل. أنهِه أولًا.',
    BreakGlassProblemCode.grantNotFound: 'لم يُعثر على هذا الوصول الطارئ.',
    BreakGlassProblemCode.grantNotActive: 'انتهى هذا الوصول الطارئ بالفعل.',
    BreakGlassProblemCode.staleTenant:
        'تغيّرت حالة الفريق. حدّث الصفحة ثم أعد المحاولة.',
    BreakGlassProblemCode.staleGrant:
        'تغيّرت حالة الوصول الطارئ. حدّث الصفحة ثم أعد المحاولة.',
    BreakGlassProblemCode.idempotencyConflict:
        'أُعيد استخدام معرّف العملية لطلب مختلف.',
    BreakGlassProblemCode.recentAuthenticationRequired:
        'يتطلب هذا الإجراء تسجيل دخول حديثًا.',
    BreakGlassProblemCode.notPermitted:
        'لا تملك الجلسة صلاحية تنفيذ هذا الإجراء.',
  };
}

class _CachedMutation {
  const _CachedMutation({required this.fingerprint, required this.result});

  final String fingerprint;
  final BreakGlassMutationResult result;
}
