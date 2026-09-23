import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../domain/saas_subscription_models.dart';
import '../domain/saas_subscription_repository.dart';
import 'mock_tenant_subscription_repository.dart';
import 'platform_overview_providers.dart';
import 'saas_tenant_providers.dart';

final tenantSubscriptionRepositoryProvider =
    Provider<TenantSubscriptionRepository>((ref) {
  return MockTenantSubscriptionRepository(
    store: ref.watch(platformTenantStoreProvider),
    clock: ref.watch(clockProvider),
  );
});

final tenantSubscriptionProvider = FutureProvider.autoDispose
    .family<Result<TenantSubscriptionDetails>, String>((ref, tenantId) {
  return ref
      .watch(tenantSubscriptionRepositoryProvider)
      .getSubscription(tenantId);
});

final saasPlansProvider = FutureProvider<Result<List<SaasPlan>>>((ref) {
  return ref.watch(tenantSubscriptionRepositoryProvider).listPlans();
});

final tenantLimitsProvider = FutureProvider.autoDispose
    .family<Result<TenantLimitsSnapshot>, String>((ref, tenantId) {
  return ref.watch(tenantSubscriptionRepositoryProvider).getLimits(tenantId);
});

enum SubscriptionActionKind {
  activate,
  extendTrial,
  endTrial,
  moveToGrace,
  changePlan,
  updateLimit,
}

class SubscriptionActionState {
  const SubscriptionActionState({this.submitting});
  final SubscriptionActionKind? submitting;
  bool get isSubmitting => submitting != null;
}

sealed class SubscriptionActionOutcome {
  const SubscriptionActionOutcome();
}

class SubscriptionActionSucceeded extends SubscriptionActionOutcome {
  const SubscriptionActionSucceeded(this.message);
  final String message;
}

class SubscriptionActionOffline extends SubscriptionActionOutcome {
  const SubscriptionActionOffline();
}

class SubscriptionActionStale extends SubscriptionActionOutcome {
  const SubscriptionActionStale();
}

class SubscriptionActionInvalid extends SubscriptionActionOutcome {
  const SubscriptionActionInvalid(this.message);
  final String message;
}

class SubscriptionActionFailed extends SubscriptionActionOutcome {
  const SubscriptionActionFailed(this.message);
  final String message;
}

class SubscriptionActionIgnored extends SubscriptionActionOutcome {
  const SubscriptionActionIgnored();
}

/// One guard for every consequential commercial write. The repository still
/// validates the current version, so disabling a button is never the safety
/// mechanism.
class SubscriptionActionController extends Notifier<SubscriptionActionState> {
  @override
  SubscriptionActionState build() => const SubscriptionActionState();

  Future<SubscriptionActionOutcome> activate(
    ActivateSubscriptionCommand command,
  ) =>
      _run(
        SubscriptionActionKind.activate,
        () => ref.read(tenantSubscriptionRepositoryProvider).activate(command),
        successMessage: 'تم تفعيل الاشتراك إداريًا دون تنفيذ دفعة.',
        tenantId: command.tenantId,
      );

  Future<SubscriptionActionOutcome> extendTrial(
    ExtendTrialCommand command,
  ) =>
      _run(
        SubscriptionActionKind.extendTrial,
        () =>
            ref.read(tenantSubscriptionRepositoryProvider).extendTrial(command),
        successMessage: 'تم تمديد الفترة التجريبية.',
        tenantId: command.tenantId,
      );

  Future<SubscriptionActionOutcome> endTrial(
    SubscriptionVersionedCommand command,
  ) =>
      _run(
        SubscriptionActionKind.endTrial,
        () => ref.read(tenantSubscriptionRepositoryProvider).endTrial(command),
        successMessage: 'انتهت التجربة وبدأت فترة السماح.',
        tenantId: command.tenantId,
      );

  Future<SubscriptionActionOutcome> moveToGrace(
    SubscriptionVersionedCommand command,
  ) =>
      _run(
        SubscriptionActionKind.moveToGrace,
        () =>
            ref.read(tenantSubscriptionRepositoryProvider).moveToGrace(command),
        successMessage: 'بدأت فترة السماح دون تغيير وصول الفريق.',
        tenantId: command.tenantId,
      );

  Future<SubscriptionActionOutcome> changePlan(ChangePlanCommand command) =>
      _run(
        SubscriptionActionKind.changePlan,
        () =>
            ref.read(tenantSubscriptionRepositoryProvider).changePlan(command),
        successMessage: 'تم تغيير الخطة مع الاحتفاظ بالبيانات الحالية.',
        tenantId: command.tenantId,
      );

  Future<SubscriptionActionOutcome> updateLimit(
    UpdateLimitOverrideCommand command,
  ) =>
      _run(
        SubscriptionActionKind.updateLimit,
        () => ref
            .read(tenantSubscriptionRepositoryProvider)
            .updateLimitOverride(command),
        successMessage: command.overrideValue == null
            ? 'أُعيد الحد إلى القيمة الافتراضية للخطة.'
            : 'تم حفظ الحد المخصص.',
        tenantId: command.tenantId,
      );

  Future<SubscriptionActionOutcome> _run<T>(
    SubscriptionActionKind kind,
    Future<Result<T>> Function() operation, {
    required String successMessage,
    required String tenantId,
  }) async {
    if (state.isSubmitting) return const SubscriptionActionIgnored();
    state = SubscriptionActionState(submitting: kind);
    try {
      final result = await operation();
      return result.when(
        success: (_, {stale = false}) {
          _invalidate(tenantId);
          return SubscriptionActionSucceeded(successMessage);
        },
        failure: (message, code) {
          final parsed = SubscriptionProblemCode.parse(code);
          if (parsed == SubscriptionProblemCode.staleSubscription) {
            _invalidate(tenantId);
            return const SubscriptionActionStale();
          }
          if (parsed == SubscriptionProblemCode.invalidTransition ||
              parsed == SubscriptionProblemCode.invalidTrialExtension ||
              parsed == SubscriptionProblemCode.limitInvalid ||
              parsed == SubscriptionProblemCode.planNotFound ||
              parsed == SubscriptionProblemCode.planUnavailable) {
            return SubscriptionActionInvalid(message);
          }
          return const SubscriptionActionFailed(
            'تعذّر إتمام العملية بأمان. حاول مجددًا.',
          );
        },
        offline: (_) => const SubscriptionActionOffline(),
      );
    } finally {
      state = const SubscriptionActionState();
    }
  }

  void _invalidate(String tenantId) {
    ref
      ..invalidate(tenantSubscriptionProvider(tenantId))
      ..invalidate(tenantLimitsProvider(tenantId))
      ..invalidate(saasTenantDetailProvider(tenantId))
      ..invalidate(saasTenantHistoryProvider(tenantId))
      ..invalidate(saasTenantListProvider)
      ..invalidate(platformOverviewProvider);
  }
}

final subscriptionActionControllerProvider =
    NotifierProvider<SubscriptionActionController, SubscriptionActionState>(
  SubscriptionActionController.new,
);
