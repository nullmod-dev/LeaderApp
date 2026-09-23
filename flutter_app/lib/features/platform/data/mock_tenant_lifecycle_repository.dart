import '../../../core/problem/problem.dart';
import '../../../core/result/result.dart';
import '../domain/saas_tenant_models.dart';
import '../domain/tenant_lifecycle_models.dart';
import '../domain/tenant_lifecycle_repository.dart';
import 'platform_tenant_store.dart';

enum MockTenantLifecycleMode { loaded, offline, failure, notPermitted }

class MockTenantLifecycleRepository implements TenantLifecycleRepository {
  MockTenantLifecycleRepository({
    required this.store,
    required this.clock,
    this.deletionGrace = kProvisionalTenantDeletionGrace,
    this.mode = MockTenantLifecycleMode.loaded,
    this.latency = const Duration(milliseconds: 280),
  });

  final PlatformTenantStore store;
  final DateTime Function() clock;
  final Duration deletionGrace;
  final MockTenantLifecycleMode mode;
  final Duration latency;

  final Map<String, _CachedMutation> _idempotency = {};

  Future<void> _wait() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  @override
  Future<Result<TenantLifecycleMutationResult>> suspend(
    SuspendTenantCommand command,
  ) =>
      _run(
        command,
        TenantLifecycleAction.suspend,
        reason: command.reason,
      );

  @override
  Future<Result<TenantLifecycleMutationResult>> reactivate(
    ReactivateTenantCommand command,
  ) =>
      _run(command, TenantLifecycleAction.reactivate);

  @override
  Future<Result<TenantLifecycleMutationResult>> beginDeletion(
    BeginTenantDeletionCommand command,
  ) =>
      _run(
        command,
        TenantLifecycleAction.beginDeletion,
        reason: command.reason,
      );

  @override
  Future<Result<TenantLifecycleMutationResult>> cancelDeletion(
    CancelTenantDeletionCommand command,
  ) =>
      _run(command, TenantLifecycleAction.cancelDeletion);

  @override
  Future<Result<TenantLifecycleMutationResult>> finalizeDeletion(
    FinalizeTenantDeletionCommand command,
  ) =>
      _run(command, TenantLifecycleAction.finalizeDeletion);

  Future<Result<TenantLifecycleMutationResult>> _run(
    TenantLifecycleCommand command,
    TenantLifecycleAction action, {
    String? reason,
  }) async {
    await _wait();

    if (mode == MockTenantLifecycleMode.offline) return const Offline();
    if (mode == MockTenantLifecycleMode.notPermitted) {
      return _failure(
        TenantLifecycleProblemCode.notPermitted,
        'لا تملك الجلسة صلاحية تنفيذ هذا الإجراء.',
      );
    }
    if (mode == MockTenantLifecycleMode.failure) {
      return Failure(
        'تعذّر إتمام العملية بأمان.',
        code: ProblemCode.server.wire,
      );
    }

    if (command.tenantId.trim().isEmpty ||
        command.expectedVersion < 1 ||
        command.idempotencyKey.trim().isEmpty) {
      return _failure(
        TenantLifecycleProblemCode.invalidTransition,
        'طلب دورة حياة الفريق غير صالح.',
      );
    }

    String? normalizedReason;
    if (reason != null) {
      normalizedReason = normalizeTenantLifecycleReason(reason);
      try {
        validateTenantLifecycleReason(normalizedReason);
      } on ArgumentError {
        return _failure(
          TenantLifecycleProblemCode.invalidReason,
          'أدخل سببًا إداريًا موجزًا وصالحًا.',
        );
      }
    }

    final fingerprint = [
      action.name,
      command.tenantId,
      command.expectedVersion,
      normalizedReason ?? '',
    ].join('|');
    final cached = _idempotency[command.idempotencyKey];
    if (cached != null) {
      if (cached.fingerprint != fingerprint) {
        return _failure(
          TenantLifecycleProblemCode.idempotencyConflict,
          'أُعيد استخدام معرّف العملية لطلب مختلف.',
        );
      }
      return Success(cached.result.asIdempotentReplay());
    }

    final tenant = store.byId(command.tenantId);
    if (tenant == null) {
      if (store.tombstoneById(command.tenantId) != null) {
        return _failure(
          TenantLifecycleProblemCode.tenantAlreadyDeleted,
          'اكتمل حذف الفريق ولا يمكن تغيير حالته.',
        );
      }
      return _failure(
        TenantLifecycleProblemCode.tenantNotFound,
        'الفريق غير موجود.',
      );
    }

    if (tenant.tenantVersion != command.expectedVersion) {
      return _failure(
        TenantLifecycleProblemCode.staleTenant,
        'تغيّرت حالة الفريق. حدّث الصفحة ثم أعد المحاولة.',
      );
    }

    final TenantLifecycleTransitionDecision decision;
    try {
      decision = TenantLifecyclePolicy.transition(
        current: tenant.lifecycle,
        action: action,
        now: clock().toUtc(),
        reason: normalizedReason,
        deletionGrace: deletionGrace,
      );
    } on ArgumentError {
      return _failure(
        TenantLifecycleProblemCode.invalidReason,
        'أدخل سببًا إداريًا موجزًا وصالحًا.',
      );
    }
    if (decision case TenantLifecycleTransitionRefused(:final problem)) {
      return switch (problem) {
        TenantLifecycleTransitionProblem.invalidTransition => _failure(
            TenantLifecycleProblemCode.invalidTransition,
            'لا يسمح وضع الفريق الحالي بهذا الانتقال.',
          ),
        TenantLifecycleTransitionProblem.invalidReason => _failure(
            TenantLifecycleProblemCode.invalidReason,
            'أدخل سببًا إداريًا موجزًا وصالحًا.',
          ),
        TenantLifecycleTransitionProblem.deletionWindowExpired => _failure(
            TenantLifecycleProblemCode.deletionWindowExpired,
            'انتهت نافذة إلغاء الحذف.',
          ),
        TenantLifecycleTransitionProblem.deletionNotEffective => _failure(
            TenantLifecycleProblemCode.deletionNotEffective,
            'لم يحن موعد الحذف النهائي بعد.',
          ),
      };
    }

    final next = (decision as TenantLifecycleTransitionAllowed).next;
    final TenantLifecycleMutationResult result;
    if (action == TenantLifecycleAction.finalizeDeletion) {
      final tombstone = store.finalizeTenant(tenant.id, next);
      result = TenantLifecycleMutationResult(
        tenantId: tenant.id,
        displayNameSnapshot: tenant.displayName,
        lifecycle: next,
        changed: true,
        tombstone: tombstone,
      );
    } else {
      final updated = store.updateLifecycle(
        tenant.id,
        next,
        eventType: _eventType(action),
        note: normalizedReason,
      );
      result = TenantLifecycleMutationResult(
        tenantId: updated.id,
        displayNameSnapshot: updated.displayName,
        lifecycle: updated.lifecycle,
        changed: true,
      );
    }

    _idempotency[command.idempotencyKey] = _CachedMutation(
      fingerprint: fingerprint,
      result: result,
    );
    return Success(result);
  }

  static SaasTenantEventType _eventType(TenantLifecycleAction action) =>
      switch (action) {
        TenantLifecycleAction.suspend => SaasTenantEventType.tenantSuspended,
        TenantLifecycleAction.reactivate =>
          SaasTenantEventType.tenantReactivated,
        TenantLifecycleAction.beginDeletion =>
          SaasTenantEventType.deletionRequested,
        TenantLifecycleAction.cancelDeletion =>
          SaasTenantEventType.deletionCancelled,
        TenantLifecycleAction.finalizeDeletion =>
          SaasTenantEventType.tenantDeleted,
      };

  Failure<TenantLifecycleMutationResult> _failure(
    TenantLifecycleProblemCode code,
    String message,
  ) =>
      Failure(message, code: code.wire);
}

class _CachedMutation {
  const _CachedMutation({
    required this.fingerprint,
    required this.result,
  });

  final String fingerprint;
  final TenantLifecycleMutationResult result;
}
