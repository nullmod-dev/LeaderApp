import '../domain/platform_break_glass_models.dart';

/// Representative starting states for the break-glass mock. Neutral
/// development scenarios, not claims of real emergencies.
enum BreakGlassFixtureScenario {
  none,
  active,
  nearExpiry,
  expired,
  ended,
  revoked,

  /// A status this build does not recognise, still before its expiry.
  unsupported,
}

/// Builds the seeded grant for a scenario from one injected `Clock` reading.
abstract final class BreakGlassFixtures {
  /// An active fixture tenant, so a seeded active grant is usable.
  static const tenantId = 'saas_hilal';

  static const reason = 'تعذّر على قائد الفريق الوصول إلى سجلات المناوبات';

  static BreakGlassGrant? seed(
    BreakGlassFixtureScenario scenario, {
    required DateTime now,
    required BreakGlassTenantReference tenant,
    required BreakGlassInitiator initiator,
    Duration duration = kProvisionalBreakGlassGrantDuration,
  }) {
    final at = now.toUtc();
    BreakGlassGrant grant({
      required DateTime issuedAt,
      required BreakGlassGrantStatus status,
      int revision = 1,
      DateTime? endedAt,
      BreakGlassEndReason? endReason,
    }) =>
        BreakGlassGrant(
          id: 'bg_fixture_${scenario.name}',
          revision: revision,
          tenant: tenant,
          scopes: const {BreakGlassScope.tenantOperationalRead},
          reason: reason,
          initiator: initiator,
          issuedAt: issuedAt,
          expiresAt: issuedAt.add(duration),
          status: status,
          endedAt: endedAt,
          endReason: endReason,
        );

    return switch (scenario) {
      BreakGlassFixtureScenario.none => null,
      BreakGlassFixtureScenario.active => grant(
          issuedAt: at.subtract(const Duration(minutes: 5)),
          status: BreakGlassGrantStatus.active,
        ),
      BreakGlassFixtureScenario.nearExpiry => grant(
          issuedAt: at.subtract(duration - const Duration(minutes: 4)),
          status: BreakGlassGrantStatus.active,
        ),
      BreakGlassFixtureScenario.expired => grant(
          issuedAt: at.subtract(duration + const Duration(minutes: 20)),
          status: BreakGlassGrantStatus.expired,
          revision: 2,
        ),
      BreakGlassFixtureScenario.ended => grant(
          issuedAt: at.subtract(const Duration(minutes: 30)),
          status: BreakGlassGrantStatus.ended,
          revision: 2,
          endedAt: at.subtract(const Duration(minutes: 12)),
          endReason: BreakGlassEndReason.endedByInitiator,
        ),
      BreakGlassFixtureScenario.revoked => grant(
          issuedAt: at.subtract(const Duration(minutes: 30)),
          status: BreakGlassGrantStatus.ended,
          revision: 2,
          endedAt: at.subtract(const Duration(minutes: 8)),
          endReason: BreakGlassEndReason.revokedByPlatform,
        ),
      BreakGlassFixtureScenario.unsupported => grant(
          issuedAt: at.subtract(const Duration(minutes: 5)),
          status: BreakGlassGrantStatus.unknown,
        ),
    };
  }
}
