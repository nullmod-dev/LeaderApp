import 'package:flutter_test/flutter_test.dart';
import 'package:mtm/core/access/saas_tenant_status.dart';
import 'package:mtm/core/access/capability.dart';
import 'package:mtm/core/startup/startup_destination.dart';
import 'package:mtm/features/app_version/presentation/upgrade_required_page.dart';
import 'package:mtm/features/auth/data/auth_providers.dart';
import 'package:mtm/features/auth/domain/auth_models.dart';
import 'package:mtm/features/auth/domain/session_access.dart';
import 'package:mtm/features/platform/presentation/platform_shell.dart';
import 'package:mtm/features/auth/presentation/startup_page.dart';
import 'package:mtm/features/auth/presentation/status_pages.dart';

/// The startup decision table, tested where it is decided.
///
/// `resolveStartup` is a pure function, so every row below is a direct call —
/// no widget, no container, no pumping. That is the reason the decision was
/// lifted out of the router's `redirect` closure in the first place: a state
/// table nobody can call is a state table nobody checks, and the states that
/// matter most here (revoked, suspended, deleted, demo) are the ones no
/// backend produces yet.
void main() {
  final now = DateTime.utc(2026, 9, 8, 12);

  StartupDestination resolve({
    AuthGate gate = AuthGate.signedIn,
    AuthUser? user,
    bool upgradeBlocks = false,
    SessionAccess access = SessionAccess.normal,
    bool? hasCapability,
  }) =>
      resolveStartup(StartupInputs(
        gate: gate,
        now: now,
        user: user,
        upgradeBlocks: upgradeBlocks,
        access: access,
        hasTenantCapability:
            hasCapability ?? (user?.capabilities.hasAny ?? false),
      ));

  group('authentication', () {
    test('a read still in flight holds the loading surface', () {
      expect(resolve(gate: AuthGate.restoring), StartupDestination.restoring);
    });

    test('a definitively signed-out session goes to login', () {
      expect(resolve(gate: AuthGate.signedOut), StartupDestination.signedOut);
    });

    test('an expired session goes to its own screen, not login', () {
      expect(
          resolve(gate: AuthGate.expired), StartupDestination.sessionExpired);
    });

    test('a server-issued expiry at or before the local instant is expired',
        () {
      for (final expiry in [now, now.subtract(const Duration(seconds: 1))]) {
        expect(
          resolve(
            user: _mainAdmin,
            access: SessionAccess(sessionExpiresAt: expiry),
          ),
          StartupDestination.sessionExpired,
        );
      }
    });

    test('a future server-issued expiry keeps the session open', () {
      expect(
        resolve(
          user: _mainAdmin,
          access: SessionAccess(
            sessionExpiresAt: now.add(const Duration(seconds: 1)),
          ),
        ),
        StartupDestination.tenantSurface,
      );
    });

    test('an invalid account fails closed onto its own screen', () {
      expect(
          resolve(gate: AuthGate.invalid), StartupDestination.invalidSession);
    });

    test('an inconclusive read decides nothing at all', () {
      // Offline with no cached account. Not a sign-out, and not a reason to
      // park an offline-first app on a splash screen either.
      final destination = resolve(gate: AuthGate.unknown);
      expect(destination, StartupDestination.unresolved);
      expect(destination.location, isNull);
      expect(destination.isProductSurface, isFalse);
    });
  });

  group('role selects the surface', () {
    test('super_admin resolves to the platform, never the tenant app', () {
      expect(
        resolve(user: _superAdmin),
        StartupDestination.platformSurface,
      );
    });

    test('main_admin resolves to the tenant application', () {
      expect(resolve(user: _mainAdmin), StartupDestination.tenantSurface);
      expect(StartupDestination.tenantSurface.location, isNull);
    });

    test('admin resolves to the same tenant application', () {
      expect(resolve(user: _simpleAdmin), StartupDestination.tenantSurface);
    });

    test(
        'a super_admin holding no tenant capability is still the platform, '
        'not «no access»', () {
      // The regression this guards: `tenantNoAccess` is checked *after* the
      // role branch, so the platform owner — which holds `Capabilities.none`
      // by design — cannot fall into a tenant authorization outcome.
      expect(_superAdmin.capabilities.hasAny, isFalse);
      expect(resolve(user: _superAdmin), StartupDestination.platformSurface);
    });
  });

  group('malformed accounts fail closed on every path', () {
    test('a super_admin carrying a tenant id is refused', () {
      const broken = AuthUser(
        id: 'u',
        name: 'x',
        email: 'x@mtm.app',
        role: AuthRole.superAdmin,
        saasTenantId: 'saas_1',
        capabilities: Capabilities.none,
        orgName: 'MTM',
      );
      expect(broken.isWellFormed, isFalse);
      // Even handed in as a "signed in" account, which is the path a caller
      // assembling inputs by hand could take.
      expect(
        resolve(user: broken),
        StartupDestination.invalidSession,
        reason: 'a refused account must not reach the platform surface',
      );
    });

    test('a main_admin with no tenant id is refused', () {
      const broken = AuthUser(
        id: 'u',
        name: 'x',
        email: 'x@mtm.org',
        role: AuthRole.mainAdmin,
        saasTenantId: null,
        capabilities: Capabilities(global: Cap.all),
        orgName: 'MTM',
      );
      expect(
        resolve(user: broken),
        StartupDestination.invalidSession,
        reason: 'no tenant id may be invented for it',
      );
    });
  });

  group('authorization inside a valid tenant session', () {
    test('a tenant account holding nothing gets the no-access state', () {
      expect(
        resolve(user: _bareTenant),
        StartupDestination.tenantNoAccess,
      );
    });

    test('an empty grant is NOT read as suspended, revoked or unfinished', () {
      // §9 of the brief, as an assertion: the one thing that may be concluded
      // from an empty capability set is that nothing was assigned.
      final destination = resolve(user: _bareTenant);
      expect(destination, isNot(StartupDestination.accountSuspended));
      expect(destination, isNot(StartupDestination.accountRevoked));
      expect(destination, isNot(StartupDestination.firstTimeSetup));
    });

    test('a scoped grant in one detachment is enough to enter the app', () {
      final scoped = _tenant(const Capabilities(scoped: {
        'd_1': {Cap.detachmentView}
      }));
      expect(resolve(user: scoped), StartupDestination.tenantSurface);
    });

    test('a scoped entry granting nothing counts as nothing held', () {
      final empty = _tenant(const Capabilities(scoped: {'d_1': {}}));
      expect(empty.capabilities.hasAny, isFalse);
      expect(resolve(user: empty), StartupDestination.tenantNoAccess);
    });
  });

  group('account and tenant lifecycle', () {
    test('a revoked account', () {
      expect(
        resolve(
          user: _mainAdmin,
          access: const SessionAccess(account: AccountStatus.revoked),
        ),
        StartupDestination.accountRevoked,
      );
    });

    test('a suspended account', () {
      expect(
        resolve(
          user: _mainAdmin,
          access: const SessionAccess(account: AccountStatus.suspended),
        ),
        StartupDestination.accountSuspended,
      );
    });

    test('a deleted tenant', () {
      expect(
        resolve(
          user: _mainAdmin,
          access: const SessionAccess(tenant: SaasTenantStatus.deleted),
        ),
        StartupDestination.tenantDeleted,
      );
    });

    test('a suspended tenant', () {
      expect(
        resolve(
          user: _mainAdmin,
          access: const SessionAccess(tenant: SaasTenantStatus.suspended),
        ),
        StartupDestination.tenantSuspended,
      );
    });

    test('a deletion-pending tenant', () {
      expect(
        resolve(
          user: _mainAdmin,
          access: const SessionAccess(
            tenant: SaasTenantStatus.deletionPending,
          ),
        ),
        StartupDestination.tenantDeletionPending,
      );
    });

    test('tenant lifecycle never blocks the Super Admin platform surface', () {
      for (final status in SaasTenantStatus.values) {
        expect(
          resolve(
            user: _superAdmin,
            access: SessionAccess(tenant: status),
          ),
          StartupDestination.platformSurface,
          reason: status.wire,
        );
      }
    });

    test('an unlinked account goes to setup', () {
      expect(
        resolve(
          user: _mainAdmin,
          access: const SessionAccess(account: AccountStatus.pendingSetup),
        ),
        StartupDestination.firstTimeSetup,
      );
    });

    test('the account outranks its customer', () {
      // A person whose own access was withdrawn is told that, not that their
      // organisation is unavailable.
      expect(
        resolve(
          user: _mainAdmin,
          access: const SessionAccess(
            account: AccountStatus.revoked,
            tenant: SaasTenantStatus.suspended,
          ),
        ),
        StartupDestination.accountRevoked,
      );
    });

    test('a blocked account is not invited to finish setting up', () {
      expect(
        resolve(
          user: _mainAdmin,
          access: const SessionAccess(
            account: AccountStatus.pendingSetup,
            tenant: SaasTenantStatus.suspended,
          ),
        ),
        StartupDestination.tenantSuspended,
      );
    });
  });

  group('customer demo is separate from every real surface', () {
    test('an active demo gets the demo surface', () {
      expect(
        resolve(
          user: _customerDemo,
          access: const SessionAccess(demo: DemoMode.active),
        ),
        StartupDestination.demoActive,
      );
    });

    test('an expired demo gets its own screen', () {
      expect(
        resolve(
          user: _customerDemo,
          access: const SessionAccess(demo: DemoMode.expired),
        ),
        StartupDestination.demoExpired,
      );
    });

    test('a real persona cannot borrow Customer Demo access state', () {
      for (final user in [_mainAdmin, _simpleAdmin, _superAdmin]) {
        for (final mode in [DemoMode.active, DemoMode.expired]) {
          final destination =
              resolve(user: user, access: SessionAccess(demo: mode));
          expect(destination, StartupDestination.invalidSession,
              reason: '${user.role.wire} + ${mode.wire}');
        }
      }
    });

    test('Customer Demo without demo state fails closed', () {
      expect(resolve(user: _customerDemo), StartupDestination.invalidSession);
    });

    test('a demo session is not judged by the tenant lifecycle', () {
      // A demo has no customer, so a tenant status cannot describe it.
      expect(
        resolve(
          user: _customerDemo,
          access: const SessionAccess(
            demo: DemoMode.active,
            tenant: SaasTenantStatus.deleted,
          ),
        ),
        StartupDestination.demoActive,
      );
    });
  });

  group('priority', () {
    test('a mandatory update outranks every session state, and every role', () {
      for (final user in [_mainAdmin, _simpleAdmin, _superAdmin, null]) {
        expect(
          resolve(user: user, upgradeBlocks: true),
          StartupDestination.forcedUpgrade,
          reason: '${user?.role.wire}',
        );
      }
      expect(
        resolve(
          gate: AuthGate.signedOut,
          upgradeBlocks: true,
        ),
        StartupDestination.forcedUpgrade,
      );
    });

    test('a restore in flight outranks everything but the update gate', () {
      expect(
        resolve(gate: AuthGate.restoring, user: _mainAdmin),
        StartupDestination.restoring,
      );
    });

    test('an unfinished MFA challenge outranks both product surfaces', () {
      for (final user in [_mainAdmin, _superAdmin]) {
        expect(
          resolve(
            user: user,
            access: const SessionAccess(mfaRequired: true),
          ),
          StartupDestination.mfaRequired,
          reason: user.role.wire,
        );
      }
    });
  });

  group('the route table has exactly one spelling of every location', () {
    test('no two destinations share a location', () {
      final locations = [
        for (final d in StartupDestination.values)
          if (d.location case final l?) l,
      ];
      expect(locations.toSet().length, locations.length);
    });

    test('the page constants agree with the classifier', () {
      // Three places declare a path as a `const String` because a const field
      // cannot read an enum member. This is what stops them drifting.
      expect(StartupDestination.restoring.location, StartupPage.location);
      expect(
          StartupDestination.platformSurface.location, PlatformShell.location);
      expect(StartupDestination.forcedUpgrade.location,
          UpgradeRequiredPage.location);
    });

    test('every status-screen destination has a page behind it', () {
      // A typed state pointing at a dead route is the failure `§37` names:
      // the router would redirect to a location with nothing registered.
      const owned = {
        StartupDestination.invalidSession,
        StartupDestination.unsupportedAccessState,
        StartupDestination.tenantNoAccess,
        StartupDestination.accountSuspended,
        StartupDestination.accountRevoked,
        StartupDestination.tenantSuspended,
        StartupDestination.tenantDeletionPending,
        StartupDestination.tenantDeleted,
        StartupDestination.emailVerification,
        StartupDestination.teamLink,
        StartupDestination.firstTimeSetup,
        // `demoActive` is deliberately absent: the demo trial runs the tenant
        // application from an isolated workspace, so it has no location of
        // its own and therefore no status page behind it.
        StartupDestination.demoExpired,
      };
      for (final destination in owned) {
        expect(
          startupStatusPages.containsKey(destination.location),
          isTrue,
          reason: '${destination.name} has no page',
        );
      }
      expect(startupStatusPages.length, owned.length);
    });
  });
}

const _superAdmin = AuthUser(
  id: 'u_platform',
  name: 'مدير منصة',
  email: 'nullmod.dev@gmail.com',
  role: AuthRole.superAdmin,
  saasTenantId: null,
  capabilities: Capabilities.none,
  orgName: 'MTM',
);

AuthUser _tenant(Capabilities grant, {AuthRole role = AuthRole.mainAdmin}) =>
    AuthUser(
      id: 'u_tenant',
      name: 'مشرف',
      email: 'admin@mtm.org',
      role: role,
      saasTenantId: 'saas_test',
      capabilities: grant,
      orgName: 'MTM',
    );

final _mainAdmin = _tenant(const Capabilities(global: Cap.all));
final _simpleAdmin = _tenant(
  const Capabilities(scoped: {
    'd_1': {Cap.detachmentView, Cap.memberView}
  }),
  role: AuthRole.admin,
);
final _bareTenant = _tenant(Capabilities.none);

const _customerDemo = AuthUser(
  id: 'u_customer_demo',
  name: 'مساحة تجريبية',
  email: 'customer-demo@mtm.app',
  role: AuthRole.customerDemo,
  saasTenantId: null,
  capabilities: Capabilities.none,
  orgName: 'MTM Demo',
);
