import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/result/result.dart';
import 'package:mtm/core/time/clock.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/data/demo_personas.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/platform/data/platform_audit_providers.dart';
import 'package:mtm/features/platform/data/platform_break_glass_providers.dart';
import 'package:mtm/features/platform/data/platform_operations_providers.dart';
import 'package:mtm/features/platform/data/saas_tenant_providers.dart';
import 'package:mtm/features/platform/data/tenant_lifecycle_providers.dart';
import 'package:mtm/features/platform/domain/platform_audit_models.dart';
import 'package:mtm/features/platform/domain/platform_break_glass_models.dart';
import 'package:mtm/features/platform/domain/platform_break_glass_repository.dart';
import 'package:mtm/features/platform/domain/platform_security_models.dart';
import 'package:mtm/features/platform/domain/tenant_lifecycle_models.dart';

final _signedIn =
    StateProvider<AuthUser?>((ref) => DemoPersona.superAdmin.user);

void main() {
  var now = DateTime.utc(2026, 9, 11, 9);

  setUp(() => now = DateTime.utc(2026, 9, 11, 9));

  ProviderContainer container({Duration latency = Duration.zero}) {
    final result = ProviderContainer(overrides: [
      clockProvider.overrideWithValue(() => now),
      currentUserProvider.overrideWith((ref) async => ref.watch(_signedIn)),
      breakGlassMockConfigProvider.overrideWithValue(
        BreakGlassMockConfig(latency: latency),
      ),
    ]);
    addTearDown(result.dispose);
    return result;
  }

  ActivateBreakGlassCommand activation(ProviderContainer c, {String? key}) {
    final tenant = c.read(platformTenantStoreProvider).byId('saas_hilal')!;
    return ActivateBreakGlassCommand(
      tenantId: tenant.id,
      expectedTenantVersion: tenant.tenantVersion,
      scopes: const {BreakGlassScope.tenantOperationalRead},
      reason: 'تعذّر على قائد الفريق الوصول',
      idempotencyKey: breakGlassActivationIdempotencyKey(key ?? 'attempt-1'),
    );
  }

  Future<BreakGlassAccessDecision> access(ProviderContainer c) async {
    await c.read(currentUserProvider.future);
    await c.read(breakGlassCurrentProvider.future);
    return c.read(breakGlassAccessProvider);
  }

  Future<BreakGlassGrant> activate(ProviderContainer c) async {
    await c.read(currentUserProvider.future);
    final outcome = await c
        .read(breakGlassActionControllerProvider.notifier)
        .activate(activation(c));
    return (outcome as BreakGlassActionSucceeded).result.grant;
  }

  test('emergency authority never becomes the account role or a Cap grant',
      () async {
    final c = container();
    await activate(c);
    expect((await access(c)).isUsable, isTrue);

    final user = (await c.read(currentUserProvider.future))!;
    expect(user.role, AuthRole.superAdmin);
    expect(user.saasTenantId, isNull);
    expect(user.capabilities.toJson(), Capabilities.none.toJson());
    expect(c.read(authRoleProvider), AuthRole.superAdmin);
  });

  test('sign-out removes the grant and a new session starts with none',
      () async {
    final c = container();
    await activate(c);
    expect((await access(c)).isUsable, isTrue);

    c.read(_signedIn.notifier).state = null;
    final signedOut = await access(c);
    expect(signedOut.state, BreakGlassAccessState.none);
    expect(signedOut.isPossiblyLive, isFalse);
    expect(await c.read(breakGlassCurrentProvider.future),
        isA<Failure<BreakGlassSnapshot>>());

    c.read(_signedIn.notifier).state = DemoPersona.superAdmin.user;
    final again = await access(c);
    expect(again.state, BreakGlassAccessState.none);
    final snapshot = (await c.read(breakGlassCurrentProvider.future))
        as Success<BreakGlassSnapshot>;
    expect(snapshot.data.grant, isNull);
  });

  test('expiry removes exceptional authority without waiting for a read',
      () async {
    final c = container();
    final grant = await activate(c);
    expect((await access(c)).isUsable, isTrue);

    now = grant.expiresAt;
    c.invalidate(breakGlassAccessProvider);
    final expired = c.read(breakGlassAccessProvider);
    expect(expired.state, BreakGlassAccessState.expired);
    expect(expired.permits(BreakGlassScope.tenantOperationalRead), isFalse);
    expect(expired.isPossiblyLive, isFalse);
  });

  test('a tenant lifecycle change removes usable authority immediately',
      () async {
    final c = container();
    final grant = await activate(c);
    expect((await access(c)).isUsable, isTrue);

    final tenant =
        c.read(platformTenantStoreProvider).byId(grant.tenant.tenantId)!;
    final outcome = await c
        .read(tenantLifecycleActionControllerProvider.notifier)
        .suspend(SuspendTenantCommand(
          tenantId: tenant.id,
          expectedVersion: tenant.tenantVersion,
          idempotencyKey: 'suspend-during-grant',
          reason: 'مراجعة موثقة',
        ));
    expect(outcome, isA<TenantLifecycleActionSucceeded>());
    expect(c.read(breakGlassAccessProvider).state,
        BreakGlassAccessState.tenantUnavailable);

    c.invalidate(breakGlassCurrentProvider);
    final reread = await access(c);
    expect(reread.state, BreakGlassAccessState.ended);
    expect(reread.grant!.endReason, BreakGlassEndReason.tenantUnavailable);
  });

  test('a tenant session is refused and holds no emergency authority',
      () async {
    final c = container();
    c.read(_signedIn.notifier).state = DemoPersona.mainAdmin.user;
    await c.read(currentUserProvider.future);
    final outcome = await c
        .read(breakGlassActionControllerProvider.notifier)
        .activate(activation(c));
    expect(outcome, isA<BreakGlassActionNotPermitted>());
    expect((await access(c)).state, BreakGlassAccessState.none);
  });

  test('controller blocks a duplicate submit and ends the grant once',
      () async {
    final c = container(latency: const Duration(milliseconds: 20));
    await c.read(currentUserProvider.future);
    final controller = c.read(breakGlassActionControllerProvider.notifier);
    final first = controller.activate(activation(c));
    expect(await controller.activate(activation(c)),
        isA<BreakGlassActionIgnored>());
    final grant = ((await first) as BreakGlassActionSucceeded).result.grant;
    expect(c.read(breakGlassActionControllerProvider).isSubmitting, isFalse);

    final end = EndBreakGlassCommand(
      grantId: grant.id,
      expectedRevision: grant.revision,
      idempotencyKey: breakGlassEndIdempotencyKey(
        grantId: grant.id,
        expectedRevision: grant.revision,
      ),
    );
    expect(await controller.end(end), isA<BreakGlassActionSucceeded>());
    expect((await access(c)).state, BreakGlassAccessState.ended);

    final stale = await controller.end(EndBreakGlassCommand(
      grantId: grant.id,
      expectedRevision: grant.revision,
      idempotencyKey: 'end-again-new-key',
    ));
    expect(stale, isA<BreakGlassActionInvalid>());
    expect((stale as BreakGlassActionInvalid).code,
        BreakGlassProblemCode.grantNotActive);
  });

  test('Platform Audit and Security stay read-only and untouched', () async {
    final c = container();
    List<String> auditIds(Result<PlatformAuditPage> page) =>
        (page as Success<PlatformAuditPage>)
            .data
            .items
            .map((event) => event.id)
            .toList();

    final query = PlatformAuditQuery(limit: 100);
    final auditBefore =
        await c.read(platformAuditRepositoryProvider).listAuditEvents(query);
    final securityBefore =
        await c.read(platformSecurityRepositoryProvider).loadSecurityAlerts();

    final grant = await activate(c);
    await c.read(breakGlassActionControllerProvider.notifier).end(
          EndBreakGlassCommand(
            grantId: grant.id,
            expectedRevision: grant.revision,
            idempotencyKey: 'end',
          ),
        );

    final auditAfter =
        await c.read(platformAuditRepositoryProvider).listAuditEvents(query);
    final securityAfter =
        await c.read(platformSecurityRepositoryProvider).loadSecurityAlerts();
    expect(auditIds(auditAfter), auditIds(auditBefore));
    List<String> alertIds(Result<PlatformSecuritySnapshot> r) =>
        (r as Success<PlatformSecuritySnapshot>)
            .data
            .alerts
            .map((alert) => alert.id)
            .toList();
    expect(alertIds(securityAfter), alertIds(securityBefore));
  });
}
