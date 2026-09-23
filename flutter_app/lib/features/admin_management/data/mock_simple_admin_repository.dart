import '../../../core/access/capability.dart';
import '../../../core/result/result.dart';
import '../domain/simple_admin_models.dart';
import '../domain/simple_admin_repository.dart';
import 'simple_admin_store.dart';

class MockSimpleAdminRepository implements SimpleAdminRepository {
  MockSimpleAdminRepository({
    required this.store,
    required this.clock,
    required this.tenantId,
    required this.canManage,
  });

  final SimpleAdminStore store;
  final DateTime Function() clock;
  final String? Function() tenantId;
  final bool Function() canManage;

  Future<Result<T>?> _guard<T>() async {
    if (!canManage()) {
      return Failure('', code: SimpleAdminProblemCode.notPermitted.wire);
    }
    final id = tenantId();
    if (id == null || id.isEmpty) {
      return Failure('', code: SimpleAdminProblemCode.contextUnavailable.wire);
    }
    return null;
  }

  @override
  Future<Result<SimpleAdminManagementSnapshot>> readCurrent() async {
    final denied = await _guard<SimpleAdminManagementSnapshot>();
    if (denied != null) return denied;
    final id = tenantId()!;
    return Success(SimpleAdminManagementSnapshot(
      tenantId: id,
      accounts: store.accounts.values.where((a) => a.tenantId == id).toList(),
      invitations:
          store.invitations.values.where((i) => i.tenantId == id).toList(),
      revision: store.revision,
      readAt: clock().toUtc(),
    ));
  }

  @override
  Future<Result<SimpleAdminInvitation>> invite(
    InviteSimpleAdminCommand command,
  ) async {
    final denied = await _guard<SimpleAdminInvitation>();
    if (denied != null) return denied;
    final id = tenantId()!;
    final replayId = store.invitationOperations[command.idempotencyKey];
    final replay = replayId == null ? null : store.invitations[replayId];
    if (replay != null && replay.tenantId == id) return Success(replay);
    if (command.expectedRevision != store.revision) {
      return Failure('', code: SimpleAdminProblemCode.stale.wire);
    }
    final email = command.email.trim().toLowerCase();
    final name = command.suggestedName.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) ||
        name.isEmpty ||
        command.idempotencyKey.trim().isEmpty ||
        command.capabilityKeys.isEmpty ||
        !simpleAdminAssignableKeys.containsAll(command.capabilityKeys)) {
      return Failure('', code: SimpleAdminProblemCode.invalidInput.wire);
    }
    final duplicateAccount = store.accounts.values.any(
      (a) => a.tenantId == id && a.email.toLowerCase() == email,
    );
    final duplicateInvitation = store.invitations.values.any(
      (i) =>
          i.tenantId == id &&
          i.email.toLowerCase() == email &&
          i.effectiveStatus(clock()) == SimpleAdminInvitationStatus.pending,
    );
    if (duplicateAccount || duplicateInvitation) {
      return Failure('', code: SimpleAdminProblemCode.duplicateEmail.wire);
    }
    final now = clock().toUtc();
    final invitation = SimpleAdminInvitation(
      id: 'admin_inv_${store.revision + 1}',
      tenantId: id,
      email: email,
      suggestedName: name,
      capabilities:
          Capabilities(global: Set.unmodifiable(command.capabilityKeys)),
      createdAt: now,
      expiresAt: now.add(const Duration(days: 7)),
      status: SimpleAdminInvitationStatus.pending,
    );
    store.invitations[invitation.id] = invitation;
    store.invitationOperations[command.idempotencyKey] = invitation.id;
    store.revision++;
    return Success(invitation);
  }

  @override
  Future<Result<void>> cancel(
    CancelSimpleAdminInvitationCommand command,
  ) async {
    final denied = await _guard<void>();
    if (denied != null) return denied;
    if (command.expectedRevision != store.revision) {
      return Failure('', code: SimpleAdminProblemCode.stale.wire);
    }
    final invitation = store.invitations[command.invitationId];
    if (invitation == null || invitation.tenantId != tenantId()) {
      return Failure('', code: SimpleAdminProblemCode.notFound.wire);
    }
    if (invitation.effectiveStatus(clock()) !=
        SimpleAdminInvitationStatus.pending) {
      return Failure('', code: SimpleAdminProblemCode.invalidInput.wire);
    }
    store.invitations[invitation.id] = invitation.copyWith(
      status: SimpleAdminInvitationStatus.cancelled,
    );
    store.revision++;
    return const Success(null);
  }

  @override
  Future<Result<SimpleAdminAccount>> updateCapabilities(
    UpdateSimpleAdminCapabilitiesCommand command,
  ) async {
    final denied = await _guard<SimpleAdminAccount>();
    if (denied != null) return denied;
    if (command.expectedRevision != store.revision) {
      return Failure('', code: SimpleAdminProblemCode.stale.wire);
    }
    if (command.capabilityKeys.isEmpty ||
        !simpleAdminAssignableKeys.containsAll(command.capabilityKeys)) {
      return Failure('', code: SimpleAdminProblemCode.invalidInput.wire);
    }
    final account = store.accounts[command.accountId];
    if (account == null || account.tenantId != tenantId()) {
      return Failure('', code: SimpleAdminProblemCode.notFound.wire);
    }
    final updated = account.copyWith(
      capabilities:
          Capabilities(global: Set.unmodifiable(command.capabilityKeys)),
      revision: account.revision + 1,
    );
    store.accounts[account.id] = updated;
    store.revision++;
    return Success(updated);
  }
}
