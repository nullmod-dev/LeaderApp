import '../../../core/result/result.dart';
import 'organization_models.dart';

/// Typed failures of the tenant organisation read. Everything else resolves
/// through the shared `ProblemCode` pipeline.
enum OrganizationProblemCode {
  /// The session is not inside a real `SaasTenant` (a customer Demo, or a
  /// Super Admin that somehow asked). Designed state, never a crash.
  contextUnavailable('tenant_context_unavailable');

  const OrganizationProblemCode(this.wire);
  final String wire;

  static OrganizationProblemCode? parse(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return null;
  }
}

/// The read-only tenant adapter Point 7 left room for: the models the
/// platform owns, seen through a seam that has **no** write.
///
/// There is no tenant id parameter on purpose. A tenant session may only read
/// its own organisation, and the backend derives which one from the bearer —
/// a client-chosen id would be an invitation to ask for somebody else's.
abstract class OrganizationRepository {
  Future<Result<OrganizationSnapshot>> readCurrent();
}
