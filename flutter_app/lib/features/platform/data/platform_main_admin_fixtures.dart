import '../domain/platform_main_admin_models.dart';
import '../domain/saas_tenant_models.dart';

/// The mock's stored state for one seat. The tenant reference is not stored:
/// it is composed from the canonical `PlatformTenantStore` at every read, so
/// a Point 9 lifecycle change is seen immediately and never duplicated.
class MainAdminSeatState {
  const MainAdminSeatState({
    required this.revision,
    required this.current,
    this.replacement,
  });

  final int revision;
  final MainAdminAccount current;
  final MainAdminReplacement? replacement;
}

/// Deterministic, Clock-positioned seats for the canonical subscribers.
///
/// Every seat is derived from the tenant record's own Main Admin contact, so
/// the Point 6 summary and the Point 14 resource describe the same person.
/// Three tenants carry a representative scenario on top:
///
/// | tenant | tenant lifecycle | seat |
/// | --- | --- | --- |
/// | `saas_hilal` (the demo tenant) | active | active |
/// | `saas_nabd` | active | pending setup, invitation outstanding |
/// | `saas_najd` | active | active + replacement pending |
/// | `saas_sahel` | active | suspended |
/// | `saas_rukn` | **suspended** | active (tenant × account interaction) |
///
/// Neutral development data: no credential, token, code or secret exists
/// here, and none of the names or addresses is a real person.
abstract final class MainAdminFixtures {
  static const pendingSetupTenantId = 'saas_nabd';
  static const replacementTenantId = 'saas_najd';
  static const suspendedAccountTenantId = 'saas_sahel';
  static const suspendedTenantId = 'saas_rukn';

  static const suspensionReason =
      'اشتباه في مشاركة بيانات الدخول بانتظار تأكيد الجهة';
  static const replacementReason =
      'طلبت الجهة تعيين مدير رئيسي جديد بعد انتقال المدير الحالي';
  static const designateName = 'ريم القحطاني';
  static const designateEmail = 'reem@najd-response.sa';

  /// The account id the mock gives a tenant's first Main Admin. Opaque to
  /// every consumer; a real backend assigns its own.
  static String accountIdFor(String tenantId) =>
      'ma_${tenantId.replaceFirst('saas_', '')}';

  static MainAdminSeatState derive(
    SaasTenant tenant, {
    required DateTime now,
    Duration? validity = kProvisionalMainAdminSetupValidity,
    bool scenarios = true,
  }) {
    final at = now.toUtc();
    final contact = tenant.mainAdmin;
    final accountId = accountIdFor(tenant.id);
    var activatedAt = tenant.createdAt.add(const Duration(days: 1));
    if (activatedAt.isAfter(at)) activatedAt = at;

    if (contact.provisioning == MainAdminProvisioning.pendingSetup) {
      return MainAdminSeatState(
        revision: 1,
        current: MainAdminAccount(
          accountId: accountId,
          displayName: contact.name,
          loginEmail: contact.email,
          status: MainAdminAccountStatus.pendingSetup,
          createdAt: tenant.createdAt,
          setup: MainAdminSetupState(
            status: MainAdminSetupStatus.outstanding,
            lastSentAt: tenant.createdAt,
            expiresAt: validity == null ? null : tenant.createdAt.add(validity),
          ),
        ),
      );
    }

    MainAdminAccount active() => MainAdminAccount(
          accountId: accountId,
          displayName: contact.name,
          loginEmail: contact.email,
          status: MainAdminAccountStatus.active,
          createdAt: tenant.createdAt,
          activatedAt: activatedAt,
        );

    if (!scenarios) return MainAdminSeatState(revision: 1, current: active());

    switch (tenant.id) {
      case suspendedAccountTenantId:
        return MainAdminSeatState(
          revision: 3,
          current: MainAdminAccount(
            accountId: accountId,
            displayName: contact.name,
            loginEmail: contact.email,
            status: MainAdminAccountStatus.suspended,
            createdAt: tenant.createdAt,
            activatedAt: activatedAt,
            suspension: MainAdminSuspension(
              suspendedAt: at.subtract(const Duration(days: 3)),
              reason: suspensionReason,
            ),
          ),
        );
      case replacementTenantId:
        final requestedAt = at.subtract(const Duration(days: 1));
        return MainAdminSeatState(
          revision: 2,
          current: active(),
          replacement: MainAdminReplacement(
            id: 'mar_${tenant.id.replaceFirst('saas_', '')}_1',
            status: MainAdminReplacementStatus.pending,
            designate: MainAdminDesignate(
              accountId: '${accountId}_2',
              displayName: designateName,
              loginEmail: designateEmail,
              setup: MainAdminSetupState(
                status: MainAdminSetupStatus.outstanding,
                lastSentAt: requestedAt,
                expiresAt: validity == null ? null : requestedAt.add(validity),
              ),
            ),
            requestedAt: requestedAt,
            reason: replacementReason,
          ),
        );
      default:
        return MainAdminSeatState(revision: 1, current: active());
    }
  }
}
