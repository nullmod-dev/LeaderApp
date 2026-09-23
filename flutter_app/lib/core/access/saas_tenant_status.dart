/// The canonical operational lifecycle of one SaaS tenant.
///
/// This is deliberately not subscription standing, feature availability,
/// administrator capability, account lifecycle, or a plan limit. It is shared
/// by the platform tenant record and the authenticated session envelope so the
/// control plane and startup classifier cannot develop two status vocabularies.
enum SaasTenantStatus {
  active('active'),
  suspended('suspended'),
  deletionPending('deletion_pending'),
  deleted('deleted');

  const SaasTenantStatus(this.wire);

  final String wire;

  static SaasTenantStatus? tryParse(String wire) {
    for (final status in values) {
      if (status.wire == wire) return status;
    }
    return null;
  }

  static SaasTenantStatus? parse(String? wire) =>
      wire == null ? null : tryParse(wire);

  /// Only [active] opens the operational tenant application.
  bool get blocksTenantAccess => this != active;

  bool get needsAttention => this == suspended || this == deletionPending;

  bool get isTerminal => this == deleted;
}
