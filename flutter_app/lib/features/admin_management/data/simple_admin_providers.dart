import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/access/capability.dart';
import '../../../core/access/capability_guard.dart';
import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../auth/data/auth_providers.dart';
import '../domain/simple_admin_models.dart';
import '../domain/simple_admin_repository.dart';
import 'mock_simple_admin_repository.dart';
import 'simple_admin_store.dart';

final simpleAdminStoreProvider = Provider<SimpleAdminStore>((ref) {
  return SimpleAdminStore.seeded(ref.watch(clockProvider)());
});

class SimpleAdminRevisionController extends Notifier<int> {
  @override
  int build() => 0;
  void changed() => state++;
}

final simpleAdminRevisionProvider =
    NotifierProvider<SimpleAdminRevisionController, int>(
  SimpleAdminRevisionController.new,
);

final simpleAdminRepositoryProvider = Provider<SimpleAdminRepository>((ref) {
  return MockSimpleAdminRepository(
    store: ref.watch(simpleAdminStoreProvider),
    clock: ref.watch(clockProvider),
    tenantId: () => ref.read(currentUserProvider).valueOrNull?.saasTenantId,
    canManage: () => ref.read(capabilitiesProvider).can(Cap.adminManage),
  );
});

final simpleAdminSnapshotProvider =
    FutureProvider.autoDispose<Result<SimpleAdminManagementSnapshot>>((ref) {
  ref.watch(currentUserProvider);
  ref.watch(capabilitiesProvider);
  ref.watch(simpleAdminRevisionProvider);
  return ref.read(simpleAdminRepositoryProvider).readCurrent();
});

class SimpleAdminActionController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<Result<SimpleAdminInvitation>?> invite(
    InviteSimpleAdminCommand command,
  ) =>
      _run(() => ref.read(simpleAdminRepositoryProvider).invite(command));

  Future<Result<void>?> cancel(
    CancelSimpleAdminInvitationCommand command,
  ) =>
      _run(() => ref.read(simpleAdminRepositoryProvider).cancel(command));

  Future<Result<SimpleAdminAccount>?> updateCapabilities(
    UpdateSimpleAdminCapabilitiesCommand command,
  ) =>
      _run(
        () =>
            ref.read(simpleAdminRepositoryProvider).updateCapabilities(command),
      );

  Future<Result<T>?> _run<T>(Future<Result<T>> Function() operation) async {
    if (state) return null;
    state = true;
    try {
      final result = await operation();
      if (result.isSuccess) {
        ref.read(simpleAdminRevisionProvider.notifier).changed();
        ref.invalidate(simpleAdminSnapshotProvider);
      }
      return result;
    } finally {
      state = false;
    }
  }
}

final simpleAdminActionControllerProvider =
    NotifierProvider<SimpleAdminActionController, bool>(
  SimpleAdminActionController.new,
);
