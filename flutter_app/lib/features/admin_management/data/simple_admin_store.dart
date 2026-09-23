import '../../../core/access/capability.dart';
import '../../../core/access/capability_presets.dart';
import '../domain/simple_admin_models.dart';

class SimpleAdminStore {
  SimpleAdminStore.seeded(DateTime now)
      : revision = 1,
        invitationOperations = {},
        accounts = {
          'u_demo_simple': SimpleAdminAccount(
            id: 'u_demo_simple',
            tenantId: 'saas_hilal',
            name: 'سامر الحلبي',
            email: 'hamodekaherhm@gmail.com',
            capabilities: Capabilities(
              global: CapabilityPreset.subAdmin.keys,
            ),
            status: SimpleAdminAccountStatus.active,
            revision: 1,
          ),
        },
        invitations = {
          'az_hilal_admin': SimpleAdminInvitation(
            id: 'az_hilal_admin',
            tenantId: 'saas_hilal',
            email: 'noura@hilal-medical.org',
            suggestedName: 'نورة الدوسري',
            capabilities: Capabilities(
              global: CapabilityPreset.subAdmin.keys,
            ),
            createdAt: now.toUtc(),
            expiresAt: now.toUtc().add(const Duration(days: 7)),
            status: SimpleAdminInvitationStatus.pending,
          ),
        };

  final Map<String, SimpleAdminAccount> accounts;
  final Map<String, SimpleAdminInvitation> invitations;
  final Map<String, String> invitationOperations;
  int revision;

  /// Point 18B — the Simple Admin half of the invitee's setup transaction:
  /// `pending` → `accepted`, and the account appears with exactly the
  /// invitation's tenant, email and capability grant (never anything the
  /// invitee typed except the display name).
  ///
  /// Idempotent: an invitation that is no longer `pending` changes nothing,
  /// and the account is keyed by the canonical account id, so a retried
  /// completion can never create a second admin relationship. A cancelled or
  /// expired invitation is never accepted here — the onboarding backend
  /// already refused its setup. Returns whether anything changed.
  bool acceptInvitation({
    required String invitationId,
    required String accountId,
    required String displayName,
    required DateTime now,
  }) {
    final invitation = invitations[invitationId];
    if (invitation == null ||
        invitation.effectiveStatus(now) !=
            SimpleAdminInvitationStatus.pending) {
      return false;
    }
    invitations[invitationId] =
        invitation.copyWith(status: SimpleAdminInvitationStatus.accepted);
    accounts.putIfAbsent(
      accountId,
      () => SimpleAdminAccount(
        id: accountId,
        tenantId: invitation.tenantId,
        name: displayName.isEmpty ? invitation.suggestedName : displayName,
        email: invitation.email,
        capabilities: invitation.capabilities,
        status: SimpleAdminAccountStatus.active,
        revision: 1,
      ),
    );
    revision++;
    return true;
  }
}
