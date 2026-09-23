import '../../../core/result/result.dart';
import 'saas_tenant_models.dart';

/// The problem codes this module owns.
///
/// **Feature-owned, per the hybrid error architecture.** `core/problem` holds
/// the codes every screen shares — `not_found`, `validation`, `offline`,
/// `server` and the rest — and a feature adds only the domain conditions that
/// nothing else can express. Point 6 adds two, because two is what the flows
/// here actually produce; everything else it needs already exists in
/// `ProblemCode` and is reused rather than re-spelled.
///
/// Behaviour branches on the code and never on the message, exactly as
/// `FRONTEND-BACKEND-INTEGRATION.md` §2 requires.
enum SaasTenantProblemCode {
  /// The submitted Team Code is already assigned to another subscriber. A
  /// `409`, and the only conflict this Point can produce.
  teamCodeConflict('tenant_code_conflict'),

  /// The submitted Team Code is not a Team Code. Normally caught at the field;
  /// carried as a code so a direct `create` call is refused the same way.
  invalidTeamCode('invalid_tenant_code');

  const SaasTenantProblemCode(this.wire);
  final String wire;

  static SaasTenantProblemCode? parse(String? wire) {
    if (wire == null) return null;
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return null;
  }
}

/// The one seam between the platform's tenant screens and their data.
///
/// Four reads and one registration write. Subscription/limit writes remain in
/// `TenantSubscriptionRepository`; operational lifecycle writes remain in
/// `TenantLifecycleRepository`. Splitting commands does not split tenant truth:
/// all implementations share the canonical platform tenant store/backend.
///
/// **Cross-tenant by nature.** Every call here is made by a `super_admin`
/// platform session and is never scoped by `saasTenantId`; no implementation
/// may reach a tenant-operational endpoint or repository to answer one. The
/// counts on a tenant record arrive *with* the record.
abstract class SaasTenantRepository {
  /// One page of subscribers matching [query], newest first.
  ///
  /// Search and status filtering are the repository's job so that a backend
  /// can take them over unchanged. Ordering is stable and total: a repeated
  /// call with the same query returns the same rows in the same order.
  Future<Result<SaasTenantPage>> list(SaasTenantQuery query);

  /// One subscriber. `not_found` when [tenantId] names none.
  Future<Result<SaasTenant>> byId(String tenantId);

  /// Registers a new subscriber and identifies its initial Main Admin.
  ///
  /// The draft is normalized and validated here — the form's own validation is
  /// a courtesy to the operator, not the gate. Refusals are
  /// `ProblemCode.validation` with per-field detail, or
  /// [SaasTenantProblemCode.teamCodeConflict] when the code is taken.
  ///
  /// **Returns no credential.** The created tenant's Main Admin is
  /// `pendingSetup`; the invitation, the email-ownership proof and the first
  /// password are the later authentication flow's, and nothing in this method
  /// generates, returns or stores one.
  Future<Result<SaasTenant>> create(SaasTenantDraft draft);

  /// The tenant's lifecycle history, newest first. Read-only, and not the
  /// platform audit log.
  Future<Result<List<SaasTenantEvent>>> statusHistory(String tenantId);
}
