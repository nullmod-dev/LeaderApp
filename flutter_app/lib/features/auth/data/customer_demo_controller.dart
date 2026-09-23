import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result/result.dart';
import '../../demo/data/demo_control_plane.dart';
import '../../demo/domain/demo_policy.dart';
import '../domain/auth_models.dart';
import '../domain/customer_demo.dart';
import 'auth_providers.dart';
import 'mock_auth_repository.dart';
import 'onboarding_controller.dart';

/// The one global availability answer for the customer-demo product entry.
///
/// **Derived, never authored here.** It is the Super Admin's `DemoPolicy`
/// read from the login screen's side: whether the offer exists, and the window
/// a new trial would be stamped with. That is why disabling the offer in
/// Platform → «إدارة الحسابات التجريبية» stops a new trial starting without a
/// second switch existing anywhere. It is never tied to `demoAccountsAllowed`,
/// which controls developer personas only.
final customerDemoPolicyProvider = Provider<CustomerDemoPolicy>((ref) {
  final policy = ref.watch(demoControlPlaneProvider).policy;
  return CustomerDemoPolicy(
    available: policy.enabled,
    duration: policy.defaultDuration,
  );
});

class CustomerDemoController extends Notifier<bool> {
  @override
  bool build() => false;

  /// Starts the isolated demo. [leavingOnboarding] is the Point 18B
  /// chooser's path: a verified, unlinked identity picked "تجربة MTM", so
  /// once the demo session exists this device's restricted onboarding
  /// session is discarded — the demo never carries the signup account, and
  /// ending the demo returns to sign-in, not to a half-finished journey.
  /// Nothing is linked, no Team Code is spent and no tenant relationship is
  /// created on either path. A refused or offline start leaves the
  /// onboarding session exactly as it was.
  Future<Result<AuthUser>?> start({bool leavingOnboarding = false}) async {
    if (state) return null;
    final policy = ref.read(customerDemoPolicyProvider);
    if (!policy.available) {
      return const Failure('', code: 'demo_unavailable');
    }
    final repository = ref.read(authRepositoryProvider);
    if (repository is! MockAuthRepository) {
      // A production repository owns the real start endpoint. Until it is
      // wired, fail closed instead of manufacturing a local tenant session.
      return const Failure('', code: 'demo_unavailable');
    }
    state = true;
    try {
      // The control plane records the trial *before* the session exists, so
      // the window is stamped from the policy that authorized it and the
      // operator's list can never contain a session the app is not in — or
      // miss one it is. A refusal here is the offer being switched off
      // between the check above and this line; an identity that is already
      // inside a trial is handed that one back rather than given a second.
      // The real, unlinked identity that asked for the trial — not the demo
      // workspace identity it is about to be handed. It is what survives the
      // trial, and what an operator's list has to name.
      final holder =
          ref.read(currentUserProvider).valueOrNull?.id ?? customerDemoUser.id;
      final registration = ref
          .read(demoControlPlaneProvider.notifier)
          .startSession(accountId: holder);
      if (registration is! Success<DemoSession>) {
        return const Failure('', code: 'demo_unavailable');
      }
      final result = await repository.startCustomerDemo(policy: policy);
      if (!result.isSuccess) {
        // Nothing was started, so nothing may stay on the operator's list —
        // and a trial nobody was ever in is not a trial that ended early, so
        // the record is discarded rather than marked terminated.
        ref
            .read(demoControlPlaneProvider.notifier)
            .discardFailedStart(registration.data.demoSessionId);
        return result;
      }
      ref.read(activeDemoSessionIdProvider.notifier).state =
          registration.data.demoSessionId;
      ref.invalidate(currentUserResultProvider);
      ref.invalidate(sessionAccessProvider);
      ref.invalidate(sessionsProvider);
      await ref.read(currentUserResultProvider.future);
      if (leavingOnboarding) {
        await ref.read(onboardingControllerProvider.notifier).abandon();
      }
      return result;
    } finally {
      state = false;
    }
  }
}

final customerDemoControllerProvider =
    NotifierProvider<CustomerDemoController, bool>(CustomerDemoController.new);
