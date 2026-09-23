import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/features/admin_management/data/mock_simple_admin_repository.dart';
import 'package:mtm/features/admin_management/data/simple_admin_store.dart';
import 'package:mtm/features/admin_management/domain/simple_admin_models.dart';
import 'package:mtm/features/admin_management/domain/simple_admin_repository.dart';

void main() {
  final now = DateTime.utc(2026, 9, 12, 12);

  MockSimpleAdminRepository repository({
    required bool canManage,
    String? tenantId = 'saas_hilal',
    SimpleAdminStore? store,
  }) =>
      MockSimpleAdminRepository(
        store: store ?? SimpleAdminStore.seeded(now),
        clock: () => now,
        tenantId: () => tenantId,
        canManage: () => canManage,
      );

  group('admin.manage authorization', () {
    test('a capability holder can view accounts and invitations', () async {
      final result = await repository(canManage: true).readCurrent();
      expect(result, isA<Success<SimpleAdminManagementSnapshot>>());
      final snapshot = (result as Success<SimpleAdminManagementSnapshot>).data;
      expect(snapshot.tenantId, 'saas_hilal');
      expect(snapshot.accounts, hasLength(1));
      expect(snapshot.invitations, hasLength(1));
    });

    test('a role label alone cannot grant access', () async {
      final result = await repository(canManage: false).readCurrent();
      expect(result, isA<Failure<SimpleAdminManagementSnapshot>>());
      expect(
        (result as Failure<SimpleAdminManagementSnapshot>).code,
        SimpleAdminProblemCode.notPermitted.wire,
      );
    });

    test('a missing tenant context fails closed', () async {
      final result =
          await repository(canManage: true, tenantId: null).readCurrent();
      expect(
        (result as Failure<SimpleAdminManagementSnapshot>).code,
        SimpleAdminProblemCode.contextUnavailable.wire,
      );
    });
  });

  group('invitation lifecycle', () {
    test('creates a tenant-bound pending Simple Admin authorization', () async {
      final store = SimpleAdminStore.seeded(now);
      final repo = repository(canManage: true, store: store);
      final result = await repo.invite(const InviteSimpleAdminCommand(
        email: ' New.Admin@Example.org ',
        suggestedName: 'مدير جديد',
        capabilityKeys: {Cap.detachmentView, Cap.memberView},
        expectedRevision: 1,
        idempotencyKey: 'op_1',
      ));

      final invitation = (result as Success<SimpleAdminInvitation>).data;
      expect(invitation.tenantId, 'saas_hilal');
      expect(invitation.email, 'new.admin@example.org');
      expect(invitation.status, SimpleAdminInvitationStatus.pending);
      expect(
          invitation.capabilities.global, {Cap.detachmentView, Cap.memberView});
      expect(store.accounts.values.map((a) => a.email),
          isNot(contains('new.admin@example.org')),
          reason: 'inviting never activates or creates an account');
    });

    test('rejects recursive administration and unknown capabilities', () async {
      for (final keys in [
        {Cap.adminManage},
        {'made.up.permission'},
      ]) {
        final result = await repository(canManage: true).invite(
          InviteSimpleAdminCommand(
            email: 'new@example.org',
            suggestedName: 'مدير',
            capabilityKeys: keys,
            expectedRevision: 1,
            idempotencyKey: 'op_bad',
          ),
        );
        expect((result as Failure<SimpleAdminInvitation>).code,
            SimpleAdminProblemCode.invalidInput.wire);
      }
    });

    test('cancels a pending invitation without deleting its audit record',
        () async {
      final store = SimpleAdminStore.seeded(now);
      final result = await repository(canManage: true, store: store).cancel(
        const CancelSimpleAdminInvitationCommand(
          invitationId: 'az_hilal_admin',
          expectedRevision: 1,
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(store.invitations['az_hilal_admin']!.status,
          SimpleAdminInvitationStatus.cancelled);
    });

    test('replays the same invitation idempotency key without duplication',
        () async {
      final store = SimpleAdminStore.seeded(now);
      final repo = repository(canManage: true, store: store);
      const command = InviteSimpleAdminCommand(
        email: 'safe@example.org',
        suggestedName: 'مدير',
        capabilityKeys: {Cap.detachmentView},
        expectedRevision: 1,
        idempotencyKey: 'op_replay',
      );
      final first = await repo.invite(command);
      final second = await repo.invite(command);
      expect((first as Success<SimpleAdminInvitation>).data.id,
          (second as Success<SimpleAdminInvitation>).data.id);
      expect(
          store.invitations.values.where((i) => i.email == 'safe@example.org'),
          hasLength(1));
    });

    test('updates an existing account only within the safe subset', () async {
      final store = SimpleAdminStore.seeded(now);
      final result =
          await repository(canManage: true, store: store).updateCapabilities(
        const UpdateSimpleAdminCapabilitiesCommand(
          accountId: 'u_demo_simple',
          capabilityKeys: {Cap.detachmentView, Cap.shiftManage},
          expectedRevision: 1,
        ),
      );
      final account = (result as Success<SimpleAdminAccount>).data;
      expect(
          account.capabilities.global, {Cap.detachmentView, Cap.shiftManage});
      expect(account.revision, 2);
    });
  });

  group('Point 18B — setup consumes the invitation', () {
    test('pending → accepted once; the account is created exactly once', () {
      final store = SimpleAdminStore.seeded(now);
      final before = store.revision;
      final invitation = store.invitations['az_hilal_admin']!;

      expect(
        store.acceptInvitation(
          invitationId: 'az_hilal_admin',
          accountId: 'acct_noura',
          displayName: 'نورة',
          now: now,
        ),
        isTrue,
      );
      expect(store.invitations['az_hilal_admin']!.status,
          SimpleAdminInvitationStatus.accepted);
      final account = store.accounts['acct_noura']!;
      expect(account.tenantId, invitation.tenantId);
      expect(account.email, invitation.email);
      expect(account.capabilities, invitation.capabilities);
      expect(store.revision, before + 1);

      // Idempotent replay: nothing changes, nothing is duplicated.
      expect(
        store.acceptInvitation(
          invitationId: 'az_hilal_admin',
          accountId: 'acct_noura',
          displayName: 'نورة',
          now: now,
        ),
        isFalse,
      );
      expect(store.accounts.values.where((a) => a.email == invitation.email),
          hasLength(1));
      expect(store.revision, before + 1);
    });

    test('a cancelled or expired invitation can never be consumed', () async {
      final store = SimpleAdminStore.seeded(now);
      final repo = repository(canManage: true, store: store);
      await repo.cancel(const CancelSimpleAdminInvitationCommand(
        invitationId: 'az_hilal_admin',
        expectedRevision: 1,
      ));
      expect(
        store.acceptInvitation(
          invitationId: 'az_hilal_admin',
          accountId: 'acct_noura',
          displayName: 'نورة',
          now: now,
        ),
        isFalse,
      );
      expect(store.accounts, isNot(contains('acct_noura')));

      final fresh = SimpleAdminStore.seeded(now);
      expect(
        fresh.acceptInvitation(
          invitationId: 'az_hilal_admin',
          accountId: 'acct_noura',
          displayName: 'نورة',
          now: now.add(const Duration(days: 8)),
        ),
        isFalse,
        reason: 'past its expiry the invitation reads expired',
      );
    });
  });
}
