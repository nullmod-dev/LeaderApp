import '../../../core/result/result.dart';
import 'simple_admin_models.dart';

enum SimpleAdminProblemCode {
  notPermitted('not_permitted'),
  contextUnavailable('tenant_context_unavailable'),
  invalidInput('validation'),
  duplicateEmail('admin_invitation_exists'),
  stale('stale_admin_management'),
  notFound('not_found');

  const SimpleAdminProblemCode(this.wire);
  final String wire;
}

abstract class SimpleAdminRepository {
  Future<Result<SimpleAdminManagementSnapshot>> readCurrent();

  Future<Result<SimpleAdminInvitation>> invite(
      InviteSimpleAdminCommand command);

  Future<Result<void>> cancel(CancelSimpleAdminInvitationCommand command);

  Future<Result<SimpleAdminAccount>> updateCapabilities(
    UpdateSimpleAdminCapabilitiesCommand command,
  );
}
