import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/platform/domain/platform_break_glass_models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 11, 9);
  final tenant = BreakGlassTenantReference(
    tenantId: 'saas_hilal',
    displayName: 'فرق الهلال الطبية',
  );
  final initiator = BreakGlassInitiator(
    accountId: 'u_demo_platform',
    displayName: 'مدير منصة MTM',
  );
  const read = {BreakGlassScope.tenantOperationalRead};

  BreakGlassTransitionDecision activate({
    SaasTenantStatus? status = SaasTenantStatus.active,
    Set<BreakGlassScope> scopes = read,
    String reason = 'تعذّر على قائد الفريق الوصول',
    BreakGlassGrant? current,
    DateTime? at,
  }) =>
      BreakGlassPolicy.activate(
        grantId: 'bg_1',
        tenant: tenant,
        tenantStatus: status,
        scopes: scopes,
        reason: reason,
        initiator: initiator,
        now: at ?? now,
        current: current,
      );

  BreakGlassGrant grantOf(BreakGlassTransitionDecision decision) =>
      (decision as BreakGlassTransitionAllowed).grant;

  BreakGlassTransitionProblem problemOf(BreakGlassTransitionDecision d) =>
      (d as BreakGlassTransitionRefused).problem;

  group('state machine', () {
    test('activation issues one active, scoped, server-shaped grant', () {
      final grant = grantOf(activate(reason: '  سبب   موثق \n للوصول '));
      expect(grant.status, BreakGlassGrantStatus.active);
      expect(grant.revision, 1);
      expect(grant.issuedAt, now);
      expect(grant.expiresAt, now.add(kProvisionalBreakGlassGrantDuration));
      expect(grant.reason, 'سبب موثق للوصول');
      expect(grant.scopes, read);
      expect(grant.endedAt, isNull);
      expect(() => grant.scopes.add(BreakGlassScope.tenantOperationalRead),
          throwsUnsupportedError);
    });

    test('initiator end is legal once and terminal afterwards', () {
      final active = grantOf(activate());
      final later = now.add(const Duration(minutes: 7));
      final ended = grantOf(BreakGlassPolicy.end(grant: active, now: later));
      expect(ended.status, BreakGlassGrantStatus.ended);
      expect(ended.endReason, BreakGlassEndReason.endedByInitiator);
      expect(ended.endedAt, later);
      expect(ended.revision, 2);
      expect(ended.id, active.id);
      expect(
        problemOf(BreakGlassPolicy.end(grant: ended, now: later)),
        BreakGlassTransitionProblem.grantNotActive,
      );
    });

    test('backend invalidation ends with a typed reason', () {
      final active = grantOf(activate());
      for (final reason in [
        BreakGlassEndReason.sessionEnded,
        BreakGlassEndReason.tenantUnavailable,
        BreakGlassEndReason.revokedByPlatform,
      ]) {
        final ended = grantOf(BreakGlassPolicy.terminate(
          grant: active,
          reason: reason,
          now: now,
        ));
        expect(ended.status, BreakGlassGrantStatus.ended);
        expect(ended.endReason, reason);
      }
      expect(
        () => BreakGlassPolicy.terminate(
          grant: active,
          reason: BreakGlassEndReason.unknown,
          now: now,
        ),
        throwsArgumentError,
      );
    });

    test('expiry boundary fails closed at exactly expiresAt', () {
      final grant = grantOf(activate());
      final justBefore =
          grant.expiresAt.subtract(const Duration(microseconds: 1));
      expect(grant.effectiveStatusAt(justBefore), BreakGlassGrantStatus.active);
      expect(grant.remainingAt(justBefore), const Duration(microseconds: 1));
      expect(grant.effectiveStatusAt(grant.expiresAt),
          BreakGlassGrantStatus.expired);
      expect(grant.remainingAt(grant.expiresAt), Duration.zero);
      expect(
        problemOf(BreakGlassPolicy.end(grant: grant, now: grant.expiresAt)),
        BreakGlassTransitionProblem.grantNotActive,
      );

      final settled = BreakGlassPolicy.settle(grant, grant.expiresAt);
      expect(settled.status, BreakGlassGrantStatus.expired);
      expect(settled.revision, 2);
      expect(
          identical(BreakGlassPolicy.settle(grant, justBefore), grant), isTrue);
    });

    test('one possibly-live grant per session; terminal ones do not block', () {
      final active = grantOf(activate());
      expect(problemOf(activate(current: active)),
          BreakGlassTransitionProblem.grantAlreadyActive);

      final ended = grantOf(BreakGlassPolicy.end(grant: active, now: now));
      expect(activate(current: ended), isA<BreakGlassTransitionAllowed>());
      expect(activate(current: active, at: active.expiresAt),
          isA<BreakGlassTransitionAllowed>());
    });

    test('constructor rejects impossible grants', () {
      BreakGlassGrant build({
        BreakGlassGrantStatus status = BreakGlassGrantStatus.active,
        DateTime? expiresAt,
        DateTime? endedAt,
        BreakGlassEndReason? endReason,
        int revision = 1,
      }) =>
          BreakGlassGrant(
            id: 'bg',
            revision: revision,
            tenant: tenant,
            scopes: read,
            reason: 'سبب',
            initiator: initiator,
            issuedAt: now,
            expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
            status: status,
            endedAt: endedAt,
            endReason: endReason,
          );

      expect(() => build(expiresAt: now), throwsArgumentError);
      expect(() => build(revision: 0), throwsArgumentError);
      expect(() => build(status: BreakGlassGrantStatus.ended),
          throwsArgumentError);
      expect(
        () => build(
          endedAt: now,
          endReason: BreakGlassEndReason.endedByInitiator,
        ),
        throwsArgumentError,
      );
    });
  });

  group('scope and reason', () {
    test('empty scope is refused and no scope permits writes', () {
      expect(problemOf(activate(scopes: const {})),
          BreakGlassTransitionProblem.invalidScope);
      expect(BreakGlassScope.values.every((scope) => !scope.permitsWrites),
          isTrue);
    });

    test('reason follows the Point 9 administrative convention', () {
      expect(kBreakGlassReasonMaxLength, 280);
      expect(problemOf(activate(reason: '   \n ')),
          BreakGlassTransitionProblem.invalidReason);
      expect(problemOf(activate(reason: 'x' * 281)),
          BreakGlassTransitionProblem.invalidReason);
      expect(activate(reason: 'x' * 280), isA<BreakGlassTransitionAllowed>());
    });
  });

  group('tenant lifecycle precedence', () {
    test('only an active tenant is eligible', () {
      expect(BreakGlassPolicy.tenantEligibility(SaasTenantStatus.active),
          BreakGlassTenantEligibility.eligible);
      expect(problemOf(activate(status: SaasTenantStatus.suspended)),
          BreakGlassTransitionProblem.tenantNotEligible);
      expect(problemOf(activate(status: SaasTenantStatus.deletionPending)),
          BreakGlassTransitionProblem.tenantNotEligible);
      expect(problemOf(activate(status: SaasTenantStatus.deleted)),
          BreakGlassTransitionProblem.tenantDeleted);
      expect(problemOf(activate(status: null)),
          BreakGlassTransitionProblem.tenantNotFound);
    });
  });

  group('wire format', () {
    Map<String, dynamic> wire() => grantOf(activate()).toJson();

    test('round-trips and carries no sensitive field', () {
      final json = wire();
      final parsed = BreakGlassGrant.fromJson(json);
      expect(parsed.toJson(), json);
      final keys = json.toString().toLowerCase();
      for (final forbidden in [
        'teamcode',
        'email',
        'token',
        'password',
        'otp',
        'session',
        'capabilit',
        'subscription',
      ]) {
        expect(keys.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('unknown status, scope and end reason fail closed', () {
      final unknownStatus = BreakGlassGrant.fromJson(
        {...wire(), 'status': 'pending_approval'},
      );
      expect(unknownStatus.status, BreakGlassGrantStatus.unknown);
      expect(unknownStatus.isActiveAt(now), isFalse);
      expect(unknownStatus.isPossiblyLiveAt(now), isTrue);

      final mixedScopes = BreakGlassGrant.fromJson({
        ...wire(),
        'scopes': const ['tenant_operational_read', 'tenant_full_admin'],
      });
      expect(mixedScopes.scopes, read);
      expect(mixedScopes.hasUnsupportedScope, isTrue);

      final onlyUnknown = BreakGlassGrant.fromJson({
        ...wire(),
        'scopes': const ['all']
      });
      expect(onlyUnknown.scopes, isEmpty);

      final endReason = BreakGlassGrant.fromJson({
        ...wire(),
        'status': 'ended',
        'endedAt': now.toIso8601String(),
        'endReason': 'future_reason',
      });
      expect(endReason.endReason, BreakGlassEndReason.unknown);
    });

    test('malformed grants are unreadable, never partially usable', () {
      for (final broken in <Map<String, dynamic>>[
        {...wire(), 'id': ''},
        {...wire(), 'scopes': 'tenant_operational_read'},
        {...wire(), 'expiresAt': now.toIso8601String()},
        {...wire(), 'issuedAt': 'yesterday'},
        {...wire(), 'reason': ''},
        {...wire(), 'status': 'ended'},
        {...wire()}..remove('tenant'),
      ]) {
        expect(() => BreakGlassGrant.fromJson(broken), throwsFormatException);
      }
    });
  });

  group('access policy', () {
    BreakGlassAccessDecision evaluate({
      AuthRole? role = AuthRole.superAdmin,
      BreakGlassGrant? grant,
      bool confirmed = true,
      SaasTenantStatus? tenantStatus = SaasTenantStatus.active,
      DateTime? at,
    }) =>
        BreakGlassAccessPolicy.evaluate(
          sessionRole: role,
          grant: grant,
          confirmed: confirmed,
          targetTenantStatus: tenantStatus,
          now: at ?? now,
        );

    test('usable only for a confirmed active grant on an active tenant', () {
      final grant = grantOf(activate());
      final decision = evaluate(grant: grant);
      expect(decision.state, BreakGlassAccessState.usable);
      expect(decision.permits(BreakGlassScope.tenantOperationalRead), isTrue);
      expect(decision.isPossiblyLive, isTrue);
      expect(decision.isNearExpiry, isFalse);
    });

    test('never attaches to a non-Super-Admin or absent session', () {
      final grant = grantOf(activate());
      for (final role in [AuthRole.mainAdmin, AuthRole.admin, null]) {
        final decision = evaluate(role: role, grant: grant);
        expect(decision.state, BreakGlassAccessState.none);
        expect(
            decision.permits(BreakGlassScope.tenantOperationalRead), isFalse);
        expect(decision.isPossiblyLive, isFalse);
      }
    });

    test('unconfirmed, tenant-blocked, expired and unknown are unusable', () {
      final grant = grantOf(activate());
      final unverified = evaluate(grant: grant, confirmed: false);
      expect(unverified.state, BreakGlassAccessState.unverified);
      expect(unverified.isPossiblyLive, isTrue);
      expect(unverified.isUsable, isFalse);

      for (final status in [
        SaasTenantStatus.suspended,
        SaasTenantStatus.deletionPending,
        SaasTenantStatus.deleted,
        null,
      ]) {
        expect(evaluate(grant: grant, tenantStatus: status).state,
            BreakGlassAccessState.tenantUnavailable);
      }

      final expired = evaluate(grant: grant, at: grant.expiresAt);
      expect(expired.state, BreakGlassAccessState.expired);
      expect(expired.isPossiblyLive, isFalse);

      final unknown = evaluate(
        grant: BreakGlassGrant.fromJson(
          {...grant.toJson(), 'status': 'future_state'},
        ),
      );
      expect(unknown.state, BreakGlassAccessState.unsupported);
      expect(unknown.isPossiblyLive, isTrue);

      final noKnownScope = evaluate(
        grant: BreakGlassGrant.fromJson({
          ...grant.toJson(),
          'scopes': const ['everything'],
        }),
      );
      expect(noKnownScope.state, BreakGlassAccessState.unsupported);
    });

    test('near-expiry window is presentation only', () {
      final grant = grantOf(activate());
      final near = evaluate(
        grant: grant,
        at: grant.expiresAt.subtract(kBreakGlassNearExpiryWindow),
      );
      expect(near.isNearExpiry, isTrue);
      expect(near.isUsable, isTrue);
    });
  });
}
