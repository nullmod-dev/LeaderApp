import '../../../core/access/capability.dart';
import '../../../core/network/api_client.dart';
import '../../../core/result/result.dart';
import '../domain/simple_admin_models.dart';
import '../domain/simple_admin_repository.dart';

/// `/tenant/simple-admins` and `/tenant/simple-admin-invitations/**`
/// (`docs/api/tenant-administration.md` §5). `admin.manage`, the assignable
/// key set, the `admins` limit and the revision compare-and-set are all
/// enforced by the server; the tenant is the caller's own.
class HttpSimpleAdminRepository implements SimpleAdminRepository {
  HttpSimpleAdminRepository(this._api, {required String? Function() tenantId})
      : _tenantId = tenantId;

  final ApiClient _api;
  final String? Function() _tenantId;

  @override
  Future<Result<SimpleAdminManagementSnapshot>> readCurrent() => _api.send(
        'GET',
        '/tenant/simple-admins',
        parse: (json) {
          final j = json as Map<String, dynamic>;
          final revision = j['revision'] as int;
          final accounts = [
            for (final row in (j['accounts'] as List?) ?? const [])
              _account(row as Map<String, dynamic>, revision),
          ];
          final invitations = [
            for (final row in (j['invitations'] as List?) ?? const [])
              _invitation(row as Map<String, dynamic>),
          ];
          return SimpleAdminManagementSnapshot(
            tenantId: _tenantId() ??
                (accounts.isNotEmpty
                    ? accounts.first.tenantId
                    : invitations.isNotEmpty
                        ? invitations.first.tenantId
                        : ''),
            accounts: accounts,
            invitations: invitations,
            revision: revision,
            readAt: DateTime.parse(j['readAt'] as String),
          );
        },
      );

  @override
  Future<Result<SimpleAdminInvitation>> invite(
    InviteSimpleAdminCommand command,
  ) =>
      _api.send(
        'POST',
        '/tenant/simple-admin-invitations',
        body: {
          'invitedEmail': command.email,
          'suggestedName': command.suggestedName,
          'capabilityKeys': command.capabilityKeys.toList(),
          if (command.detachmentIds.isNotEmpty)
            'detachmentIds': command.detachmentIds.toList(),
          'expectedRevision': command.expectedRevision,
        },
        idempotencyKey: command.idempotencyKey,
        parse: (json) => _invitation(json as Map<String, dynamic>),
      );

  @override
  Future<Result<void>> cancel(CancelSimpleAdminInvitationCommand command) =>
      _api.send(
        'POST',
        '/tenant/simple-admin-invitations/'
            '${Uri.encodeComponent(command.invitationId)}/cancel',
        body: {'expectedRevision': command.expectedRevision},
        idempotencyKey: ApiClient.newIdempotencyKey(),
        parse: (_) {},
      );

  /// The server answers the account alone; its revision is the one the
  /// compare-and-set just moved to.
  @override
  Future<Result<SimpleAdminAccount>> updateCapabilities(
    UpdateSimpleAdminCapabilitiesCommand command,
  ) =>
      _api.send(
        'PATCH',
        '/tenant/simple-admins/'
            '${Uri.encodeComponent(command.accountId)}/capabilities',
        body: {
          'capabilityKeys': command.capabilityKeys.toList(),
          // Absent = team-wide (the server's `grantFromKeys`).
          if (command.detachmentIds.isNotEmpty)
            'detachmentIds': command.detachmentIds.toList(),
          'expectedRevision': command.expectedRevision,
        },
        parse: (json) => _account(
          json as Map<String, dynamic>,
          command.expectedRevision + 1,
        ),
      );

  static SimpleAdminAccount _account(Map<String, dynamic> j, int revision) =>
      SimpleAdminAccount(
        id: j['id'] as String,
        tenantId: (j['tenantId'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        email: (j['email'] as String?) ?? '',
        capabilities: Capabilities.fromJson(
          (j['capabilities'] as Map<String, dynamic>?) ?? const {},
        ),
        status: j['status'] == 'suspended'
            ? SimpleAdminAccountStatus.suspended
            : SimpleAdminAccountStatus.active,
        revision: revision,
      );

  static SimpleAdminInvitation _invitation(Map<String, dynamic> j) =>
      SimpleAdminInvitation(
        id: j['id'] as String,
        tenantId: (j['tenantId'] as String?) ?? '',
        email: (j['email'] as String?) ?? '',
        suggestedName: (j['suggestedName'] as String?) ?? '',
        capabilities: Capabilities.fromJson(
          (j['capabilities'] as Map<String, dynamic>?) ?? const {},
        ),
        createdAt: DateTime.parse(j['createdAt'] as String),
        expiresAt: j['expiresAt'] is String
            ? DateTime.parse(j['expiresAt'] as String)
            : null,
        status: SimpleAdminInvitationStatus.values.firstWhere(
          (s) => s.name == j['status'],
          // `withdrawn` and anything newer read as no longer pending.
          orElse: () => SimpleAdminInvitationStatus.cancelled,
        ),
      );
}
